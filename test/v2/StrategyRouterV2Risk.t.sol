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
import {InstrumentedStrategyAdapterV2} from "./mocks/InstrumentedStrategyAdapterV2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {ReentrantRouterVaultV2} from "./StrategyRouterV2Execution.t.sol";

contract StrategyRouterV2RiskTest is Test {
    using stdStorage for StdStorage;

    uint16 private constant _BPS = 10_000;
    bytes32 private constant _EXECUTION_ID = keccak256("TASK_6_RISK");

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    StrategyRouterV2 internal router;
    InstrumentedStrategyAdapterV2 internal idle;
    InstrumentedStrategyAdapterV2 internal upshift;
    ReentrantRouterVaultV2 internal vault;
    address internal owner = address(0xA11CE);

    function setUp() public {
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        (router, idle, upshift, vault) = _deploy(_risk());
    }

    function testLossBoundaryUsesPreNetNavAndTenThousandDenominator() external {
        asset.mint(address(router), 1_000_000);
        upshift.setDepositPreview(1_000_000, 1_000_000, 989_999);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumRebalanceLossBps = 100;

        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouterV2.RebalanceLossExceeded.selector, 10_000, 10_001)
        );
        router.rebalance(_EXECUTION_ID, _allocation(10_000), limits, 1_000_000);
    }

    function testLossBelowAndAtBoundaryPass() external {
        _assertDepositLossPasses(1_000_000, 990_001, 100);
        _assertDepositLossPasses(1_000_000, 990_000, 100);
    }

    function testLossUsesNetNavNotGrossTelemetry() external {
        asset.mint(address(router), 1_000_000);
        upshift.setDepositPreview(1_000_000, 1_000_000, 999_999);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumRebalanceLossBps = 0;

        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouterV2.RebalanceLossExceeded.selector, 0, 1)
        );
        router.rebalance(_EXECUTION_ID, _allocation(10_000), limits, 1_000_000);
    }

    function testMinimumPostNavBelowAndAtBoundaryPass() external {
        _assertMinimumPostNavPasses(98);
        _assertMinimumPostNavPasses(99);
    }

    function testMinimumPostNavAboveActualReverts() external {
        asset.mint(address(router), 100);
        upshift.setDepositPreview(100, 100, 99);
        RebalanceLimitsV2 memory limits = _limits();
        limits.minimumPostNAV = 100;

        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouterV2.MinimumPostNAVNotMet.selector, 100, 99)
        );
        router.rebalance(_EXECUTION_ID, _allocation(10_000), limits, 100);
    }

    function testZeroPreNavNoOpIsWellDefined() external {
        vm.prank(address(vault));
        uint256 totalAfter = router.rebalance(_EXECUTION_ID, _allocation(0), _limits(), 0);

        assertEq(totalAfter, 0);
        assertEq(router.lastRebalanceTimestamp(), 0);
    }

    function testMinimumPostNavStillAppliesToNoOp() external {
        RebalanceLimitsV2 memory limits = _limits();
        limits.minimumPostNAV = 1;

        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouterV2.MinimumPostNAVNotMet.selector, 1, 0)
        );
        router.rebalance(_EXECUTION_ID, _allocation(0), limits, 0);
    }

    function testFeeAndRoundingLossUseFloorBpsBoundary() external {
        _assertDepositLossPasses(101, 100, 100);

        (
            StrategyRouterV2 nextRouter,,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(_risk());
        asset.mint(address(nextRouter), 101);
        nextUpshift.setDepositPreview(101, 101, 100);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumRebalanceLossBps = 99;
        vm.prank(address(nextVault));
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouterV2.RebalanceLossExceeded.selector, 0, 1)
        );
        nextRouter.rebalance(_EXECUTION_ID, _allocation(10_000), limits, 101);
    }

    function testFullWidthLossMulDivDoesNotOverflow() external {
        RiskConfigurationV2 memory risk = _risk();
        risk.maximumRebalanceLossBps = 10_000;
        (
            StrategyRouterV2 nextRouter,,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(risk);
        asset.mint(address(nextRouter), type(uint256).max);
        nextUpshift.setDepositPreview(type(uint256).max, type(uint256).max, type(uint256).max - 1);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumRebalanceLossBps = 10_000;

        vm.prank(address(nextVault));
        uint256 totalAfter =
            nextRouter.rebalance(_EXECUTION_ID, _allocation(10_000), limits, type(uint256).max);
        assertEq(totalAfter, type(uint256).max - 1);
    }

    function testSignedLossLimitBelowAndAtFrozenAreAccepted() external view {
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumRebalanceLossBps = 999;
        assertTrue(router.previewRebalance(_allocation(0), limits).feasible);
        limits.maximumRebalanceLossBps = 1_000;
        assertTrue(router.previewRebalance(_allocation(0), limits).feasible);
    }

    function testSignedLossLimitAboveFrozenIsRejected() external view {
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumRebalanceLossBps = 1_001;
        _assertBlocker(limits, RebalanceBlockerV2.InvalidSignedLimits);
    }

    function testSignedPreviewLimitBelowAndAtFrozenAreAccepted() external view {
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumPreviewDeviationBps = 999;
        assertTrue(router.previewRebalance(_allocation(0), limits).feasible);
        limits.maximumPreviewDeviationBps = 1_000;
        assertTrue(router.previewRebalance(_allocation(0), limits).feasible);
    }

    function testSignedPreviewLimitAboveFrozenIsRejected() external view {
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumPreviewDeviationBps = 1_001;
        _assertBlocker(limits, RebalanceBlockerV2.InvalidSignedLimits);
    }

    function testSignedToleranceBelowAndAtFrozenAreAccepted() external view {
        RebalanceLimitsV2 memory limits = _limits();
        limits.allocationToleranceBps = 999;
        assertTrue(router.previewRebalance(_allocation(0), limits).feasible);
        limits.allocationToleranceBps = 1_000;
        assertTrue(router.previewRebalance(_allocation(0), limits).feasible);
    }

    function testSignedToleranceAboveFrozenIsRejected() external view {
        RebalanceLimitsV2 memory limits = _limits();
        limits.allocationToleranceBps = 1_001;
        _assertBlocker(limits, RebalanceBlockerV2.InvalidSignedLimits);
    }

    function testDepositNetPreviewDeviationBelowAndAtBoundaryPass() external {
        _assertDepositNetDeviationPasses(100);
        _assertDepositNetDeviationPasses(99);
    }

    function testDepositNetPreviewDeviationAboveBoundaryReverts() external {
        asset.mint(address(router), 100);
        upshift.setDepositPreview(100, 100, 100);
        upshift.setDepositPositionNetAdded(98);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumPreviewDeviationBps = 100;

        vm.prank(address(vault));
        vm.expectRevert(IStrategyRouterV2.PreviewDeviationExceeded.selector);
        router.rebalance(_EXECUTION_ID, _allocation(10_000), limits, 100);
    }

    function testRedeemPreviewDeviationBelowAndAtBoundaryPass() external {
        _assertRedeemDeviationPasses(50);
        _assertRedeemDeviationPasses(49);
    }

    function testRedeemPreviewDeviationAboveBoundaryReverts() external {
        (
            StrategyRouterV2 nextRouter,
            InstrumentedStrategyAdapterV2 nextIdle,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(_redeemRisk());
        _configureRedeemDeviationScenario(nextIdle, nextUpshift, 48);
        nextUpshift.setIgnoreMinimumChecks(true);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumPreviewDeviationBps = 200;
        limits.allocationToleranceBps = 25;

        vm.prank(address(nextVault));
        vm.expectRevert(IStrategyRouterV2.PreviewDeviationExceeded.selector);
        nextRouter.rebalance(_EXECUTION_ID, _allocation(5_000), limits, 0);
    }

    function testIdleAllocationToleranceAtBoundaryPasses() external {
        _assertIdleToleranceScenarioPasses(98);
    }

    function testIdleAllocationToleranceBelowBoundaryPasses() external {
        _assertIdleToleranceScenarioPasses(99);
    }

    function testIdleAllocationToleranceAboveBoundaryRevertsIndependently() external {
        _configureIdleOnlyToleranceScenario(idle, upshift);
        RebalanceLimitsV2 memory limits = _limits();
        limits.allocationToleranceBps = 97;

        vm.prank(address(vault));
        vm.expectRevert(IStrategyRouterV2.AllocationToleranceExceeded.selector);
        router.rebalance(_EXECUTION_ID, _allocation(5_000), limits, 0);
    }

    function testUpshiftAllocationToleranceAtBoundaryPasses() external {
        _assertUpshiftToleranceScenarioPasses(99);
    }

    function testUpshiftAllocationToleranceBelowBoundaryPasses() external {
        _assertUpshiftToleranceScenarioPasses(100);
    }

    function testUpshiftAllocationToleranceAboveBoundaryRevertsIndependently() external {
        _configureUpshiftOnlyToleranceScenario(idle, upshift);
        RebalanceLimitsV2 memory limits = _limits();
        limits.allocationToleranceBps = 98;

        vm.prank(address(vault));
        vm.expectRevert(IStrategyRouterV2.AllocationToleranceExceeded.selector);
        router.rebalance(_EXECUTION_ID, _allocation(5_000), limits, 0);
    }

    function testFirstQualifyingRebalanceIsImmediateAndSetsTimestamp() external {
        vm.warp(100_000);
        asset.mint(address(router), 100);

        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(0), _limits(), 100);

        assertEq(router.lastRebalanceTimestamp(), 100_000);
    }

    function testCooldownAllowsExactEarliestTimestamp() external {
        vm.warp(100_000);
        asset.mint(address(router), 100);
        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(0), _limits(), 100);

        vm.warp(103_600);
        vm.prank(address(vault));
        router.rebalance(bytes32(uint256(2)), _allocation(10_000), _limits(), 0);

        assertEq(router.lastRebalanceTimestamp(), 103_600);
    }

    function testCooldownRejectsOneSecondEarlyWithoutAdvancingTimestamp() external {
        vm.warp(100_000);
        asset.mint(address(router), 100);
        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(0), _limits(), 100);

        vm.warp(103_599);
        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyRouterV2.RebalanceInfeasible.selector, RebalanceBlockerV2.CooldownActive
            )
        );
        router.rebalance(bytes32(uint256(2)), _allocation(10_000), _limits(), 0);
        assertEq(router.lastRebalanceTimestamp(), 100_000);
    }

    function testNoOpDoesNotAdvanceCooldown() external {
        vm.warp(100_000);
        asset.mint(address(router), 100);
        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(0), _limits(), 100);

        vm.warp(100_001);
        vm.prank(address(vault));
        router.rebalance(bytes32(uint256(2)), _allocation(0), _limits(), 0);

        assertEq(router.lastRebalanceTimestamp(), 100_000);
        assertEq(idle.stateChangingCallCount(), 1);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testBelowMinimumChangeDoesNotAdvanceCooldown() external {
        idle.setPositionValues(5_050, 5_050, 5_050, 5_050);
        upshift.setPositionValues(4_950, 4_950, 4_950, 4_950);

        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyRouterV2.RebalanceInfeasible.selector,
                RebalanceBlockerV2.ChangeBelowMinimum
            )
        );
        router.rebalance(_EXECUTION_ID, _allocation(5_000), _limits(), 0);
        assertEq(router.lastRebalanceTimestamp(), 0);
    }

    function testCooldownTimestampAdditionFailsClosedOnOverflow() external {
        stdstore.target(address(router)).sig(router.lastRebalanceTimestamp.selector)
            .checked_write(type(uint256).max - 1);
        idle.setPositionValues(100, 100, 100, 100);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(10_000), _limits());
        assertFalse(plan.feasible);
        assertEq(uint256(plan.blocker), uint256(RebalanceBlockerV2.CooldownActive));
    }

    function _assertDepositLossPasses(uint256 amount, uint256 postNet, uint16 lossBps) internal {
        (
            StrategyRouterV2 nextRouter,,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(_risk());
        asset.mint(address(nextRouter), amount);
        nextUpshift.setDepositPreview(amount, amount, postNet);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumRebalanceLossBps = lossBps;
        vm.prank(address(nextVault));
        uint256 totalAfter =
            nextRouter.rebalance(_EXECUTION_ID, _allocation(10_000), limits, amount);
        assertEq(totalAfter, postNet);
    }

    function _assertMinimumPostNavPasses(uint256 minimumPostNav) internal {
        (
            StrategyRouterV2 nextRouter,,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(_risk());
        asset.mint(address(nextRouter), 100);
        nextUpshift.setDepositPreview(100, 100, 99);
        RebalanceLimitsV2 memory limits = _limits();
        limits.minimumPostNAV = minimumPostNav;
        vm.prank(address(nextVault));
        assertEq(nextRouter.rebalance(_EXECUTION_ID, _allocation(10_000), limits, 100), 99);
    }

    function _assertDepositNetDeviationPasses(uint256 actualNet) internal {
        (
            StrategyRouterV2 nextRouter,,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(_risk());
        asset.mint(address(nextRouter), 100);
        nextUpshift.setDepositPreview(100, 100, 100);
        nextUpshift.setDepositPositionNetAdded(actualNet);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumPreviewDeviationBps = 100;
        vm.prank(address(nextVault));
        assertEq(nextRouter.rebalance(_EXECUTION_ID, _allocation(10_000), limits, 100), actualNet);
    }

    function _assertRedeemDeviationPasses(uint256 actualAssets) internal {
        (
            StrategyRouterV2 nextRouter,
            InstrumentedStrategyAdapterV2 nextIdle,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(_redeemRisk());
        _configureRedeemDeviationScenario(nextIdle, nextUpshift, actualAssets);
        RebalanceLimitsV2 memory limits = _limits();
        limits.maximumPreviewDeviationBps = 200;
        limits.allocationToleranceBps = 25;
        vm.prank(address(nextVault));
        nextRouter.rebalance(_EXECUTION_ID, _allocation(5_000), limits, 0);
    }

    function _configureRedeemDeviationScenario(
        InstrumentedStrategyAdapterV2 targetIdle,
        InstrumentedStrategyAdapterV2 targetUpshift,
        uint256 actualAssets
    ) internal {
        targetIdle.setPositionValues(5_000, 5_000, 5_000, 5_000);
        targetUpshift.setPositionValues(5_100, 5_100, 5_100, 5_100);
        targetUpshift.setRedeemPreview(50, 50, 50);
        targetUpshift.setRedeemPreview(5_050, 5_000, 5_000);
        targetUpshift.setRedeemExecution(50, actualAssets, actualAssets);
    }

    function _assertIdleToleranceScenarioPasses(uint16 toleranceBps) internal {
        (
            StrategyRouterV2 nextRouter,
            InstrumentedStrategyAdapterV2 nextIdle,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(_risk());
        _configureIdleOnlyToleranceScenario(nextIdle, nextUpshift);
        RebalanceLimitsV2 memory limits = _limits();
        limits.allocationToleranceBps = toleranceBps;
        vm.prank(address(nextVault));
        nextRouter.rebalance(_EXECUTION_ID, _allocation(5_000), limits, 0);
    }

    function _configureIdleOnlyToleranceScenario(
        InstrumentedStrategyAdapterV2 targetIdle,
        InstrumentedStrategyAdapterV2 targetUpshift
    ) internal {
        targetIdle.setPositionValues(20, 20, 20, 20);
        targetUpshift.setPositionValues(82, 82, 82, 82);
        targetUpshift.setRedeemPreview(31, 30, 30);
        targetUpshift.setRedeemPreview(51, 51, 51);
        targetUpshift.setRedeemExecution(31, 31, 31);
    }

    function _assertUpshiftToleranceScenarioPasses(uint16 toleranceBps) internal {
        (
            StrategyRouterV2 nextRouter,
            InstrumentedStrategyAdapterV2 nextIdle,
            InstrumentedStrategyAdapterV2 nextUpshift,
            ReentrantRouterVaultV2 nextVault
        ) = _deploy(_risk());
        _configureUpshiftOnlyToleranceScenario(nextIdle, nextUpshift);
        RebalanceLimitsV2 memory limits = _limits();
        limits.allocationToleranceBps = toleranceBps;
        vm.prank(address(nextVault));
        nextRouter.rebalance(_EXECUTION_ID, _allocation(5_000), limits, 0);
    }

    function _configureUpshiftOnlyToleranceScenario(
        InstrumentedStrategyAdapterV2 targetIdle,
        InstrumentedStrategyAdapterV2 targetUpshift
    ) internal {
        targetIdle.setPositionValues(20, 20, 20, 20);
        targetUpshift.setPositionValues(81, 81, 81, 81);
        targetUpshift.setRedeemPreview(30, 30, 30);
        targetUpshift.setRedeemPreview(51, 50, 50);
        targetUpshift.setRedeemExecution(30, 31, 31);
    }

    function _assertBlocker(RebalanceLimitsV2 memory limits, RebalanceBlockerV2 blocker)
        internal
        view
    {
        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(0), limits);
        assertFalse(plan.feasible);
        assertEq(uint256(plan.blocker), uint256(blocker));
    }

    function _deploy(RiskConfigurationV2 memory risk)
        internal
        returns (
            StrategyRouterV2 deployedRouter,
            InstrumentedStrategyAdapterV2 deployedIdle,
            InstrumentedStrategyAdapterV2 deployedUpshift,
            ReentrantRouterVaultV2 deployedVault
        )
    {
        deployedRouter = new StrategyRouterV2(IERC20(address(asset)), owner);
        deployedIdle = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(deployedRouter), address(asset)
        );
        deployedUpshift = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(deployedRouter), address(lpToken)
        );
        deployedVault = new ReentrantRouterVaultV2(owner);

        vm.startPrank(owner);
        deployedRouter.configureAdapters(address(deployedUpshift), address(deployedIdle));
        deployedRouter.configureRisk(risk);
        deployedRouter.bindVault(address(deployedVault));
        vm.stopPrank();
    }

    function _allocation(uint16 upshiftBps) internal pure returns (AllocationV2 memory) {
        return AllocationV2({
            upshiftBps: upshiftBps, firelightBps: 0, sparkdexBps: 0, idleBps: _BPS - upshiftBps
        });
    }

    function _limits() internal pure returns (RebalanceLimitsV2 memory) {
        return RebalanceLimitsV2({
            minimumPostNAV: 0,
            maximumRebalanceLossBps: 1_000,
            maximumPreviewDeviationBps: 1_000,
            allocationToleranceBps: 1_000
        });
    }

    function _risk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 1 hours,
            minimumAllocationChangeBps: 1_000,
            maximumRebalanceLossBps: 1_000,
            maximumPreviewDeviationBps: 1_000,
            allocationToleranceBps: 1_000
        });
    }

    function _redeemRisk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 1 hours,
            minimumAllocationChangeBps: 25,
            maximumRebalanceLossBps: 1_000,
            maximumPreviewDeviationBps: 1_000,
            allocationToleranceBps: 25
        });
    }
}
