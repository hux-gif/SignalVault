// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {IStrategyRouterV2, RebalanceBlockerV2} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2
} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {InstrumentedStrategyAdapterV2} from "./mocks/InstrumentedStrategyAdapterV2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";

/// @title StrategyRouterV2 Adversarial Security Suite
/// @notice Consolidated mutation-sensitive tests for every security-critical invariant
///         enumerated in the Task 9 adversarial security suite specification.
///         Invariants already covered by dedicated task test files are re-asserted here
///         as a single-entry-point defense-in-depth matrix. The executionId/replay
///         boundary is the sole invariant NOT covered by prior tasks and is introduced here.
contract StrategyRouterV2SecurityTest is Test {
    uint16 private constant _BPS = 10_000;
    bytes32 private constant _EXEC_ID_A = keccak256("SEC_EXEC_A");
    bytes32 private constant _EXEC_ID_B = keccak256("SEC_EXEC_B");

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

    // ========================================================================
    // Authorization Matrix — onlyVault enforcement on all privileged entrypoints
    // ========================================================================

    function testSecurityRebalanceRejectsNonVaultCaller() external {
        asset.mint(address(router), 100);
        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        router.rebalance(_EXEC_ID_A, _allUpshift(), _validLimits(), 100);
    }

    function testSecurityWithdrawToVaultRejectsNonVaultCaller() external {
        asset.mint(address(router), 10);
        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        router.withdrawToVault(10);
    }

    function testSecurityWithdrawAllToVaultRejectsNonVaultCaller() external {
        asset.mint(address(router), 10);
        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        router.withdrawAllToVault();
    }

    function testSecuritySetExecutionPausedRejectsNonVaultCaller() external {
        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        router.setExecutionPaused(true);
    }

    function testSecurityRecoverAdapterPositionRejectsNonVaultCaller() external {
        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        router.recoverAdapterPosition();
    }

    // ========================================================================
    // Configuration Freeze Immutability — after bindVault the configuration
    // is permanently frozen and cannot be reconfigured.
    // ========================================================================

    function testSecurityFrozenConfigRejectsAdapterReconfiguration() external {
        vm.prank(owner);
        vm.expectRevert(IStrategyRouterV2.ConfigurationFrozen.selector);
        router.configureAdapters(address(upshift), address(idle));
    }

    function testSecurityFrozenConfigRejectsRiskReconfiguration() external {
        vm.prank(owner);
        vm.expectRevert(IStrategyRouterV2.ConfigurationFrozen.selector);
        router.configureRisk(_risk());
    }

    function testSecurityFrozenConfigRejectsVaultRebind() external {
        vm.prank(owner);
        vm.expectRevert(IStrategyRouterV2.ConfigurationFrozen.selector);
        router.bindVault(address(vault));
    }

    // ========================================================================
    // executionId / Replay Boundary
    //
    // The bytes32 executionId parameter on rebalance() is a pure event label for
    // off-chain correlation — the router does NOT track executionId uniqueness.
    // Replay protection is provided by:
    //   1. onlyVault — only the bound vault can call
    //   2. nonReentrant — no reentrancy within a single call
    //   3. cooldown — prevents immediate sequential rebalances
    //   4. economic guards — loss limits, allocation tolerance, post-NAV
    //
    // ExecutionId replay protection is the vault/signature layer's responsibility.
    // These tests document that design boundary.
    // ========================================================================

    function testSecurityExecutionIdNotTrackedSameIdWorksAfterCooldown() external {
        asset.mint(address(router), 100);

        // First rebalance with EXEC_ID_A: move to 100% upshift
        vm.prank(address(vault));
        router.rebalance(_EXEC_ID_A, _allUpshift(), _validLimits(), 100);

        // Warp past the 1-hour cooldown
        vm.warp(block.timestamp + 1 hours + 1);

        // Second rebalance with the SAME EXEC_ID_A: move back to 100% idle
        // If executionId were tracked, this would revert. It does not.
        vm.prank(address(vault));
        router.rebalance(_EXEC_ID_A, _allIdle(), _validLimits(), 0);

        assertEq(idle.depositCallCount(), 1);
        assertEq(upshift.redeemCallCount(), 1);
    }

    function testSecurityReplayBlockedByCooldownNotExecutionId() external {
        asset.mint(address(router), 100);

        // First rebalance with EXEC_ID_A
        vm.prank(address(vault));
        router.rebalance(_EXEC_ID_A, _allUpshift(), _validLimits(), 100);

        // Immediate replay with a DIFFERENT executionId is still blocked by cooldown
        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyRouterV2.RebalanceInfeasible.selector, RebalanceBlockerV2.CooldownActive
            )
        );
        router.rebalance(_EXEC_ID_B, _allIdle(), _validLimits(), 0);
    }

    function testSecurityNoOpRebalanceDoesNotRequireUniqueExecutionId() external {
        asset.mint(address(idle), 100);

        // No-op rebalance (already at 100% idle) with EXEC_ID_A
        vm.prank(address(vault));
        router.rebalance(_EXEC_ID_A, _allIdle(), _validLimits(), 0);

        // Another no-op with the SAME EXEC_ID_A succeeds — no-op does not set cooldown
        vm.prank(address(vault));
        router.rebalance(_EXEC_ID_A, _allIdle(), _validLimits(), 0);

        assertEq(router.lastRebalanceTimestamp(), 0);
    }

    // ========================================================================
    // Post-Recovery Execution Matrix — after recoverAdapterPosition the
    // upshiftRecovered flag is permanent. Rebalance and second recovery are
    // blocked, but withdrawal and pause toggle remain operational.
    // ========================================================================

    function testSecurityRecoveredStateBlocksRebalanceAndSecondRecovery() external {
        _setupAndRecover();

        // Rebalance permanently blocked
        vm.prank(address(vault));
        vm.expectRevert(IStrategyRouterV2.RecoveredTargetForbidden.selector);
        router.rebalance(_EXEC_ID_A, _allIdle(), _validLimits(), 0);

        // Second recovery permanently blocked
        vm.prank(address(vault));
        vm.expectRevert(IStrategyRouterV2.PositionAlreadyRecovered.selector);
        router.recoverAdapterPosition();

        // Preview rebalance also reports the blocker
        vm.prank(address(vault));
        RebalanceBlockerV2 blocker = router.previewRebalance(_allIdle(), _validLimits()).blocker;
        assertEq(uint256(blocker), uint256(RebalanceBlockerV2.RecoveredTargetForbidden));
    }

    function testSecurityRecoveredStateAllowsWithdrawalAndPauseToggle() external {
        _setupAndRecover();

        // Pause toggle still works in recovered state
        vm.prank(address(vault));
        router.setExecutionPaused(false);
        assertFalse(router.executionPaused());

        vm.prank(address(vault));
        router.setExecutionPaused(true);
        assertTrue(router.executionPaused());

        // Withdrawal still works — recovery does not block withdrawals
        asset.mint(address(router), 10);
        vm.prank(address(vault));
        uint256 delivered = router.withdrawToVault(10);
        assertEq(delivered, 10);
        assertEq(asset.balanceOf(address(vault)), 10);
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    function _allIdle() internal pure returns (AllocationV2 memory) {
        return AllocationV2({upshiftBps: 0, firelightBps: 0, sparkdexBps: 0, idleBps: _BPS});
    }

    function _allUpshift() internal pure returns (AllocationV2 memory) {
        return AllocationV2({upshiftBps: _BPS, firelightBps: 0, sparkdexBps: 0, idleBps: 0});
    }

    function _validLimits() internal pure returns (RebalanceLimitsV2 memory) {
        return RebalanceLimitsV2({
            minimumPostNAV: 0,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
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

    function _setupAndRecover() internal {
        // Seed upshift adapter with LP tokens so recovery has a position to recover
        lpToken.mint(address(upshift), 100);
        upshift.setPositionValues(100, 100, 100, 100);

        // Pause execution (recovery requires pause)
        vm.prank(address(vault));
        router.setExecutionPaused(true);

        // Execute recovery
        vm.prank(address(vault));
        router.recoverAdapterPosition();

        assertTrue(router.upshiftRecovered());
    }
}
