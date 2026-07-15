// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
import {FalseReturnERC20V2} from "./mocks/FalseReturnERC20V2.sol";
import {SkimmingERC20V2} from "./mocks/SkimmingERC20V2.sol";

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

contract UnderDebitingOverCreditingERC20V2 is ERC20 {
    constructor() ERC20("Under-debit Token", "UNDER") {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function transferFrom(address owner, address receiver, uint256 amount)
        public
        override
        returns (bool)
    {
        _spendAllowance(owner, msg.sender, amount);
        _transfer(owner, receiver, amount - 1);
        _mint(receiver, 1);
        return true;
    }
}

contract StrategyRouterV2ExecutionTest is Test {
    uint16 private constant _BPS = 10_000;
    bytes32 private constant _EXECUTION_ID = keccak256("TASK_4_EXECUTION");

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
        (router, idle, upshift, vault) = _deploy(IERC20(address(asset)));
    }

    function testDirectBufferMovesOnlyIntoIdleAndLeavesNoAllowance() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});

        _rebalance(_halfAndHalf(), 20);

        assertEq(idle.lastDepositAssets(), 20);
        assertEq(idle.lastDepositMinSharesOut(), 20);
        assertEq(idle.lastObservedAllowance(), 20);
        assertEq(idle.depositCallCount(), 1);
        assertEq(idle.withdrawLiquidCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
        assertEq(asset.allowance(address(router), address(idle)), 0);
        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(idle)), 50);
    }

    function testInitialOneHundredPercentIdleMovesOnlyPlannedDelta() external {
        _seed({routerDirect: 100, idleAssets: 0, upshiftAssets: 0});

        _rebalance(_allocation(0), 100);

        assertEq(idle.lastDepositAssets(), 100);
        assertEq(idle.depositCallCount(), 1);
        assertEq(idle.withdrawLiquidCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
        assertEq(asset.balanceOf(address(idle)), 100);
        assertEq(asset.allowance(address(router), address(idle)), 0);
    }

    function testIdleWithdrawalMovesOnlyPlannedDelta() external {
        _seed({routerDirect: 0, idleAssets: 80, upshiftAssets: 20});

        _rebalance(_halfAndHalf(), 0);

        assertEq(idle.lastWithdrawLiquidAssets(), 30);
        assertEq(idle.withdrawLiquidCallCount(), 1);
        assertEq(idle.depositCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
        assertEq(asset.balanceOf(address(router)), 30);
        assertEq(asset.balanceOf(address(idle)), 50);
    }

    function testDirectBufferPriorityLimitsIdleWithdrawalToExactDelta() external {
        _seed({routerDirect: 20, idleAssets: 60, upshiftAssets: 20});

        _rebalance(_halfAndHalf(), 0);

        assertEq(idle.lastWithdrawLiquidAssets(), 10);
        assertEq(idle.withdrawLiquidCallCount(), 1);
        assertEq(upshift.stateChangingCallCount(), 0);
        assertEq(asset.balanceOf(address(router)), 30);
        assertEq(asset.balanceOf(address(idle)), 50);
    }

    function testFundingDeclarationCannotExceedEntryBalance() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});

        vm.expectRevert(abi.encodeWithSelector(IStrategyRouterV2.FundingMismatch.selector, 21, 20));
        _rebalance(_halfAndHalf(), 21);

        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testExistingRouterDonationIsNotMisreportedAsFunding() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});

        _rebalance(_halfAndHalf(), 0);

        assertEq(idle.lastDepositAssets(), 20);
        assertEq(idle.depositCallCount(), 1);
    }

    function testRebalanceRecomputesIdlePlanAtExecution() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});
        RebalancePlanV2 memory stale = router.previewRebalance(_halfAndHalf(), _validLimits());
        assertEq(stale.idleDepositAssets, 20);
        asset.mint(address(idle), 10);

        _rebalance(_halfAndHalf(), 20);

        assertEq(idle.lastDepositAssets(), 15);
        assertEq(asset.balanceOf(address(router)), 5);
        assertEq(asset.balanceOf(address(idle)), 55);
    }

    function testIdleUnderReceiptRevertsAndRollsBack() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});
        idle.setDepositExecution(20, 19, 19, 19);

        vm.expectRevert(IStrategyRouterV2.AdapterDeltaMismatch.selector);
        _rebalance(_halfAndHalf(), 20);

        _assertDepositRollback();
    }

    function testIdleUnderDebitWithExactAdapterCreditReverts() external {
        UnderDebitingOverCreditingERC20V2 hostileAsset = new UnderDebitingOverCreditingERC20V2();
        (
            StrategyRouterV2 hostileRouter,
            InstrumentedStrategyAdapterV2 hostileIdle,
            InstrumentedStrategyAdapterV2 hostileUpshift,
            ReentrantRouterVaultV2 hostileVault
        ) = _deploy(IERC20(address(hostileAsset)));
        hostileAsset.mint(address(hostileRouter), 20);
        hostileAsset.mint(address(hostileIdle), 30);
        hostileUpshift.setPositionValues(50, 50, 50, 50);

        vm.expectRevert(IStrategyRouterV2.AssetDeltaMismatch.selector);
        vm.prank(address(hostileVault));
        IStrategyRouterV2(address(hostileRouter))
            .rebalance(_EXECUTION_ID, _halfAndHalf(), _validLimits(), 20);

        assertEq(hostileAsset.balanceOf(address(hostileRouter)), 20);
        assertEq(hostileAsset.balanceOf(address(hostileIdle)), 30);
        assertEq(hostileAsset.allowance(address(hostileRouter), address(hostileIdle)), 0);
    }

    function testIdleOverReportWithoutTransferReverts() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});
        idle.setDepositExecution(0, 0, 0, 20);

        vm.expectRevert(IStrategyRouterV2.AssetDeltaMismatch.selector);
        _rebalance(_halfAndHalf(), 20);

        _assertDepositRollback();
    }

    function testIdleOverReportWithExactTransferReverts() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});
        idle.setDepositExecution(20, 20, 20, 21);

        vm.expectRevert(IStrategyRouterV2.AdapterDeltaMismatch.selector);
        _rebalance(_halfAndHalf(), 20);

        _assertDepositRollback();
    }

    function testIdleOverDebitRevertsAndRollsBack() external {
        _seed({routerDirect: 21, idleAssets: 30, upshiftAssets: 49});
        idle.setDepositExecution(21, 21, 21, 21);

        // The exact 20-unit approval rejects the attempted 21-unit debit before Router
        // reconciliation. This is still a required fail-closed outcome.
        vm.expectRevert();
        _rebalance(_halfAndHalf(), 21);

        assertEq(asset.balanceOf(address(router)), 21);
        assertEq(asset.balanceOf(address(idle)), 30);
        assertEq(asset.allowance(address(router), address(idle)), 0);
    }

    function testIdleWithdrawalUnderCreditRevertsAndRollsBack() external {
        _seed({routerDirect: 0, idleAssets: 80, upshiftAssets: 20});
        idle.setWithdrawalExecution(30, 29, 29);

        vm.expectRevert(IStrategyRouterV2.AssetDeltaMismatch.selector);
        _rebalance(_halfAndHalf(), 0);

        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(idle)), 80);
    }

    function testIdleWithdrawalOverDebitRevertsAndRollsBack() external {
        _seed({routerDirect: 0, idleAssets: 80, upshiftAssets: 20});
        idle.setWithdrawalExecution(31, 30, 30);

        vm.expectRevert(IStrategyRouterV2.AdapterDeltaMismatch.selector);
        _rebalance(_halfAndHalf(), 0);

        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(idle)), 80);
    }

    function testIdleWithdrawalOverReportWithoutTransferReverts() external {
        _seed({routerDirect: 0, idleAssets: 80, upshiftAssets: 20});
        idle.setWithdrawalExecution(30, 0, 30);

        vm.expectRevert(IStrategyRouterV2.AssetDeltaMismatch.selector);
        _rebalance(_halfAndHalf(), 0);

        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(idle)), 80);
    }

    function testIdleWithdrawalOverReportWithExactTransferReverts() external {
        _seed({routerDirect: 0, idleAssets: 80, upshiftAssets: 20});
        idle.setWithdrawalExecution(30, 30, 31);

        vm.expectRevert(IStrategyRouterV2.AdapterDeltaMismatch.selector);
        _rebalance(_halfAndHalf(), 0);

        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(idle)), 80);
    }

    function testIdleProtocolRevertRollsBackApprovalAndBalances() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});
        idle.setDepositReverts(true);

        vm.expectRevert(InstrumentedStrategyAdapterV2.ForcedExecutionRevert.selector);
        _rebalance(_halfAndHalf(), 20);

        _assertDepositRollback();
    }

    function testIdleFalseReturnTransferFromFailsClosed() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        (
            StrategyRouterV2 falseRouter,
            InstrumentedStrategyAdapterV2 falseIdle,
            InstrumentedStrategyAdapterV2 falseUpshift,
            ReentrantRouterVaultV2 falseVault
        ) = _deploy(IERC20(address(falseAsset)));
        falseAsset.mint(address(falseRouter), 20);
        falseAsset.mint(address(falseIdle), 30);
        falseUpshift.setPositionValues(50, 50, 50, 50);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.TransferFrom);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseAsset))
        );
        vm.prank(address(falseVault));
        IStrategyRouterV2(address(falseRouter))
            .rebalance(_EXECUTION_ID, _halfAndHalf(), _validLimits(), 20);

        assertEq(falseAsset.balanceOf(address(falseRouter)), 20);
        assertEq(falseAsset.balanceOf(address(falseIdle)), 30);
        assertEq(falseAsset.allowance(address(falseRouter), address(falseIdle)), 0);
    }

    function testIdleFeeOnTransferUnderDeliveryFailsClosed() external {
        SkimmingERC20V2 skimAsset = new SkimmingERC20V2();
        (
            StrategyRouterV2 skimRouter,
            InstrumentedStrategyAdapterV2 skimIdle,
            InstrumentedStrategyAdapterV2 skimUpshift,
            ReentrantRouterVaultV2 skimVault
        ) = _deploy(IERC20(address(skimAsset)));
        skimAsset.mint(address(skimRouter), 20);
        skimAsset.mint(address(skimIdle), 30);
        skimUpshift.setPositionValues(50, 50, 50, 50);
        skimAsset.setTransferFromShortfall(address(skimRouter), 1);

        vm.expectRevert(IStrategyRouterV2.AdapterDeltaMismatch.selector);
        vm.prank(address(skimVault));
        IStrategyRouterV2(address(skimRouter))
            .rebalance(_EXECUTION_ID, _halfAndHalf(), _validLimits(), 20);

        assertEq(skimAsset.balanceOf(address(skimRouter)), 20);
        assertEq(skimAsset.balanceOf(address(skimIdle)), 30);
        assertEq(skimAsset.allowance(address(skimRouter), address(skimIdle)), 0);
    }

    function testIdleNoOpMakesZeroStateChangingCalls() external {
        _seed({routerDirect: 0, idleAssets: 50, upshiftAssets: 50});

        uint256 totalAfter = _rebalance(_halfAndHalf(), 0);

        assertEq(totalAfter, 100);
        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
        assertEq(router.lastRebalanceTimestamp(), 0);
    }

    function testIdleInfeasiblePlanRevertsBeforeMutation() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});
        AllocationV2 memory invalid = _halfAndHalf();
        invalid.firelightBps = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyRouterV2.RebalanceInfeasible.selector, RebalanceBlockerV2.InvalidAllocation
            )
        );
        _rebalance(invalid, 20);

        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testIdleRebalanceRejectsNonVaultCaller() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});

        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        IStrategyRouterV2(address(router))
            .rebalance(_EXECUTION_ID, _halfAndHalf(), _validLimits(), 20);

        assertEq(idle.stateChangingCallCount(), 0);
    }

    function testIdleRebalanceRejectsReentrancy() external {
        _seed({routerDirect: 20, idleAssets: 30, upshiftAssets: 50});
        bytes memory nested = abi.encodeCall(
            IStrategyRouterV2.rebalance, (_EXECUTION_ID, _halfAndHalf(), _validLimits(), 20)
        );
        vault.arm(address(router), nested);
        idle.setDepositCallback(address(vault), abi.encodeCall(vault.reenter, ()));

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _rebalance(_halfAndHalf(), 20);

        _assertDepositRollback();
    }

    function _seed(uint256 routerDirect, uint256 idleAssets, uint256 upshiftAssets) internal {
        if (routerDirect != 0) asset.mint(address(router), routerDirect);
        if (idleAssets != 0) asset.mint(address(idle), idleAssets);
        upshift.setPositionValues(upshiftAssets, upshiftAssets, upshiftAssets, upshiftAssets);
    }

    function _rebalance(AllocationV2 memory target, uint256 fundingAssets)
        internal
        returns (uint256 totalAssetsAfter)
    {
        vm.prank(address(vault));
        return IStrategyRouterV2(address(router))
            .rebalance(_EXECUTION_ID, target, _validLimits(), fundingAssets);
    }

    function _assertDepositRollback() internal view {
        assertEq(asset.balanceOf(address(router)), 20);
        assertEq(asset.balanceOf(address(idle)), 30);
        assertEq(asset.allowance(address(router), address(idle)), 0);
    }

    function _deploy(IERC20 asset_)
        internal
        returns (
            StrategyRouterV2 deployedRouter,
            InstrumentedStrategyAdapterV2 deployedIdle,
            InstrumentedStrategyAdapterV2 deployedUpshift,
            ReentrantRouterVaultV2 deployedVault
        )
    {
        deployedRouter = new StrategyRouterV2(asset_, owner);
        deployedIdle =
            new InstrumentedStrategyAdapterV2(asset_, address(deployedRouter), address(asset_));
        deployedUpshift =
            new InstrumentedStrategyAdapterV2(asset_, address(deployedRouter), address(lpToken));
        deployedVault = new ReentrantRouterVaultV2(owner);

        vm.startPrank(owner);
        deployedRouter.configureAdapters(address(deployedUpshift), address(deployedIdle));
        deployedRouter.configureRisk(_risk());
        deployedRouter.bindVault(address(deployedVault));
        vm.stopPrank();
    }

    function _halfAndHalf() internal pure returns (AllocationV2 memory) {
        return _allocation(5_000);
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
