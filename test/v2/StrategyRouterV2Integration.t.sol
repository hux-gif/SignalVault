// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {
    IStrategyRouterV2,
    AllocationSnapshotV2,
    RebalanceBlockerV2,
    RouterStateV2,
    RebalancePlanV2
} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {IUpshiftVaultV2} from "../../src/v2/interfaces/IUpshiftVaultV2.sol";
import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2
} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {SignalVaultHashesV2} from "../../src/v2/libraries/SignalVaultHashesV2.sol";
import {IdleAdapterV2} from "../../src/v2/adapters/IdleAdapterV2.sol";
import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {FeeAwareUpshiftVaultMock} from "./mocks/FeeAwareUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";

/// @notice Canonical integration test using production Router, real IdleAdapterV2,
/// real UpshiftAdapterV2 and FeeAwareUpshiftVaultMock. Exercises the complete
/// lifecycle: configuration freeze, initial direct-buffer allocation, no-op,
/// strict increase, strict decrease, dynamic fee change, paused fee-free
/// withdrawal, partial withdrawal, full withdrawal, and final reconciliation.
contract StrategyRouterV2IntegrationTest is Test {
    uint16 private constant _BPS = 10_000;
    bytes32 private constant _EXECUTION_ID = keccak256("INTEGRATION_LIFECYCLE");

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    FeeAwareUpshiftVaultMock internal protocol;
    IdleAdapterV2 internal idle;
    UpshiftAdapterV2 internal upshift;
    StrategyRouterV2 internal router;
    RouterBoundVaultMockV2 internal vault;
    address internal owner = address(0xB0B);

    function setUp() public {
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        protocol = new FeeAwareUpshiftVaultMock(address(asset), address(lpToken));

        router = new StrategyRouterV2(IERC20(address(asset)), owner);
        idle = new IdleAdapterV2(IERC20(address(asset)), address(router));
        upshift = new UpshiftAdapterV2(
            IERC20(address(asset)),
            address(router),
            IUpshiftVaultV2(address(protocol)),
            IERC20(address(lpToken))
        );
        vault = new RouterBoundVaultMockV2(owner);

        vm.startPrank(owner);
        router.configureAdapters(address(upshift), address(idle));
        router.configureRisk(_risk());
        router.bindVault(address(vault));
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // Canonical lifecycle
    // -----------------------------------------------------------------------

    function testCanonicalRouterLifecycleThroughRealAdapters() external {
        // ---- Phase 1: Frozen config hash ----
        bytes32 expectedRisk = SignalVaultHashesV2.computeRiskConfigurationHash(_risk());
        bytes32 expectedConfig = SignalVaultHashesV2.computeRouterConfigHash(
            block.chainid,
            address(vault),
            address(router),
            address(asset),
            address(upshift),
            address(idle),
            router.capabilityProfile(),
            expectedRisk,
            1
        );
        assertEq(router.riskConfigurationHash(), expectedRisk, "P1: risk hash");
        assertEq(router.routerConfigHash(), expectedConfig, "P1: config hash");
        assertTrue(router.configurationFrozen(), "P1: frozen");
        assertEq(
            uint256(router.strategyState()), uint256(RouterStateV2.Operational), "P1: operational"
        );

        // ---- Phase 2: Initial direct-buffer allocation 50/50 ----
        vm.warp(1 hours);
        asset.mint(address(router), 1_000_000);
        _assertNoAllowances();

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _validLimits());
        assertTrue(plan.feasible, "P2: plan feasible");
        assertEq(plan.upshiftDepositAssets, 500_000, "P2: upshift deposit");
        assertEq(plan.idleDepositAssets, 500_000, "P2: idle deposit");
        assertEq(plan.upshiftSharesToRedeem, 0, "P2: no redeem");
        assertEq(plan.idleWithdrawAssets, 0, "P2: no idle withdraw");

        vm.prank(address(vault));
        uint256 totalAfter =
            router.rebalance(_EXECUTION_ID, _allocation(5_000), _validLimits(), 1_000_000);
        assertEq(totalAfter, 1_000_000, "P2: total after");

        assertEq(asset.balanceOf(address(router)), 0, "P2: router direct zero");
        assertEq(asset.balanceOf(address(idle)), 500_000, "P2: idle balance");
        assertEq(lpToken.balanceOf(address(upshift)), 500_000, "P2: upshift LP");
        assertEq(asset.balanceOf(address(upshift)), 0, "P2: upshift direct zero");
        assertEq(router.totalAssets(), 1_000_000, "P2: total");
        _assertNoAllowances();

        // ---- Phase 3: No-op rebalance (exact zero adapter calls) ----
        uint256 idleBefore = asset.balanceOf(address(idle));
        uint256 upshiftLPBefore = lpToken.balanceOf(address(upshift));
        uint256 routerDirectBefore = asset.balanceOf(address(router));

        plan = router.previewRebalance(_allocation(5_000), _validLimits());
        assertTrue(plan.feasible, "P3: noop plan feasible");
        assertEq(plan.idleDepositAssets, 0, "P3: noop idle deposit");
        assertEq(plan.upshiftDepositAssets, 0, "P3: noop upshift deposit");
        assertEq(plan.upshiftSharesToRedeem, 0, "P3: noop upshift redeem");
        assertEq(plan.idleWithdrawAssets, 0, "P3: noop idle withdraw");
        assertEq(plan.upshiftLiquidWithdrawAssets, 0, "P3: noop liquid withdraw");

        vm.prank(address(vault));
        totalAfter = router.rebalance(_EXECUTION_ID, _allocation(5_000), _validLimits(), 0);
        assertEq(totalAfter, 1_000_000, "P3: total unchanged");
        assertEq(asset.balanceOf(address(idle)), idleBefore, "P3: idle unchanged");
        assertEq(lpToken.balanceOf(address(upshift)), upshiftLPBefore, "P3: upshift LP unchanged");
        assertEq(
            asset.balanceOf(address(router)), routerDirectBefore, "P3: router direct unchanged"
        );
        _assertNoAllowances();

        // ---- Phase 4: Strict increase to 60/40 ----
        vm.warp(3 hours);
        plan = router.previewRebalance(_allocation(6_000), _validLimits());
        assertTrue(plan.feasible, "P4: increase plan feasible");
        assertEq(plan.idleWithdrawAssets, 100_000, "P4: idle withdraw");
        assertEq(plan.upshiftDepositAssets, 100_000, "P4: upshift deposit");
        assertEq(plan.upshiftSharesToRedeem, 0, "P4: no redeem");

        vm.prank(address(vault));
        totalAfter = router.rebalance(_EXECUTION_ID, _allocation(6_000), _validLimits(), 0);
        assertEq(totalAfter, 1_000_000, "P4: total preserved");

        assertEq(asset.balanceOf(address(idle)), 400_000, "P4: idle decreased");
        assertEq(lpToken.balanceOf(address(upshift)), 600_000, "P4: upshift LP increased");
        assertEq(asset.balanceOf(address(router)), 0, "P4: router direct zero");
        _assertNoAllowances();

        // ---- Phase 5: Strict decrease to 40/60 ----
        vm.warp(5 hours);
        plan = router.previewRebalance(_allocation(4_000), _validLimits());
        assertTrue(plan.feasible, "P5: decrease plan feasible");
        assertEq(plan.upshiftSharesToRedeem, 200_000, "P5: shares to redeem");
        assertEq(plan.idleDepositAssets, 200_000, "P5: idle deposit");
        assertEq(plan.upshiftDepositAssets, 0, "P5: no upshift deposit");

        vm.prank(address(vault));
        totalAfter = router.rebalance(_EXECUTION_ID, _allocation(4_000), _validLimits(), 0);
        assertEq(totalAfter, 1_000_000, "P5: total preserved");

        assertEq(asset.balanceOf(address(idle)), 600_000, "P5: idle increased");
        assertEq(lpToken.balanceOf(address(upshift)), 400_000, "P5: upshift LP decreased");
        assertEq(asset.balanceOf(address(router)), 0, "P5: router direct zero");
        _assertNoAllowances();

        // ---- Phase 6: Dynamic fee change + rebalance ----
        uint256 totalBeforeFee = router.totalAssets();
        assertEq(totalBeforeFee, 1_000_000, "P6: total before fee");

        protocol.setInstantFee(50); // 50 bps
        uint256 totalAfterFeeSet = router.totalAssets();
        assertLt(totalAfterFeeSet, totalBeforeFee, "P6: fee reduced valuation");
        // 400_000 LP * 50 / 10000 = 2000 fee drag
        assertEq(totalAfterFeeSet, 998_000, "P6: total after fee set");

        vm.warp(7 hours);
        plan = router.previewRebalance(_allocation(3_000), _validLimits());
        assertTrue(plan.feasible, "P6: fee plan feasible");
        assertGt(plan.upshiftSharesToRedeem, 0, "P6: shares redeem positive");
        assertGt(plan.idleDepositAssets, 0, "P6: idle deposit positive");
        uint256 lpBeforeFeeRebalance = lpToken.balanceOf(address(upshift));

        vm.prank(address(vault));
        totalAfter = router.rebalance(_EXECUTION_ID, _allocation(3_000), _validLimits(), 0);
        assertLt(lpToken.balanceOf(address(upshift)), lpBeforeFeeRebalance, "P6: LP decreased");
        assertGt(lpToken.balanceOf(address(upshift)), 0, "P6: LP not fully redeemed");
        assertEq(asset.balanceOf(address(router)), 1, "P6: router direct residual (fee rounding)");
        _assertNoAllowances();

        uint256 routerDirectAfterFee = asset.balanceOf(address(router));

        // ---- Phase 7: Paused fee-free partial withdrawal ----
        protocol.setPaused(true);
        assertEq(
            uint256(router.strategyState()),
            uint256(RouterStateV2.UpshiftUnavailable),
            "P7: unavailable state"
        );

        uint256 vaultBefore = asset.balanceOf(address(vault));
        uint256 routerDirectForEvent = routerDirectAfterFee;
        uint256 idleForEvent = 100_000 - routerDirectForEvent;

        vm.prank(address(vault));
        vm.expectEmit(false, false, false, true);
        emit IStrategyRouterV2.AssetsWithdrawnToVault(
            100_000, 100_000, routerDirectForEvent, idleForEvent, 0, 0, 0
        );
        uint256 delivered = router.withdrawToVault(100_000);
        assertEq(delivered, 100_000, "P7: delivered");
        assertEq(asset.balanceOf(address(vault)) - vaultBefore, 100_000, "P7: vault received");
        _assertNoAllowances();

        protocol.setPaused(false);
        assertEq(
            uint256(router.strategyState()),
            uint256(RouterStateV2.Operational),
            "P7: operational after unpause"
        );

        // ---- Phase 8: Full withdrawal ----
        vm.prank(address(vault));
        uint256 allDelivered = router.withdrawAllToVault();
        assertGt(allDelivered, 0, "P8: full withdrawal positive");

        // ---- Phase 9: Final reconciliation ----
        assertEq(asset.balanceOf(address(router)), 0, "P9: router direct zero");
        assertEq(asset.balanceOf(address(idle)), 0, "P9: idle zero");
        assertEq(
            asset.balanceOf(address(upshift)), 0, "P9: upshift direct zero (recoverable underlying)"
        );
        assertEq(lpToken.balanceOf(address(upshift)), 0, "P9: upshift LP zero");
        assertEq(idle.positionShares(), 0, "P9: idle position shares zero");
        assertEq(upshift.positionShares(), 0, "P9: upshift position shares zero");

        _assertNoAllowances();
        assertFalse(router.upshiftRecovered(), "P9: not recovered");
        assertFalse(router.executionPaused(), "P9: not paused");
        assertEq(
            uint256(router.strategyState()), uint256(RouterStateV2.Operational), "P9: operational"
        );

        // Privacy-safe event fields: all emitted events contain only public
        // execution evidence (amounts, addresses, booleans). No private intent,
        // salt, allocation signer key, or plaintext mandate field is present.
        // The AssetsWithdrawnToVault event asserted in Phase 7 has only
        // uint256 amount fields — no private data.
    }

    // -----------------------------------------------------------------------
    // Focused integration tests
    // -----------------------------------------------------------------------

    function testPreviewPlanMatchesExecutionForInitialAllocation() external {
        vm.warp(1 hours);
        asset.mint(address(router), 1_000_000);

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(5_000), _validLimits());
        assertTrue(plan.feasible);

        uint256 routerDirectBefore = asset.balanceOf(address(router));
        uint256 idleBefore = asset.balanceOf(address(idle));
        uint256 upshiftLPBefore = lpToken.balanceOf(address(upshift));

        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(5_000), _validLimits(), 1_000_000);

        assertEq(
            asset.balanceOf(address(idle)) - idleBefore,
            plan.idleDepositAssets,
            "idle delta matches plan"
        );
        assertEq(
            lpToken.balanceOf(address(upshift)) - upshiftLPBefore,
            plan.previewedUpshiftSharesOut,
            "upshift LP delta matches plan"
        );
        assertEq(
            routerDirectBefore - asset.balanceOf(address(router)),
            plan.idleDepositAssets + plan.upshiftDepositAssets,
            "router direct delta matches plan"
        );
    }

    function testProtocolPauseBlocksRebalanceButAllowsIdleWithdrawal() external {
        vm.warp(1 hours);
        asset.mint(address(router), 1_000_000);
        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(5_000), _validLimits(), 1_000_000);

        protocol.setPaused(true);
        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftUnavailable));

        RebalancePlanV2 memory plan = router.previewRebalance(_allocation(6_000), _validLimits());
        assertFalse(plan.feasible);
        assertEq(uint256(plan.blocker), uint256(RebalanceBlockerV2.UpshiftUnavailable));

        vm.warp(3 hours);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyRouterV2.RebalanceInfeasible.selector,
                RebalanceBlockerV2.UpshiftUnavailable
            )
        );
        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(6_000), _validLimits(), 0);

        vm.prank(address(vault));
        uint256 delivered = router.withdrawToVault(100_000);
        assertEq(delivered, 100_000);
        assertEq(asset.balanceOf(address(vault)), 100_000);
    }

    function testZeroAllowancesAfterEveryPhase() external {
        vm.warp(1 hours);
        asset.mint(address(router), 1_000_000);

        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(5_000), _validLimits(), 1_000_000);
        _assertNoAllowances();

        vm.warp(3 hours);
        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(8_000), _validLimits(), 0);
        _assertNoAllowances();

        vm.warp(5 hours);
        vm.prank(address(vault));
        router.rebalance(_EXECUTION_ID, _allocation(2_000), _validLimits(), 0);
        _assertNoAllowances();

        vm.prank(address(vault));
        router.withdrawAllToVault();
        _assertNoAllowances();
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    function _assertNoAllowances() internal view {
        assertEq(asset.allowance(address(router), address(idle)), 0, "router->idle allowance zero");
        assertEq(
            asset.allowance(address(router), address(upshift)), 0, "router->upshift allowance zero"
        );
        assertEq(
            asset.allowance(address(upshift), address(protocol)),
            0,
            "upshift->protocol asset allowance zero"
        );
        assertEq(
            lpToken.allowance(address(upshift), address(protocol)),
            0,
            "upshift->protocol LP allowance zero"
        );
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
