// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {FeeAwareUpshiftVaultMock} from "./mocks/FeeAwareUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";

contract UpshiftAdapterV2ExecutionTest is Test {
    bytes4 internal constant ONLY_ROUTER = bytes4(keccak256("OnlyRouter()"));
    bytes4 internal constant ZERO_AMOUNT = bytes4(keccak256("ZeroAmount()"));
    bytes4 internal constant INSUFFICIENT_BALANCE = bytes4(keccak256("InsufficientBalance()"));
    bytes4 internal constant INSUFFICIENT_SHARES_OUT = bytes4(keccak256("InsufficientSharesOut()"));
    bytes4 internal constant INSUFFICIENT_ASSETS_OUT = bytes4(keccak256("InsufficientAssetsOut()"));
    bytes4 internal constant PROTOCOL_PAUSED = bytes4(keccak256("ProtocolPaused()"));
    bytes4 internal constant WITHDRAWAL_LIMIT_EXCEEDED =
        bytes4(keccak256("WithdrawalLimitExceeded()"));

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lp;
    FeeAwareUpshiftVaultMock internal protocol;
    UpshiftAdapterV2 internal adapter;

    address internal attacker = address(0xBAD);

    function setUp() public {
        asset = new MockLPTokenV2("MockFXRP", "MFXRP", 6);
        lp = new MockLPTokenV2("MockUpshiftLP", "MULP", 6);
        protocol = new FeeAwareUpshiftVaultMock(address(asset), address(lp));
        protocol.setInstantFee(50);
        adapter = new UpshiftAdapterV2(
            IERC20(address(asset)), address(this), protocol, IERC20(address(lp))
        );
    }

    function _fundAndApprove(uint256 amount) internal {
        asset.mint(address(this), amount);
        asset.approve(address(adapter), amount);
    }

    function _seedPosition(uint256 shares) internal {
        lp.mint(address(adapter), shares);
        asset.mint(address(protocol), shares);
    }

    function testAllMutationsAreRouterOnly() external {
        vm.startPrank(attacker);
        vm.expectRevert(ONLY_ROUTER);
        adapter.withdrawLiquid(1);
        vm.expectRevert(ONLY_ROUTER);
        adapter.deposit(1, 1);
        vm.expectRevert(ONLY_ROUTER);
        adapter.redeem(1, 1);
        vm.expectRevert(ONLY_ROUTER);
        adapter.redeemAll(1);
        vm.stopPrank();
    }

    function testWithdrawLiquidTransfersOnlyDirectUnderlying() external {
        asset.mint(address(adapter), 100);
        lp.mint(address(adapter), 77);
        uint256 routerBefore = asset.balanceOf(address(this));

        uint256 received = adapter.withdrawLiquid(40);

        assertEq(received, 40);
        assertEq(asset.balanceOf(address(this)) - routerBefore, 40);
        assertEq(asset.balanceOf(address(adapter)), 60);
        assertEq(lp.balanceOf(address(adapter)), 77);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testWithdrawLiquidRejectsZeroAndInsufficientDirectBalance() external {
        vm.expectRevert(ZERO_AMOUNT);
        adapter.withdrawLiquid(0);

        asset.mint(address(adapter), 9);
        vm.expectRevert(INSUFFICIENT_BALANCE);
        adapter.withdrawLiquid(10);
    }

    function testDepositUsesExactAllowanceAndMeasuresLpDelta() external {
        _fundAndApprove(10_000);
        uint256 shares = adapter.deposit(10_000, 9_000);

        assertEq(shares, 10_000);
        assertEq(lp.balanceOf(address(adapter)), 10_000);
        assertEq(asset.balanceOf(address(protocol)), 10_000);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(asset.allowance(address(this), address(adapter)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testDepositUsesActualNonOneToOneLpDelta() external {
        protocol.setDepositRates(2, 1, 3, 1);
        _fundAndApprove(5_000);

        uint256 shares = adapter.deposit(5_000, 9_999);

        assertEq(shares, 10_000);
        assertEq(lp.balanceOf(address(adapter)), 10_000);
    }

    function testDepositDoesNotApproveOrSpendPreexistingDirectUnderlying() external {
        asset.mint(address(adapter), 777);
        _fundAndApprove(1_000);

        adapter.deposit(1_000, 1);

        assertEq(asset.balanceOf(address(adapter)), 777);
        assertEq(asset.balanceOf(address(protocol)), 1_000);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
    }

    function testDepositMinSharesOutRevertsAtomically() external {
        _fundAndApprove(1_000);
        uint256 routerBefore = asset.balanceOf(address(this));

        vm.expectRevert(INSUFFICIENT_SHARES_OUT);
        adapter.deposit(1_000, 1_001);

        assertEq(asset.balanceOf(address(this)), routerBefore);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(asset.balanceOf(address(protocol)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(asset.allowance(address(this), address(adapter)), 1_000);
    }

    function testDepositRejectsZeroPauseAndBindingMismatch() external {
        vm.expectRevert(ZERO_AMOUNT);
        adapter.deposit(0, 0);

        protocol.setPaused(true);
        vm.expectRevert(PROTOCOL_PAUSED);
        adapter.deposit(1, 0);
        protocol.setPaused(false);

        protocol.setReportedAsset(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        adapter.deposit(1, 0);
    }

    function testRedeemMeasuresProtocolLpAndRouterDeltas() external {
        asset.mint(address(adapter), 100);
        _seedPosition(10_000);
        uint256 routerBefore = asset.balanceOf(address(this));

        uint256 received = adapter.redeem(10_000, 9_950);

        assertEq(received, 9_950);
        assertEq(asset.balanceOf(address(this)) - routerBefore, 9_950);
        assertEq(asset.balanceOf(address(adapter)), 100);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testRedeemMinAssetsOutRevertsAtomically() external {
        _seedPosition(10_000);

        vm.expectRevert(INSUFFICIENT_ASSETS_OUT);
        adapter.redeem(10_000, 9_951);

        assertEq(lp.balanceOf(address(adapter)), 10_000);
        assertEq(asset.balanceOf(address(protocol)), 10_000);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(asset.balanceOf(address(this)), 0);
    }

    function testRedeemRejectsZeroInsufficientSharesPauseAndBindingMismatch() external {
        vm.expectRevert(ZERO_AMOUNT);
        adapter.redeem(0, 0);

        vm.expectRevert(INSUFFICIENT_BALANCE);
        adapter.redeem(1, 0);

        _seedPosition(10);
        protocol.setPaused(true);
        vm.expectRevert(PROTOCOL_PAUSED);
        adapter.redeem(1, 0);
        protocol.setPaused(false);

        protocol.setReportedLPToken(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        adapter.redeem(1, 0);
    }

    function testRedeemConservativelyEnforcesGrossLimitBoundary() external {
        _seedPosition(100);
        protocol.setMaxWithdrawalReferenceAmount(100);
        assertEq(adapter.redeem(100, 1), 100);
    }

    function testRedeemRejectsGrossOneAboveLimit() external {
        _seedPosition(101);
        protocol.setMaxWithdrawalReferenceAmount(100);

        vm.expectRevert(WITHDRAWAL_LIMIT_EXCEEDED);
        adapter.redeem(101, 0);
    }

    function testRedeemAllSweepsDirectUnderlyingAndFullPositionWithoutDust() external {
        asset.mint(address(adapter), 100);
        _seedPosition(10_000);
        uint256 routerBefore = asset.balanceOf(address(this));

        uint256 received = adapter.redeemAll(10_050);

        assertEq(received, 10_050);
        assertEq(asset.balanceOf(address(this)) - routerBefore, 10_050);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testRedeemAllSupportsDirectOnlyAndSkipsProtocol() external {
        asset.mint(address(adapter), 123);

        assertEq(adapter.redeemAll(123), 123);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
    }

    function testRedeemAllSupportsFullFeeWhenDirectUnderlyingExists() external {
        protocol.setInstantFee(10_000);
        asset.mint(address(adapter), 7);
        _seedPosition(100);

        assertEq(adapter.redeemAll(7), 7);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
    }

    function testRedeemAllRejectsEmptyAdapter() external {
        vm.expectRevert(ZERO_AMOUNT);
        adapter.redeemAll(0);
    }
}
