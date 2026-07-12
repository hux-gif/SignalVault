// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IdleAdapterV2} from "../../src/v2/adapters/IdleAdapterV2.sol";
import {IStrategyAdapterV2} from "../../src/v2/interfaces/IStrategyAdapterV2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {FalseReturnERC20V2} from "./mocks/FalseReturnERC20V2.sol";
import {ReentrantERC20V2} from "./mocks/ReentrantERC20V2.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract IdleAdapterV2Test is Test {
    MockLPTokenV2 internal asset;
    IdleAdapterV2 internal idle;
    address internal router = address(0xA11CE);
    address internal attacker = address(0xBAD);

    function setUp() public {
        asset = new MockLPTokenV2("MockFXRP", "MFXRP", 6);
        idle = new IdleAdapterV2(IERC20(address(asset)), router);
    }

    // ---- Constructor bindings ----

    function testConstructorBindsAssetAndRouter() external view {
        assertEq(idle.asset(), address(asset));
        assertEq(idle.positionToken(), address(asset));
        assertEq(idle.positionShares(), 0);
        assertEq(idle.totalAssets(), 0);
        assertEq(idle.grossAssets(), 0);
        assertEq(idle.availableLiquidity(), 0);
    }

    function testConstructorRejectsZeroAsset() external {
        vm.expectRevert(IdleAdapterV2.ZeroAddress.selector);
        new IdleAdapterV2(IERC20(address(0)), router);
    }

    function testConstructorRejectsZeroRouter() external {
        vm.expectRevert(IdleAdapterV2.ZeroAddress.selector);
        new IdleAdapterV2(IERC20(address(asset)), address(0));
    }

    // ---- Direct donation accounting ----

    function testDirectDonationIncreasesAllViews() external {
        asset.mint(address(idle), 100);
        assertEq(idle.totalAssets(), 100);
        assertEq(idle.grossAssets(), 100);
        assertEq(idle.availableLiquidity(), 100);
        assertEq(idle.positionShares(), 100);
    }

    function testDirectDonationOfOneMinimumUnit() external {
        asset.mint(address(idle), 1);
        assertEq(idle.totalAssets(), 1);
        assertEq(idle.grossAssets(), 1);
        assertEq(idle.availableLiquidity(), 1);
    }

    // ---- Preview semantics (1:1) ----

    function testPreviewDepositIsOneToOne() external view {
        (uint256 shares, uint256 immediateNetValue) = idle.previewDeposit(0);
        assertEq(shares, 0);
        assertEq(immediateNetValue, 0);

        (shares, immediateNetValue) = idle.previewDeposit(1);
        assertEq(shares, 1);
        assertEq(immediateNetValue, 1);

        (shares, immediateNetValue) = idle.previewDeposit(1_000_000);
        assertEq(shares, 1_000_000);
        assertEq(immediateNetValue, 1_000_000);
    }

    function testPreviewRedeemIsOneToOne() external {
        asset.mint(address(idle), 500);
        (uint256 gross, uint256 net) = idle.previewRedeem(500);
        assertEq(gross, 500);
        assertEq(net, 500);

        (gross, net) = idle.previewRedeem(0);
        assertEq(gross, 0);
        assertEq(net, 0);
    }

    // ---- Access control ----

    function testNonRouterCannotMutateIdle() external {
        vm.expectRevert(IdleAdapterV2.OnlyRouter.selector);
        idle.withdrawLiquid(1);
    }

    function testNonRouterCannotDeposit() external {
        vm.expectRevert(IdleAdapterV2.OnlyRouter.selector);
        idle.deposit(1, 1);
    }

    function testNonRouterCannotRedeem() external {
        vm.expectRevert(IdleAdapterV2.OnlyRouter.selector);
        idle.redeem(1, 1);
    }

    function testNonRouterCannotRedeemAll() external {
        vm.expectRevert(IdleAdapterV2.OnlyRouter.selector);
        idle.redeemAll(1);
    }

    // ---- Zero-amount reverts ----

    function testWithdrawLiquidZeroReverts() external {
        vm.prank(router);
        vm.expectRevert(IdleAdapterV2.ZeroAmount.selector);
        idle.withdrawLiquid(0);
    }

    function testDepositZeroReverts() external {
        vm.prank(router);
        vm.expectRevert(IdleAdapterV2.ZeroAmount.selector);
        idle.deposit(0, 0);
    }

    function testRedeemZeroReverts() external {
        vm.prank(router);
        vm.expectRevert(IdleAdapterV2.ZeroAmount.selector);
        idle.redeem(0, 0);
    }

    // ---- withdrawLiquid: one-to-one, donation-inclusive ----

    function testWithdrawLiquidTransfersExactDirectUnderlying() external {
        asset.mint(address(idle), 100);
        uint256 routerBefore = asset.balanceOf(router);
        vm.prank(router);
        uint256 received = idle.withdrawLiquid(40);
        assertEq(received, 40);
        assertEq(asset.balanceOf(router) - routerBefore, 40);
        assertEq(asset.balanceOf(address(idle)), 60);
        assertEq(idle.totalAssets(), 60);
    }

    function testWithdrawLiquidInsufficientBalanceReverts() external {
        asset.mint(address(idle), 10);
        vm.prank(router);
        vm.expectRevert(IdleAdapterV2.InsufficientBalance.selector);
        idle.withdrawLiquid(11);
    }

    function testWithdrawLiquidFullBalanceLeavesZero() external {
        asset.mint(address(idle), 100);
        vm.prank(router);
        uint256 received = idle.withdrawLiquid(100);
        assertEq(received, 100);
        assertEq(asset.balanceOf(address(idle)), 0);
        assertEq(idle.totalAssets(), 0);
    }

    // ---- deposit: exact pull, measured shares, zero allowance ----

    function testDepositPullsExactAmountAndMeasuresBalanceDelta() external {
        asset.mint(router, 1_000);
        vm.startPrank(router);
        asset.approve(address(idle), 1_000);
        uint256 shares = idle.deposit(1_000, 900);
        vm.stopPrank();
        assertEq(shares, 1_000);
        assertEq(asset.balanceOf(address(idle)), 1_000);
        assertEq(asset.balanceOf(router), 0);
        assertEq(idle.totalAssets(), 1_000);
        assertEq(idle.positionShares(), 1_000);
    }

    function testDepositLeavesZeroAllowanceAfterSuccess() external {
        asset.mint(router, 1_000);
        vm.startPrank(router);
        asset.approve(address(idle), 1_000);
        idle.deposit(1_000, 1);
        vm.stopPrank();
        assertEq(asset.allowance(router, address(idle)), 0);
    }

    function testDepositRespectsMinSharesOut() external {
        asset.mint(router, 1_000);
        vm.startPrank(router);
        asset.approve(address(idle), 1_000);
        vm.expectRevert(IdleAdapterV2.InsufficientSharesOut.selector);
        idle.deposit(1_000, 1_001);
        vm.stopPrank();
    }

    // ---- redeem: measured balance delta, no trust on return ----

    function testRedeemMeasuresBalanceDelta() external {
        asset.mint(address(idle), 500);
        uint256 routerBefore = asset.balanceOf(router);
        vm.prank(router);
        uint256 received = idle.redeem(200, 100);
        assertEq(received, 200);
        assertEq(asset.balanceOf(router) - routerBefore, 200);
        assertEq(asset.balanceOf(address(idle)), 300);
        assertEq(idle.totalAssets(), 300);
    }

    function testRedeemRespectsMinAssetsOut() external {
        asset.mint(address(idle), 500);
        vm.prank(router);
        vm.expectRevert(IdleAdapterV2.InsufficientAssetsOut.selector);
        idle.redeem(200, 201);
    }

    function testRedeemFullBalanceLeavesZero() external {
        asset.mint(address(idle), 500);
        vm.prank(router);
        uint256 received = idle.redeem(500, 1);
        assertEq(received, 500);
        assertEq(asset.balanceOf(address(idle)), 0);
        assertEq(idle.totalAssets(), 0);
    }

    // ---- redeemAll: full recovery, no dust ----

    function testRedeemAllRecoversCompleteBalance() external {
        asset.mint(address(idle), 123);
        uint256 routerBefore = asset.balanceOf(router);
        vm.prank(router);
        uint256 received = idle.redeemAll(1);
        assertEq(received, 123);
        assertEq(asset.balanceOf(router) - routerBefore, 123);
        assertEq(asset.balanceOf(address(idle)), 0);
        assertEq(idle.totalAssets(), 0);
        assertEq(idle.positionShares(), 0);
    }

    function testRedeemAllRespectsMinAssetsOut() external {
        asset.mint(address(idle), 100);
        vm.prank(router);
        vm.expectRevert(IdleAdapterV2.InsufficientAssetsOut.selector);
        idle.redeemAll(101);
    }

    function testRedeemAllOnEmptyReverts() external {
        vm.prank(router);
        vm.expectRevert(IdleAdapterV2.ZeroAmount.selector);
        idle.redeemAll(0);
    }

    // ---- Allowance invariant ----

    function testNoProtocolApprovalCreated() external {
        asset.mint(router, 1_000);
        vm.startPrank(router);
        asset.approve(address(idle), 1_000);
        idle.deposit(1_000, 1);
        vm.stopPrank();
        assertEq(asset.allowance(address(idle), address(0)), 0);
        assertEq(asset.allowance(address(idle), router), 0);
        assertEq(asset.allowance(address(idle), address(this)), 0);
    }

    // ---- False-return token safety ----

    function testFalseReturnTransferRevertsOnWithdrawLiquid() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        IdleAdapterV2 falseIdle = new IdleAdapterV2(IERC20(address(falseAsset)), router);
        falseAsset.mint(address(falseIdle), 100);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.Transfer);
        vm.prank(router);
        vm.expectRevert();
        falseIdle.withdrawLiquid(50);
        // State unchanged, asset not lost.
        assertEq(falseAsset.balanceOf(address(falseIdle)), 100);
        assertEq(falseIdle.totalAssets(), 100);
    }

    function testFalseReturnTransferFromRevertsOnDeposit() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        IdleAdapterV2 falseIdle = new IdleAdapterV2(IERC20(address(falseAsset)), router);
        falseAsset.mint(router, 1_000);
        vm.startPrank(router);
        falseAsset.approve(address(falseIdle), 1_000);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.TransferFrom);
        vm.expectRevert();
        falseIdle.deposit(1_000, 1);
        vm.stopPrank();
        // Asset remains with router.
        assertEq(falseAsset.balanceOf(router), 1_000);
        assertEq(falseAsset.balanceOf(address(falseIdle)), 0);
    }

    // ---- Interface conformance ----

    function testImplementsIStrategyAdapterV2() external pure {
        IStrategyAdapterV2 iface = IdleAdapterV2(address(0));
        iface;
    }

    // ---- protocolStatus semantics ----
    //
    // Idle has no external protocol pause, fee, or withdrawal ceiling.
    // type(uint256).max represents an unbounded reference-asset limit.
    // Consumers must treat it as a sentinel and must not blindly add to it.

    function testProtocolStatusReturnsIdleDefaults() external view {
        (
            bool depositsEnabled,
            bool withdrawalsEnabled,
            uint256 maxWithdrawalReferenceAmount,
            uint256 rawInstantRedemptionFee
        ) = idle.protocolStatus();
        assertEq(depositsEnabled, true);
        assertEq(withdrawalsEnabled, true);
        assertEq(maxWithdrawalReferenceAmount, type(uint256).max);
        assertEq(rawInstantRedemptionFee, 0);
    }

    // ---- Reentrancy protection ----
    //
    // Topology: this test contract is the trusted Router. It calls
    // IdleAdapterV2.deposit, which calls ReentrantERC20V2.transferFrom,
    // which reenters this contract via reenterDeposit(). reenterDeposit()
    // calls adapter.deposit again with msg.sender == router, so onlyRouter
    // passes; the second call must be rejected by ReentrancyGuard.

    ReentrantERC20V2 internal reentrantToken;
    IdleAdapterV2 internal reentrantAdapter;

    function setUpReentrancy() internal {
        reentrantToken = new ReentrantERC20V2();
        // Test contract is the trusted Router.
        reentrantAdapter = new IdleAdapterV2(IERC20(address(reentrantToken)), address(this));
        reentrantToken.mint(address(this), 1_000);
        reentrantToken.approve(address(reentrantAdapter), type(uint256).max);
    }

    /// @notice Reentry callback invoked by ReentrantERC20V2.transferFrom.
    function reenterDeposit() external {
        reentrantAdapter.deposit(1, 1);
    }

    function testDepositReentrancyIsBlocked() external {
        setUpReentrancy();
        bytes memory callback = abi.encodeCall(this.reenterDeposit, ());
        reentrantToken.armCallback(address(this), callback);

        uint256 adapterBefore = reentrantToken.balanceOf(address(reentrantAdapter));
        uint256 routerBefore = reentrantToken.balanceOf(address(this));

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reentrantAdapter.deposit(100, 1);

        // After revert, state must be unchanged.
        assertEq(reentrantToken.balanceOf(address(reentrantAdapter)), adapterBefore);
        assertEq(reentrantToken.balanceOf(address(this)), routerBefore);
    }
}
