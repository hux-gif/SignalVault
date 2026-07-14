// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {AllocationSnapshotV2, RouterStateV2} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {RiskConfigurationV2} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {InstrumentedStrategyAdapterV2} from "./mocks/InstrumentedStrategyAdapterV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";

contract StrategyRouterV2AccountingHarness is StrategyRouterV2 {
    constructor(IERC20 asset_, address vaultOwner_) StrategyRouterV2(asset_, vaultOwner_) {}

    function setRecoveredForTest() external {
        upshiftRecovered = true;
    }
}

contract MalformedAccountingAdapterV2 {
    address public immutable asset;
    address public immutable router;
    address public immutable positionToken;

    constructor(address asset_, address router_, address positionToken_) {
        asset = asset_;
        router = router_;
        positionToken = positionToken_;
    }

    fallback() external {
        assembly ("memory-safe") {
            mstore(0, 1)
            return(31, 1)
        }
    }
}

contract StrategyRouterV2AccountingTest is Test {
    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    StrategyRouterV2 internal router;
    InstrumentedStrategyAdapterV2 internal idle;
    InstrumentedStrategyAdapterV2 internal upshift;
    address internal owner = address(0xA11CE);

    function setUp() public {
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        router = new StrategyRouterV2AccountingHarness(IERC20(address(asset)), owner);
        idle = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(router), address(asset)
        );
        upshift = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(router), address(lpToken)
        );

        vm.prank(owner);
        router.configureAdapters(address(upshift), address(idle));
    }

    function testTotalAssetsUsesRouterAndAdapterNetValues() external {
        asset.mint(address(router), 5);
        idle.setPositionValues(20, 30, 15, 20);
        asset.mint(address(upshift), 7);
        upshift.setPositionValues(95, 99, 40, 10_000);

        assertEq(router.totalAssets(), 127);
    }

    function testGrossAssetsUsesGrossTelemetryInsteadOfNetValues() external {
        asset.mint(address(router), 10);
        idle.setPositionValues(100, 100, 60, 100);
        upshift.setPositionValues(95, 100, 20, 100);

        assertEq(router.totalAssets(), 205);
        assertEq(router.grossAssets(), 210);
    }

    function testAvailableLiquidityIsIndependentFromNetAssetValue() external {
        _freezeRouter();
        asset.mint(address(router), 10);
        idle.setPositionValues(100, 100, 60, 100);
        upshift.setPositionValues(100, 100, 20, 100);

        assertEq(router.totalAssets(), 210);
        assertEq(router.availableLiquidity(), 90);
    }

    function testAllocationSeparatesDirectBufferFromStrategyExposure() external {
        asset.mint(address(router), 20);
        idle.setPositionValues(30, 30, 30, 30);
        asset.mint(address(upshift), 10);
        upshift.setPositionValues(50, 55, 40, 123);

        AllocationSnapshotV2 memory snapshot = router.allocation();

        assertEq(snapshot.totalNetAssets, 110);
        assertEq(snapshot.totalGrossAssets, 115);
        assertEq(snapshot.routerDirectAssets, 20);
        assertEq(snapshot.idleAssets, 30);
        assertEq(snapshot.upshiftDirectAssets, 10);
        assertEq(snapshot.upshiftPositionNetAssets, 50);
        assertEq(snapshot.upshiftPositionGrossAssets, 55);
        assertEq(snapshot.upshiftPositionShares, 123);
        assertEq(snapshot.idleBps, 2_727);
        assertEq(snapshot.upshiftBps, 4_545);
    }

    function testStrategyStateRequiresFrozenConfigurationAndLiveStatus() external {
        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftUnavailable));

        _freezeRouter();
        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.Operational));

        upshift.setStatus(true, false);
        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftUnavailable));

        upshift.setStatusReverts(true);
        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftUnavailable));
    }

    function testRecoveredAccountingUsesOnlyObservedUpshiftUnderlying() external {
        asset.mint(address(router), 5);
        idle.setPositionValues(20, 20, 20, 20);
        asset.mint(address(upshift), 7);
        upshift.setPositionValues(95, 100, 50, type(uint256).max);
        upshift.setViewReverts(true, true, true);
        StrategyRouterV2AccountingHarness(address(router)).setRecoveredForTest();

        assertEq(router.totalAssets(), 32);
        assertEq(router.grossAssets(), 32);
        assertEq(router.availableLiquidity(), 32);

        AllocationSnapshotV2 memory snapshot = router.allocation();
        assertEq(snapshot.upshiftDirectAssets, 7);
        assertEq(snapshot.upshiftPositionNetAssets, 0);
        assertEq(snapshot.upshiftPositionGrossAssets, 0);
        assertEq(snapshot.upshiftPositionShares, 0);
        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftRecovered));
    }

    function testUnavailableUpshiftLiquidityUsesOnlyProvablyWithdrawableTiers() external {
        _freezeRouter();
        asset.mint(address(router), 10);
        idle.setPositionValues(100, 100, 60, 100);
        asset.mint(address(upshift), 5);
        upshift.setPositionValues(100, 100, 20, 100);
        upshift.setStatus(true, false);

        assertEq(router.availableLiquidity(), 70);
    }

    function testZeroNavReturnsZeroAllocationAndMakesNoStateChangingCalls() external view {
        assertEq(router.totalAssets(), 0);
        assertEq(router.grossAssets(), 0);
        assertEq(router.availableLiquidity(), 0);

        AllocationSnapshotV2 memory snapshot = router.allocation();
        assertEq(snapshot.totalNetAssets, 0);
        assertEq(snapshot.totalGrossAssets, 0);
        assertEq(snapshot.idleBps, 0);
        assertEq(snapshot.upshiftBps, 0);
        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testDirectOnlyBufferHasZeroStrategyAllocation() external {
        asset.mint(address(router), 7);

        AllocationSnapshotV2 memory snapshot = router.allocation();
        assertEq(snapshot.totalNetAssets, 7);
        assertEq(snapshot.routerDirectAssets, 7);
        assertEq(snapshot.idleBps, 0);
        assertEq(snapshot.upshiftBps, 0);
    }

    function testDonationsAreCountedOnceWithoutCreatingStrategyExposure() external {
        _freezeRouter();
        idle.setPositionValues(30, 30, 30, 30);
        upshift.setPositionValues(50, 55, 40, 50);
        asset.mint(address(router), 11);
        asset.mint(address(idle), 13);
        asset.mint(address(upshift), 17);

        assertEq(router.totalAssets(), 121);
        assertEq(router.grossAssets(), 126);
        assertEq(router.availableLiquidity(), 111);

        AllocationSnapshotV2 memory snapshot = router.allocation();
        assertEq(snapshot.routerDirectAssets, 11);
        assertEq(snapshot.idleAssets, 43);
        assertEq(snapshot.upshiftDirectAssets, 17);
        assertEq(snapshot.upshiftPositionNetAssets, 50);
        assertEq(snapshot.upshiftPositionGrossAssets, 55);
    }

    function testPositionSharesAreNeverAddedAsUnderlyingAssets() external {
        idle.setPositionValues(0, 0, 0, type(uint256).max);
        upshift.setPositionValues(0, 0, 0, type(uint256).max);

        assertEq(router.totalAssets(), 0);
        assertEq(router.grossAssets(), 0);
        assertEq(router.allocation().upshiftPositionShares, type(uint256).max);
    }

    function testAdapterReportsBelowObservedDirectUnderlyingRevert() external {
        asset.mint(address(upshift), 10);
        upshift.setExactReportedValues(9, 9, 9);

        vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
        router.totalAssets();
        vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
        router.grossAssets();

        _freezeRouter();
        vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
        router.availableLiquidity();
        vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
        router.allocation();
    }

    function testIdleReportsBelowObservedDirectUnderlyingRevert() external {
        asset.mint(address(idle), 10);
        idle.setExactReportedValues(9, 9, 9);

        vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
        router.totalAssets();
        vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
        router.grossAssets();

        _freezeRouter();
        vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
        router.availableLiquidity();
        vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
        router.allocation();
    }

    function testAdapterAccountingErrorsPropagateWithoutFallback() external {
        idle.setViewReverts(true, false, false);
        vm.expectRevert(InstrumentedStrategyAdapterV2.ForcedViewRevert.selector);
        router.totalAssets();
        idle.setViewReverts(false, false, false);

        upshift.setViewReverts(true, false, false);
        vm.expectRevert(InstrumentedStrategyAdapterV2.ForcedViewRevert.selector);
        router.totalAssets();
        upshift.setViewReverts(false, false, false);

        idle.setViewReverts(false, true, false);
        vm.expectRevert(InstrumentedStrategyAdapterV2.ForcedViewRevert.selector);
        router.grossAssets();
        idle.setViewReverts(false, false, false);

        upshift.setViewReverts(false, true, false);
        vm.expectRevert(InstrumentedStrategyAdapterV2.ForcedViewRevert.selector);
        router.grossAssets();
        upshift.setViewReverts(false, false, false);

        _freezeRouter();
        idle.setViewReverts(false, false, true);
        vm.expectRevert(InstrumentedStrategyAdapterV2.ForcedViewRevert.selector);
        router.availableLiquidity();
        idle.setViewReverts(false, false, false);

        upshift.setViewReverts(false, false, true);
        vm.expectRevert(InstrumentedStrategyAdapterV2.ForcedViewRevert.selector);
        router.availableLiquidity();
    }

    function testLifecycleMatrixFailsOnlyWhenAdaptersAreMissing() external {
        StrategyRouterV2 unconfigured = new StrategyRouterV2(IERC20(address(asset)), owner);
        vm.expectRevert(StrategyRouterV2.ConfigurationIncomplete.selector);
        unconfigured.totalAssets();
        vm.expectRevert(StrategyRouterV2.ConfigurationIncomplete.selector);
        unconfigured.grossAssets();
        vm.expectRevert(StrategyRouterV2.ConfigurationIncomplete.selector);
        unconfigured.availableLiquidity();
        vm.expectRevert(StrategyRouterV2.ConfigurationIncomplete.selector);
        unconfigured.allocation();
        assertEq(uint256(unconfigured.strategyState()), uint256(RouterStateV2.UpshiftUnavailable));

        vm.prank(owner);
        unconfigured.configureRisk(_validRisk());
        vm.expectRevert(StrategyRouterV2.ConfigurationIncomplete.selector);
        unconfigured.totalAssets();

        assertEq(router.totalAssets(), 0);
        assertEq(router.grossAssets(), 0);
        assertEq(router.availableLiquidity(), 0);
        assertEq(router.allocation().totalNetAssets, 0);

        vm.prank(owner);
        router.configureRisk(_validRisk());
        assertEq(router.totalAssets(), 0);
        assertEq(router.allocation().totalNetAssets, 0);
    }

    function testMalformedAdapterReturnDataFailsClosed() external {
        StrategyRouterV2 malformedRouter = new StrategyRouterV2(IERC20(address(asset)), owner);
        InstrumentedStrategyAdapterV2 validIdle = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(malformedRouter), address(asset)
        );
        MalformedAccountingAdapterV2 malformed = new MalformedAccountingAdapterV2(
            address(asset), address(malformedRouter), address(lpToken)
        );

        vm.prank(owner);
        malformedRouter.configureAdapters(address(malformed), address(validIdle));

        vm.expectRevert();
        malformedRouter.totalAssets();
        vm.expectRevert();
        malformedRouter.grossAssets();
        vm.expectRevert();
        malformedRouter.allocation();
    }

    function testAllocationRoundingUsesIndependentFloorAgainstTotalNetNav() external {
        idle.setPositionValues(1, 1, 1, 1);
        upshift.setPositionValues(2, 2, 2, 2);

        AllocationSnapshotV2 memory snapshot = router.allocation();
        assertEq(snapshot.idleBps, 3_333);
        assertEq(snapshot.upshiftBps, 6_666);
        assertEq(uint256(snapshot.idleBps) + snapshot.upshiftBps, 9_999);
    }

    function testAllocationCoversAllIdleAllUpshiftHalfAndDust() external {
        idle.setPositionValues(1, 1, 1, 1);
        assertEq(router.allocation().idleBps, 10_000);
        assertEq(router.allocation().upshiftBps, 0);

        idle.setPositionValues(0, 0, 0, 0);
        upshift.setPositionValues(1, 1, 1, 1);
        assertEq(router.allocation().idleBps, 0);
        assertEq(router.allocation().upshiftBps, 10_000);

        idle.setPositionValues(1, 1, 1, 1);
        assertEq(router.allocation().idleBps, 5_000);
        assertEq(router.allocation().upshiftBps, 5_000);

        asset.mint(address(router), 1);
        assertEq(router.allocation().idleBps, 3_333);
        assertEq(router.allocation().upshiftBps, 3_333);
    }

    function testAllocationUsesFullPrecisionForMaximumRepresentableSinglePosition() external {
        idle.setPositionValues(type(uint256).max, type(uint256).max, 0, 0);

        AllocationSnapshotV2 memory snapshot = router.allocation();
        assertEq(snapshot.totalNetAssets, type(uint256).max);
        assertEq(snapshot.idleBps, 10_000);
    }

    function testAccountingSumOverflowReverts() external {
        idle.setPositionValues(type(uint256).max, type(uint256).max, 0, 0);
        upshift.setPositionValues(1, 1, 0, 0);

        vm.expectRevert(stdError.arithmeticError);
        router.totalAssets();
        vm.expectRevert(stdError.arithmeticError);
        router.grossAssets();
        vm.expectRevert(stdError.arithmeticError);
        router.allocation();
    }

    function testProtocolStatusMaximumIsNeverAddedToAssetAccounting() external {
        _freezeRouter();

        assertEq(router.totalAssets(), 0);
        assertEq(router.grossAssets(), 0);
        assertEq(router.availableLiquidity(), 0);
    }

    function testAccountingViewsCreateNoApprovalOrStateChangingAdapterCall() external {
        _freezeRouter();
        idle.setPositionValues(20, 20, 20, 20);
        upshift.setPositionValues(30, 31, 10, 30);

        router.totalAssets();
        router.grossAssets();
        router.availableLiquidity();
        router.allocation();

        assertEq(asset.allowance(address(router), address(idle)), 0);
        assertEq(asset.allowance(address(router), address(upshift)), 0);
        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testInstrumentedExecutionConfigurationRetainsEveryDelta() external {
        upshift.setDepositExecution(11, 12, 13, 14);
        upshift.setWithdrawalExecution(21, 22, 23);

        assertEq(upshift.depositRouterDebit(), 11);
        assertEq(upshift.depositAdapterCredit(), 12);
        assertEq(upshift.depositSharesMinted(), 13);
        assertEq(upshift.depositReturnedShares(), 14);
        assertEq(upshift.withdrawalAdapterDebit(), 21);
        assertEq(upshift.withdrawalRouterCredit(), 22);
        assertEq(upshift.withdrawalReturnedAssets(), 23);
    }

    function _freezeRouter() internal {
        vm.startPrank(owner);
        router.configureRisk(_validRisk());
        router.bindVault(address(new RouterBoundVaultMockV2(owner)));
        vm.stopPrank();
    }

    function _validRisk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 0,
            minimumAllocationChangeBps: 100,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }
}
