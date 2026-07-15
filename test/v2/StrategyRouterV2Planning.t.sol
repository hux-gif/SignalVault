// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {
    IStrategyRouterV2,
    RebalanceBlockerV2,
    RebalancePlanV2
} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2
} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {IStrategyAdapterV2} from "../../src/v2/interfaces/IStrategyAdapterV2.sol";
import {InstrumentedStrategyAdapterV2} from "./mocks/InstrumentedStrategyAdapterV2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";

contract StrategyRouterV2PlanningHarness is StrategyRouterV2 {
    constructor(IERC20 asset_, address vaultOwner_) StrategyRouterV2(asset_, vaultOwner_) {}

    function setRecoveredForTest() external {
        upshiftRecovered = true;
    }
}

contract StrategyRouterV2PlanningTest is Test {
    using stdStorage for StdStorage;

    uint16 private constant _BPS = 10_000;

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    StrategyRouterV2PlanningHarness internal router;
    InstrumentedStrategyAdapterV2 internal idle;
    InstrumentedStrategyAdapterV2 internal upshift;
    address internal owner = address(0xA11CE);

    function setUp() public {
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        router = new StrategyRouterV2PlanningHarness(IERC20(address(asset)), owner);
        idle = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(router), address(asset)
        );
        upshift = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(router), address(lpToken)
        );

        vm.startPrank(owner);
        router.configureAdapters(address(upshift), address(idle));
        router.configureRisk(_risk());
        router.bindVault(address(new RouterBoundVaultMockV2(owner)));
        vm.stopPrank();
    }

    function testDirectBufferSatisfiesIdleDeficitWithoutUpshiftRedemption() external {
        asset.mint(address(router), 20);
        idle.setPositionValues(30, 30, 30, 30);
        upshift.setPositionValues(50, 50, 50, 50);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _validLimits());

        assertTrue(plan.feasible);
        assertEq(plan.idleDepositAssets, 20);
        assertEq(plan.upshiftSharesToRedeem, 0);
        assertEq(plan.upshiftDepositAssets, 0);
        assertEq(plan.targetIdleAssets + plan.targetUpshiftAssets, plan.projectedTotalAssetsAfter);
    }

    function testDirectBufferTurnoverCountsDonationAtMinimumBoundary() external {
        asset.mint(address(router), 1);
        idle.setPositionValues(49, 49, 49, 49);
        upshift.setPositionValues(50, 50, 50, 50);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _validLimits());

        assertTrue(plan.feasible);
        assertEq(plan.idleDepositAssets, 1);
        assertEq(plan.upshiftSharesToRedeem, 0);
    }

    function testExactNoOpIsFeasibleAndMakesNoPreviewOrStateChangingCalls() external {
        idle.setPositionValues(50, 50, 50, 50);
        upshift.setPositionValues(50, 50, 50, 50);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _validLimits());

        assertTrue(plan.feasible);
        assertEq(uint256(plan.blocker), uint256(RebalanceBlockerV2.None));
        assertEq(plan.idleWithdrawAssets, 0);
        assertEq(plan.upshiftSharesToRedeem, 0);
        assertEq(plan.idleDepositAssets, 0);
        assertEq(plan.upshiftDepositAssets, 0);
        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
        assertEq(IStrategyRouterV2(address(router)).lastRebalanceTimestamp(), 0);
    }

    function testInitialBufferAllocationCanDepositIntoBothStrategies() external {
        asset.mint(address(router), 100);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(6_000), _validLimits());

        assertTrue(plan.feasible);
        assertEq(plan.idleDepositAssets, 40);
        assertEq(plan.upshiftDepositAssets, 60);
        assertEq(plan.previewedUpshiftSharesOut, 60);
        assertEq(plan.previewedUpshiftNetAdded, 60);
        assertEq(plan.idleWithdrawAssets, 0);
        assertEq(plan.upshiftSharesToRedeem, 0);
    }

    function testUnsupportedOrMalformedAllocationReturnsInvalidAllocation() external view {
        _assertBlocker(
            AllocationV2({upshiftBps: 4_000, firelightBps: 1, sparkdexBps: 0, idleBps: 5_999}),
            _validLimits(),
            RebalanceBlockerV2.InvalidAllocation
        );
        _assertBlocker(
            AllocationV2({upshiftBps: 4_000, firelightBps: 0, sparkdexBps: 1, idleBps: 5_999}),
            _validLimits(),
            RebalanceBlockerV2.InvalidAllocation
        );
        _assertBlocker(
            AllocationV2({upshiftBps: 4_999, firelightBps: 0, sparkdexBps: 0, idleBps: 5_000}),
            _validLimits(),
            RebalanceBlockerV2.InvalidAllocation
        );
    }

    function testSignedLimitsCannotWeakenFrozenRisk() external view {
        RebalanceLimitsV2 memory limits = _validLimits();
        limits.maximumRebalanceLossBps = 101;
        _assertBlocker(_allocation(5_000), limits, RebalanceBlockerV2.InvalidSignedLimits);

        limits = _validLimits();
        limits.maximumPreviewDeviationBps = 101;
        _assertBlocker(_allocation(5_000), limits, RebalanceBlockerV2.InvalidSignedLimits);

        limits = _validLimits();
        limits.allocationToleranceBps = 101;
        _assertBlocker(_allocation(5_000), limits, RebalanceBlockerV2.InvalidSignedLimits);
    }

    function testNonzeroTurnoverBelowMinimumIsInfeasible() external {
        idle.setPositionValues(5_050, 5_050, 5_050, 5_050);
        upshift.setPositionValues(4_950, 4_950, 4_950, 4_950);

        _assertBlocker(_allocation(5_000), _validLimits(), RebalanceBlockerV2.ChangeBelowMinimum);
    }

    function testCooldownBlocksAQualifyingNonzeroPlan() external {
        vm.warp(10_000);
        stdstore.target(address(router)).sig(router.lastRebalanceTimestamp.selector)
            .checked_write(9_999);
        assertEq(router.lastRebalanceTimestamp(), 9_999);
        idle.setPositionValues(8_000, 8_000, 8_000, 8_000);
        upshift.setPositionValues(2_000, 2_000, 2_000, 2_000);

        _assertBlocker(_allocation(5_000), _validLimits(), RebalanceBlockerV2.CooldownActive);
    }

    function testUpshiftUnavailableMakesPlanInfeasible() external {
        idle.setPositionValues(50, 50, 50, 50);
        upshift.setPositionValues(50, 50, 50, 50);
        upshift.setStatus(true, false);

        _assertBlocker(_allocation(5_000), _validLimits(), RebalanceBlockerV2.UpshiftUnavailable);
    }

    function testRecoveredRouterRejectsEvenZeroUpshiftTarget() external {
        router.setRecoveredForTest();

        _assertBlocker(_allocation(0), _validLimits(), RebalanceBlockerV2.RecoveredTargetForbidden);
    }

    function testIncreaseMovesOnlyIdleDeltaIntoUpshift() external {
        idle.setPositionValues(80, 80, 80, 80);
        upshift.setPositionValues(20, 20, 20, 20);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewDeposit, (30)), 1);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _validLimits());

        assertTrue(plan.feasible);
        assertEq(plan.idleWithdrawAssets, 30);
        assertEq(plan.upshiftDepositAssets, 30);
        assertEq(plan.previewedUpshiftSharesOut, 30);
        assertEq(plan.previewedUpshiftNetAdded, 30);
        assertEq(plan.upshiftSharesToRedeem, 0);
    }

    function testDecreaseRedeemsOnlyProportionalUpshiftShares() external {
        idle.setPositionValues(20, 20, 20, 20);
        upshift.setPositionValues(80, 80, 80, 80);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewRedeem, (30)), 1);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewRedeem, (50)), 1);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _validLimits());

        assertTrue(plan.feasible);
        assertEq(plan.upshiftSharesToRedeem, 30);
        assertEq(plan.previewedUpshiftAssetsOut, 30);
        assertEq(plan.requiredProtocolLiquidity, 30);
        assertEq(plan.idleDepositAssets, 30);
        assertEq(plan.upshiftDepositAssets, 0);
        assertEq(plan.upshiftMinAssetsOut, 29);
    }

    function testDecreaseRefinementUsesActualPositionReduction() external {
        idle.setPositionValues(40, 40, 40, 40);
        upshift.setPositionValues(60, 60, 60, 60);
        upshift.setRedeemPreview(10, 12, 12);
        upshift.setRedeemPreview(50, 50, 50);
        upshift.setRedeemPreview(9, 10, 10);
        upshift.setRedeemPreview(51, 50, 50);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewRedeem, (10)), 1);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewRedeem, (50)), 1);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewRedeem, (9)), 1);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewRedeem, (51)), 1);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _zeroTolerance());

        assertTrue(plan.feasible);
        assertEq(plan.upshiftSharesToRedeem, 9);
        assertEq(plan.previewedUpshiftAssetsOut, 10);
        assertEq(plan.idleDepositAssets, 10);
        assertEq(plan.targetIdleAssets, 50);
        assertEq(plan.targetUpshiftAssets, 50);
    }

    function testIncreaseUsesOnlyInitialCandidateAndOneRefinement() external {
        idle.setPositionValues(80, 80, 80, 80);
        upshift.setPositionValues(20, 20, 20, 20);
        upshift.setDepositPreview(30, 20, 20);
        upshift.setDepositPreview(38, 22, 22);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewDeposit, (30)), 1);
        vm.expectCall(address(upshift), abi.encodeCall(IStrategyAdapterV2.previewDeposit, (38)), 1);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _zeroTolerance());

        assertTrue(plan.feasible);
        assertEq(plan.upshiftDepositAssets, 38);
        assertEq(plan.previewedUpshiftNetAdded, 22);
        assertEq(plan.projectedTotalAssetsAfter, 84);
        assertEq(plan.targetIdleAssets, 42);
        assertEq(plan.targetUpshiftAssets, 42);
    }

    function testZeroDepositPreviewIsInfeasible() external {
        idle.setPositionValues(80, 80, 80, 80);
        upshift.setPositionValues(20, 20, 20, 20);
        upshift.setDepositPreview(30, 0, 0);

        _assertBlocker(_allocation(5_000), _validLimits(), RebalanceBlockerV2.ZeroPreview);
    }

    function testZeroRemainingPositionPreviewIsInfeasible() external {
        idle.setPositionValues(40, 40, 40, 40);
        upshift.setPositionValues(60, 60, 60, 60);
        upshift.setRedeemPreview(10, 10, 10);
        upshift.setRedeemPreview(50, 0, 0);

        _assertBlocker(_allocation(5_000), _validLimits(), RebalanceBlockerV2.ZeroPreview);
    }

    function testZeroObservedPositionReductionIsInfeasible() external {
        idle.setPositionValues(40, 40, 40, 40);
        upshift.setPositionValues(60, 60, 60, 60);
        upshift.setRedeemPreview(10, 10, 10);
        upshift.setRedeemPreview(50, 60, 60);

        _assertBlocker(_allocation(5_000), _validLimits(), RebalanceBlockerV2.SolverDidNotConverge);
    }

    function testIncreasingObservedRemainingPositionIsInfeasible() external {
        idle.setPositionValues(40, 40, 40, 40);
        upshift.setPositionValues(60, 60, 60, 60);
        upshift.setRedeemPreview(10, 10, 10);
        upshift.setRedeemPreview(50, 61, 61);

        _assertBlocker(_allocation(5_000), _validLimits(), RebalanceBlockerV2.SolverDidNotConverge);
    }

    function testRefinedDecreaseCandidateAboveHeldSharesIsInfeasible() external {
        upshift.setPositionValues(100, 100, 100, 10);
        upshift.setRedeemPreview(4, 1, 1);
        upshift.setRedeemPreview(6, 99, 99);

        _assertBlocker(
            _allocation(6_000), _zeroTolerance(), RebalanceBlockerV2.SolverDidNotConverge
        );
    }

    function testNonconvergentSecondCandidateIsInfeasible() external {
        idle.setPositionValues(80, 80, 80, 80);
        upshift.setPositionValues(20, 20, 20, 20);
        upshift.setDepositPreview(30, 20, 20);
        upshift.setDepositPreview(38, 21, 21);

        _assertBlocker(
            _allocation(5_000), _zeroTolerance(), RebalanceBlockerV2.SolverDidNotConverge
        );
    }

    function testDecreaseRequiresStrictLiveProtocolLiquidity() external {
        idle.setPositionValues(20, 20, 20, 20);
        upshift.setPositionValues(80, 80, 20, 80);

        _assertBlocker(_allocation(5_000), _validLimits(), RebalanceBlockerV2.InsufficientLiquidity);
    }

    function testProjectedPostNavRecognizesImmediateUpshiftFeeReserve() external {
        idle.setPositionValues(80, 80, 80, 80);
        upshift.setPositionValues(20, 20, 20, 20);
        upshift.setDepositPreview(30, 20, 20);
        upshift.setDepositPreview(38, 22, 22);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _zeroTolerance());

        assertTrue(plan.feasible);
        assertEq(plan.totalAssetsBefore, 100);
        assertEq(plan.projectedTotalAssetsAfter, 84);
        assertEq(plan.targetIdleAssets + plan.targetUpshiftAssets, 84);
    }

    function testTargetDivisionRemainderIsAssignedToUpshift() external {
        asset.mint(address(router), 2);
        idle.setPositionValues(1, 1, 1, 1);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(6_667), _validLimits());

        assertTrue(plan.feasible);
        assertEq(plan.targetIdleAssets, 0);
        assertEq(plan.targetUpshiftAssets, 3);
        assertEq(plan.targetIdleAssets + plan.targetUpshiftAssets, 3);
    }

    function testSixDecimalSmallestUnitsRemainIntegerExact() external {
        asset.mint(address(router), 500_000);
        idle.setPositionValues(250_000, 250_000, 250_000, 250_000);
        upshift.setPositionValues(250_000, 250_000, 250_000, 250_000);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _validLimits());

        assertTrue(plan.feasible);
        assertEq(plan.totalAssetsBefore, 1_000_000);
        assertEq(plan.idleDepositAssets, 250_000);
        assertEq(plan.upshiftDepositAssets, 250_000);
    }

    function testFullPrecisionTargetMathHandlesNearUint256Limit() external {
        idle.setPositionValues(
            type(uint256).max - 1, type(uint256).max - 1, 0, type(uint256).max - 1
        );

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(0), _validLimits());

        assertTrue(plan.feasible);
        assertEq(plan.totalAssetsBefore, type(uint256).max - 1);
        assertEq(plan.targetIdleAssets, type(uint256).max - 1);
        assertEq(plan.targetUpshiftAssets, 0);
    }

    function _assertBlocker(
        AllocationV2 memory target,
        RebalanceLimitsV2 memory limits,
        RebalanceBlockerV2 expected
    ) internal view {
        RebalancePlanV2 memory plan = router.previewRebalance(target, limits);
        assertFalse(plan.feasible);
        assertEq(uint256(plan.blocker), uint256(expected));
    }

    function _allocation(uint16 upshiftBps) internal pure returns (AllocationV2 memory) {
        return AllocationV2({
            upshiftBps: upshiftBps, firelightBps: 0, sparkdexBps: 0, idleBps: _BPS - upshiftBps
        });
    }

    function _validLimits() internal pure returns (RebalanceLimitsV2 memory) {
        return RebalanceLimitsV2({
            minimumPostNAV: 0,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }

    function _zeroTolerance() internal pure returns (RebalanceLimitsV2 memory limits) {
        limits = _validLimits();
        limits.allocationToleranceBps = 0;
    }

    function _risk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 1 hours,
            minimumAllocationChangeBps: 100,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }
}
