// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {
    IStrategyRouterV2,
    RebalanceBlockerV2,
    RebalancePlanV2,
    RouterStateV2
} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2
} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {InstrumentedStrategyAdapterV2} from "./mocks/InstrumentedStrategyAdapterV2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";

contract ReentrantRouterVaultV2 {
    address public immutable vaultOwner;
    address private _target;
    bytes private _data;

    constructor(address owner_) {
        vaultOwner = owner_;
    }

    function arm(address target, bytes calldata data) external {
        _target = target;
        _data = data;
    }

    function reenter() external {
        address target = _target;
        bytes memory data = _data;
        _target = address(0);
        delete _data;
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }
}

contract StrategyRouterV2RecoveryTest is Test {
    using stdStorage for StdStorage;

    event AdapterPositionRecovered(
        address indexed positionToken, uint256 sharesRecovered, address indexed receiver
    );
    event ExecutionPauseUpdated(bool paused);

    bytes32 internal constant EXECUTION_ID = keccak256("TASK_8_EXECUTION");

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    StrategyRouterV2 internal router;
    InstrumentedStrategyAdapterV2 internal idle;
    InstrumentedStrategyAdapterV2 internal upshift;
    RouterBoundVaultMockV2 internal vault;
    address internal owner = address(0xA11CE);

    function setUp() public {
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        router = new StrategyRouterV2(IERC20(address(asset)), owner);
        idle = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(router), address(asset)
        );
        upshift = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(router), address(lpToken)
        );
        vault = new RouterBoundVaultMockV2(owner);

        vm.startPrank(owner);
        router.configureAdapters(address(upshift), address(idle));
        router.configureRisk(_risk());
        router.bindVault(address(vault));
        vm.stopPrank();
    }

    // ============ setExecutionPaused tests ============

    function testSetExecutionPausedRestrictedToVault() external {
        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        IStrategyRouterV2(address(router)).setExecutionPaused(true);
    }

    function testSetExecutionPausedEmitsEvent() external {
        vm.expectEmit(address(router));
        emit ExecutionPauseUpdated(true);
        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).setExecutionPaused(true);
    }

    function testSetExecutionPausedTogglesBackAndForth() external {
        assertFalse(router.executionPaused());

        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).setExecutionPaused(true);
        assertTrue(router.executionPaused());

        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).setExecutionPaused(false);
        assertFalse(router.executionPaused());
    }

    function testSetExecutionPausedWorksInRecoveredState() external {
        _seedUpshiftPosition(100, 100);
        _pause();
        _recover();

        assertTrue(router.upshiftRecovered());

        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).setExecutionPaused(false);
        assertFalse(router.executionPaused());
        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftRecovered));
    }

    // ============ recoverAdapterPosition access control ============

    function testRecoveryRestrictedToVault() external {
        _seedUpshiftPosition(100, 100);
        _pause();

        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        IStrategyRouterV2(address(router)).recoverAdapterPosition();
    }

    function testRecoveryRequiresPause() external {
        _seedUpshiftPosition(100, 100);

        vm.expectRevert(IStrategyRouterV2.RecoveryRequiresPause.selector);
        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).recoverAdapterPosition();
    }

    function testRecoveryRequiresNonzeroPosition() external {
        _pause();

        vm.expectRevert(IStrategyRouterV2.ResidualPosition.selector);
        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).recoverAdapterPosition();
    }

    function testRecoveryRejectsSecondCall() external {
        _seedUpshiftPosition(100, 100);
        _pause();
        _recover();

        vm.expectRevert(IStrategyRouterV2.PositionAlreadyRecovered.selector);
        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).recoverAdapterPosition();
    }

    // ============ recoverAdapterPosition accounting ============

    function testRecoveryTransfersExactLpToVault() external {
        _seedUpshiftPosition(100, 100);
        _pause();

        uint256 shares = _recover();

        assertEq(shares, 100);
        assertEq(lpToken.balanceOf(address(vault)), 100);
        assertEq(lpToken.balanceOf(address(upshift)), 0);
    }

    function testRecoveryReceiverIsAlwaysBoundVault() external {
        _seedUpshiftPosition(100, 100);
        _pause();
        _recover();

        assertEq(upshift.lastRecoveryReceiver(), address(vault));
    }

    function testRecoveryAdapterOverReportReverts() external {
        _seedUpshiftPosition(100, 100);
        upshift.setRecoveryExecution(100, 100, 200);
        _pause();

        vm.expectRevert(IStrategyRouterV2.AdapterDeltaMismatch.selector);
        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).recoverAdapterPosition();
    }

    function testRecoveryVaultUnderCreditReverts() external {
        _seedUpshiftPosition(100, 100);
        upshift.setRecoveryExecution(100, 50, 100);
        _pause();

        vm.expectRevert(IStrategyRouterV2.AdapterDeltaMismatch.selector);
        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).recoverAdapterPosition();
    }

    function testRecoverySetsUpshiftRecoveredPermanently() external {
        _seedUpshiftPosition(100, 100);
        _pause();
        _recover();

        assertTrue(router.upshiftRecovered());
        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftRecovered));
    }

    // ============ recovery execution restrictions ============

    function testRecoveryBlocksRebalanceWithRecoveredTargetForbidden() external {
        _seedUpshiftPosition(100, 100);
        _pause();
        _recover();

        vm.expectRevert(IStrategyRouterV2.RecoveredTargetForbidden.selector);
        vm.prank(address(vault));
        IStrategyRouterV2(address(router))
            .rebalance(EXECUTION_ID, _halfAndHalf(), _validLimits(), 0);
    }

    function testRecoveryDoesNotBlockWithdrawToVault() external {
        _seedUpshiftPosition(100, 100);
        _seedDirectUnderlying(50);
        _pause();
        _recover();

        vm.prank(address(vault));
        uint256 delivered = IStrategyRouterV2(address(router)).withdrawToVault(50);

        assertEq(delivered, 50);
        assertEq(asset.balanceOf(address(vault)), 50);
        assertEq(asset.balanceOf(address(upshift)), 0);
    }

    function testRecoveryDirectUnderlyingCountedInNAV() external {
        _seedUpshiftPosition(100, 100);
        _seedDirectUnderlying(50);
        _pause();
        _recover();

        assertEq(router.totalAssets(), 50);
    }

    // ============ recovery NAV ============

    function testRecoveredStateNetGrossLiquidityEqualDirectOnly() external {
        _seedUpshiftPosition(100, 100);
        _seedDirectUnderlying(50);
        _pause();
        _recover();

        assertEq(router.totalAssets(), 50);
        assertEq(router.grossAssets(), 50);
        assertEq(router.availableLiquidity(), 50);
    }

    function testRecoveredStatePreviewRebalanceReturnsRecoveredTargetForbidden() external {
        _seedUpshiftPosition(100, 100);
        _pause();
        _recover();

        RebalancePlanV2 memory plan = router.previewRebalance(_halfAndHalf(), _validLimits());
        assertFalse(plan.feasible);
        assertEq(uint256(plan.blocker), uint256(RebalanceBlockerV2.RecoveredTargetForbidden));
    }

    // ============ events ============

    function testRecoveryEmitsAdapterPositionRecoveredEvent() external {
        _seedUpshiftPosition(100, 100);
        _pause();

        vm.expectEmit(true, true, false, true);
        emit AdapterPositionRecovered(address(lpToken), 100, address(vault));

        _recover();
    }

    // ============ reentrancy ============

    function testRecoveryReentrancyBlocked() external {
        ReentrantRouterVaultV2 callbackVault = new ReentrantRouterVaultV2(owner);
        StrategyRouterV2 callbackRouter = new StrategyRouterV2(IERC20(address(asset)), owner);
        InstrumentedStrategyAdapterV2 callbackIdle = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(callbackRouter), address(asset)
        );
        InstrumentedStrategyAdapterV2 callbackUpshift = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(callbackRouter), address(lpToken)
        );

        vm.startPrank(owner);
        callbackRouter.configureAdapters(address(callbackUpshift), address(callbackIdle));
        callbackRouter.configureRisk(_risk());
        callbackRouter.bindVault(address(callbackVault));
        vm.stopPrank();

        lpToken.mint(address(callbackUpshift), 100);
        callbackUpshift.setPositionValues(100, 100, 100, 100);

        vm.prank(address(callbackVault));
        IStrategyRouterV2(address(callbackRouter)).setExecutionPaused(true);

        bytes memory nested = abi.encodeCall(IStrategyRouterV2.recoverAdapterPosition, ());
        callbackVault.arm(address(callbackRouter), nested);
        callbackUpshift.setRecoveryCallback(
            address(callbackVault), abi.encodeCall(callbackVault.reenter, ())
        );

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(callbackVault));
        IStrategyRouterV2(address(callbackRouter)).recoverAdapterPosition();
    }

    // ============ cooldown bypass ============

    function testRecoveryNotBlockedByCooldown() external {
        _seedUpshiftPosition(100, 100);
        _pause();

        stdstore.target(address(router)).sig(router.lastRebalanceTimestamp.selector)
            .checked_write(block.timestamp);

        uint256 shares = _recover();
        assertEq(shares, 100);
    }

    // ============ LP donation after recovery ============

    function testLpDonationAfterRecoveryIsNonRecoverable() external {
        _seedUpshiftPosition(100, 100);
        _pause();
        _recover();

        lpToken.mint(address(upshift), 50);

        vm.expectRevert(IStrategyRouterV2.PositionAlreadyRecovered.selector);
        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).recoverAdapterPosition();
    }

    // ============ helpers ============

    function _risk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 1 hours,
            minimumAllocationChangeBps: 100,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }

    function _halfAndHalf() internal pure returns (AllocationV2 memory) {
        return AllocationV2({upshiftBps: 5000, firelightBps: 0, sparkdexBps: 0, idleBps: 5000});
    }

    function _validLimits() internal pure returns (RebalanceLimitsV2 memory) {
        return RebalanceLimitsV2({
            minimumPostNAV: 0,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }

    function _seedUpshiftPosition(uint256 net, uint256 shares) internal {
        lpToken.mint(address(upshift), shares);
        upshift.setPositionValues(net, net, net, shares);
    }

    function _seedDirectUnderlying(uint256 amount) internal {
        asset.mint(address(upshift), amount);
    }

    function _pause() internal {
        vm.prank(address(vault));
        IStrategyRouterV2(address(router)).setExecutionPaused(true);
    }

    function _recover() internal returns (uint256 sharesRecovered) {
        vm.prank(address(vault));
        return IStrategyRouterV2(address(router)).recoverAdapterPosition();
    }
}
