// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUpshiftVaultV2} from "../../src/v2/interfaces/IUpshiftVaultV2.sol";
import {IStrategyAdapterV2} from "../../src/v2/interfaces/IStrategyAdapterV2.sol";
import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {FeeAwareUpshiftVaultMock} from "./mocks/FeeAwareUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";

/// @notice Tests for UpshiftAdapterV2 accounting views, composed previews, protocol
/// status, binding verification, and malformed-preview fail-closed behavior.
contract UpshiftAdapterV2AccountingTest is Test {
    bytes4 internal constant PREVIEW_ZERO_NET = bytes4(keccak256("PreviewZeroNet()"));
    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lp;
    FeeAwareUpshiftVaultMock internal protocol;
    UpshiftAdapterV2 internal adapter;

    address internal router = address(0xA11CE);
    address internal attacker = address(0xBAD);

    uint256 internal constant FEE_50_BPS = 50;

    function setUp() public {
        asset = new MockLPTokenV2("MockFXRP", "MFXRP", 6);
        lp = new MockLPTokenV2("MockUpshiftLP", "MULP", 6);
        protocol = new FeeAwareUpshiftVaultMock(address(asset), address(lp));
        protocol.setInstantFee(FEE_50_BPS);
        adapter =
            new UpshiftAdapterV2(IERC20(address(asset)), router, protocol, IERC20(address(lp)));
    }

    /// @dev Mint LP tokens directly to the adapter, simulating an existing position.
    function seedPosition(uint256 shares) internal {
        lp.mint(address(adapter), shares);
    }

    // ============ Constructor and binding ============

    function testConstructorBindsAssetRouterProtocolAndLPToken() external view {
        assertEq(adapter.asset(), address(asset));
        assertEq(adapter.positionToken(), address(lp));
        assertEq(adapter.router(), router);
        assertEq(adapter.positionShares(), 0);
    }

    function testConstructorRejectsZeroAsset() external {
        vm.expectRevert(UpshiftAdapterV2.ZeroAddress.selector);
        new UpshiftAdapterV2(IERC20(address(0)), router, protocol, IERC20(address(lp)));
    }

    function testConstructorRejectsZeroRouter() external {
        vm.expectRevert(UpshiftAdapterV2.ZeroAddress.selector);
        new UpshiftAdapterV2(IERC20(address(asset)), address(0), protocol, IERC20(address(lp)));
    }

    function testConstructorRejectsZeroProtocol() external {
        vm.expectRevert(UpshiftAdapterV2.ZeroAddress.selector);
        new UpshiftAdapterV2(
            IERC20(address(asset)), router, IUpshiftVaultV2(address(0)), IERC20(address(lp))
        );
    }

    function testConstructorRejectsZeroLPToken() external {
        vm.expectRevert(UpshiftAdapterV2.ZeroAddress.selector);
        new UpshiftAdapterV2(IERC20(address(asset)), router, protocol, IERC20(address(0)));
    }

    function testConstructorRejectsReportedAssetMismatch() external {
        protocol.setReportedAsset(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        new UpshiftAdapterV2(IERC20(address(asset)), router, protocol, IERC20(address(lp)));
    }

    function testConstructorRejectsReportedLPTokenMismatch() external {
        protocol.setReportedLPToken(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        new UpshiftAdapterV2(IERC20(address(asset)), router, protocol, IERC20(address(lp)));
    }

    function testRuntimeAssetMismatchFailsClosed() external {
        seedPosition(10_000);
        protocol.setReportedAsset(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        adapter.totalAssets();
    }

    function testRuntimeLPTokenMismatchFailsClosed() external {
        seedPosition(10_000);
        protocol.setReportedLPToken(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        adapter.totalAssets();
    }

    // ============ Position views ============

    function testPositionSharesReflectsLPTokenBalance() external {
        assertEq(adapter.positionShares(), 0);
        seedPosition(5_000);
        assertEq(adapter.positionShares(), 5_000);
        assertEq(adapter.positionToken(), address(lp));
    }

    function testPositionTokenIsLPTokenNotVault() external view {
        assertTrue(adapter.positionToken() != address(protocol));
        assertEq(adapter.positionToken(), address(lp));
    }

    // ============ NAV: direct + LP ============

    function testTotalGrossAndLiquidityIncludeDirectUnderlyingOnce() external {
        asset.mint(address(adapter), 7);
        seedPosition(10_000);
        (uint256 gross, uint256 net) = adapter.previewRedeem(adapter.positionShares());
        assertEq(adapter.totalAssets(), 7 + net);
        assertEq(adapter.grossAssets(), 7 + gross);
    }

    function testDirectOnlyNAV() external {
        asset.mint(address(adapter), 100);
        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.grossAssets(), 100);
        assertEq(adapter.availableLiquidity(), 100);
    }

    function testLPOnlyNetAndGrossNAV() external {
        seedPosition(10_000);
        (uint256 expectedGross, uint256 expectedNet) = protocol.previewRedemption(10_000, true);
        assertEq(adapter.totalAssets(), expectedNet);
        assertEq(adapter.grossAssets(), expectedGross);
    }

    function testDirectPlusLPNAV() external {
        asset.mint(address(adapter), 500);
        seedPosition(10_000);
        (, uint256 expectedNet) = protocol.previewRedemption(10_000, true);
        (uint256 expectedGross,) = protocol.previewRedemption(10_000, true);
        assertEq(adapter.totalAssets(), 500 + expectedNet);
        assertEq(adapter.grossAssets(), 500 + expectedGross);
    }

    function testDirectDonationAfterLPPosition() external {
        seedPosition(10_000);
        asset.mint(address(adapter), 300);
        (, uint256 expectedNet) = protocol.previewRedemption(10_000, true);
        assertEq(adapter.totalAssets(), 300 + expectedNet);
    }

    function testZeroPositionZeroDirectNAV() external view {
        assertEq(adapter.totalAssets(), 0);
        assertEq(adapter.grossAssets(), 0);
        assertEq(adapter.availableLiquidity(), 0);
    }

    function testDynamicFeeChangesNetButNotGross() external {
        seedPosition(10_000);
        (uint256 grossBefore, uint256 netBefore) = adapter.previewRedeem(10_000);
        protocol.setInstantFee(100);
        (uint256 grossAfter, uint256 netAfter) = adapter.previewRedeem(10_000);
        assertEq(grossAfter, grossBefore);
        assertLt(netAfter, netBefore);
        assertEq(adapter.totalAssets(), netAfter);
        assertEq(adapter.grossAssets(), grossAfter);
    }

    function testTotalAssetsRejectsZeroNetForNonzeroPositionDespiteDirectUnderlying() external {
        asset.mint(address(adapter), 200);
        seedPosition(10_000);
        protocol.setInstantFee(10_000);
        vm.expectRevert(PREVIEW_ZERO_NET);
        adapter.totalAssets();
    }

    function testGrossAssetsRejectsZeroNetForNonzeroPositionDespiteDirectUnderlying() external {
        asset.mint(address(adapter), 200);
        seedPosition(10_000);
        protocol.setInstantFee(10_000);
        vm.expectRevert(PREVIEW_ZERO_NET);
        adapter.grossAssets();
    }

    // ============ Composed previewDeposit ============

    function testPreviewDepositComposesBothProtocolPreviews() external view {
        (uint256 shares, uint256 immediateNet) = adapter.previewDeposit(10_000);
        (uint256 expectedShares,) = protocol.previewDeposit(address(asset), 10_000);
        (, uint256 expectedNet) = protocol.previewRedemption(expectedShares, true);
        assertEq(shares, expectedShares);
        assertEq(immediateNet, expectedNet);
    }

    function testPreviewDepositNonOneToOneShareRate() external {
        // shares = 2x, reference = 3x so net <= reference holds.
        protocol.setDepositRates(2, 1, 3, 1);
        (uint256 shares, uint256 immediateNet) = adapter.previewDeposit(5_000);
        assertEq(shares, 10_000);
        (, uint256 expectedNet) = protocol.previewRedemption(10_000, true);
        assertEq(immediateNet, expectedNet);
    }

    function testPreviewDepositReferenceAmountIsNotNet() external {
        protocol.setDepositRates(1, 1, 3, 1);
        (uint256 shares, uint256 immediateNet) = adapter.previewDeposit(1_000);
        (, uint256 referenceAmount) = protocol.previewDeposit(address(asset), 1_000);
        assertGt(referenceAmount, immediateNet);
        assertEq(shares, 1_000);
        (, uint256 expectedNet) = protocol.previewRedemption(1_000, true);
        assertEq(immediateNet, expectedNet);
    }

    function testPreviewDepositRejectsZeroShares() external {
        protocol.setDepositPreviewOverride(100, true, 0, 100);
        vm.expectRevert(UpshiftAdapterV2.PreviewZeroShares.selector);
        adapter.previewDeposit(100);
    }

    function testPreviewDepositRejectsZeroReferenceAmount() external {
        protocol.setDepositPreviewOverride(100, true, 50, 0);
        vm.expectRevert(UpshiftAdapterV2.PreviewZeroReferenceAmount.selector);
        adapter.previewDeposit(100);
    }

    function testPreviewDepositRejectsNetExceedingReference() external {
        // shares = 100, reference = 50, gross = 100, net = 80
        protocol.setDepositPreviewOverride(100, true, 100, 50);
        protocol.setRedemptionPreviewOverride(100, true, 100, 80, 100);
        vm.expectRevert(UpshiftAdapterV2.PreviewNetExceedsReference.selector);
        adapter.previewDeposit(100);
    }

    function testPreviewDepositRejectsZeroNetForNonzeroExpectedShares() external {
        protocol.setInstantFee(10_000);
        vm.expectRevert(PREVIEW_ZERO_NET);
        adapter.previewDeposit(100);
    }

    // ============ previewRedeem ============

    function testPreviewRedeemOneToOneWithProtocol() external {
        seedPosition(10_000);
        (uint256 gross, uint256 net) = adapter.previewRedeem(10_000);
        (uint256 pGross, uint256 pNet) = protocol.previewRedemption(10_000, true);
        assertEq(gross, pGross);
        assertEq(net, pNet);
    }

    function testPreviewRedeemZeroSharesReturnsZero() external view {
        (uint256 gross, uint256 net) = adapter.previewRedeem(0);
        assertEq(gross, 0);
        assertEq(net, 0);
    }

    function testPreviewRedeemRejectsZeroGrossForNonzeroShares() external {
        protocol.setRedemptionPreviewOverride(500, true, 0, 0, 0);
        vm.expectRevert(UpshiftAdapterV2.PreviewZeroGross.selector);
        adapter.previewRedeem(500);
    }

    function testPreviewRedeemRejectsNetExceedingGross() external {
        protocol.setRedemptionPreviewOverride(500, true, 100, 200, 100);
        vm.expectRevert(UpshiftAdapterV2.PreviewNetExceedsGross.selector);
        adapter.previewRedeem(500);
    }

    function testPreviewRedeemRejectsZeroNetForNonzeroShares() external {
        protocol.setRedemptionPreviewOverride(500, true, 100, 0, 100);
        vm.expectRevert(PREVIEW_ZERO_NET);
        adapter.previewRedeem(500);
    }

    // ============ protocolStatus ============

    function testProtocolStatusReportsLiveValues() external {
        protocol.setInstantFee(75);
        protocol.setMaxWithdrawalReferenceAmount(50_000);
        (
            bool depositsEnabled,
            bool withdrawalsEnabled,
            uint256 maxWithdrawalReferenceAmount,
            uint256 rawInstantRedemptionFee
        ) = adapter.protocolStatus();
        assertTrue(depositsEnabled);
        assertTrue(withdrawalsEnabled);
        assertEq(maxWithdrawalReferenceAmount, 50_000);
        assertEq(rawInstantRedemptionFee, 75);
    }

    function testProtocolStatusPauseDisablesDepositsAndWithdrawals() external {
        protocol.setPaused(true);
        (bool depositsEnabled, bool withdrawalsEnabled,,) = adapter.protocolStatus();
        assertFalse(depositsEnabled);
        assertFalse(withdrawalsEnabled);
    }

    function testProtocolStatusReflectsDynamicFeeChange() external {
        (,,, uint256 feeBefore) = adapter.protocolStatus();
        assertEq(feeBefore, FEE_50_BPS);
        protocol.setInstantFee(200);
        (,,, uint256 feeAfter) = adapter.protocolStatus();
        assertEq(feeAfter, 200);
    }

    function testProtocolStatusReflectsDynamicLimitChange() external {
        protocol.setMaxWithdrawalReferenceAmount(999);
        (,, uint256 limit,) = adapter.protocolStatus();
        assertEq(limit, 999);
    }

    function testProtocolStatusDisablesBothFlagsOnAssetBindingMismatch() external {
        protocol.setReportedAsset(address(0xDEAD));
        protocol.setInstantFee(75);
        protocol.setMaxWithdrawalReferenceAmount(50_000);
        (bool depositsEnabled, bool withdrawalsEnabled, uint256 limit, uint256 fee) =
            adapter.protocolStatus();
        assertFalse(depositsEnabled);
        assertFalse(withdrawalsEnabled);
        assertEq(limit, 50_000);
        assertEq(fee, 75);
    }

    function testProtocolStatusDisablesBothFlagsOnLPBindingMismatch() external {
        protocol.setReportedLPToken(address(0xDEAD));
        (bool depositsEnabled, bool withdrawalsEnabled,,) = adapter.protocolStatus();
        assertFalse(depositsEnabled);
        assertFalse(withdrawalsEnabled);
    }

    function testProtocolStatusDisablesBothFlagsWhenBothBindingsMismatch() external {
        protocol.setReportedAsset(address(0xDEAD));
        protocol.setReportedLPToken(address(0xBEEF));
        (bool depositsEnabled, bool withdrawalsEnabled,,) = adapter.protocolStatus();
        assertFalse(depositsEnabled);
        assertFalse(withdrawalsEnabled);
    }

    function testProtocolStatusBindingMismatchAndPauseRemainDisabled() external {
        protocol.setReportedAsset(address(0xDEAD));
        protocol.setPaused(true);
        (bool depositsEnabled, bool withdrawalsEnabled, uint256 limit,) = adapter.protocolStatus();
        assertFalse(depositsEnabled);
        assertFalse(withdrawalsEnabled);
        assertEq(limit, 0);
    }

    function testProtocolStatusDisablesBothFlagsWhenBindingGetterReverts() external {
        vm.mockCallRevert(
            address(protocol),
            abi.encodeWithSelector(IUpshiftVaultV2.asset.selector),
            bytes("asset getter")
        );
        (bool depositsEnabled, bool withdrawalsEnabled,,) = adapter.protocolStatus();
        assertFalse(depositsEnabled);
        assertFalse(withdrawalsEnabled);
    }

    function testProtocolStatusPropagatesFeeGetterRevert() external {
        vm.mockCallRevert(
            address(protocol),
            abi.encodeWithSelector(IUpshiftVaultV2.instantRedemptionFee.selector),
            bytes("fee getter")
        );
        vm.expectRevert(bytes("fee getter"));
        adapter.protocolStatus();
    }

    function testProtocolStatusPropagatesLimitGetterRevert() external {
        vm.mockCallRevert(
            address(protocol),
            abi.encodeWithSelector(IUpshiftVaultV2.maxWithdrawalAmount.selector),
            bytes("limit getter")
        );
        vm.expectRevert(bytes("limit getter"));
        adapter.protocolStatus();
    }

    // ============ Malformed preview / fail closed ============

    function testTotalAssetsFailsClosedOnPreviewRevert() external {
        seedPosition(10_000);
        // Configure override with gross=0 to trigger PreviewZeroGross.
        protocol.setRedemptionPreviewOverride(10_000, true, 0, 0, 0);
        vm.expectRevert(UpshiftAdapterV2.PreviewZeroGross.selector);
        adapter.totalAssets();
    }

    function testGrossAssetsFailsClosedOnPreviewRevert() external {
        seedPosition(10_000);
        protocol.setRedemptionPreviewOverride(10_000, true, 0, 0, 0);
        vm.expectRevert(UpshiftAdapterV2.PreviewZeroGross.selector);
        adapter.grossAssets();
    }

    function testPreviewRedeemFailsClosedOnNetExceedsGross() external {
        protocol.setRedemptionPreviewOverride(777, true, 100, 150, 100);
        vm.expectRevert(UpshiftAdapterV2.PreviewNetExceedsGross.selector);
        adapter.previewRedeem(777);
    }

    // ============ Read-only assertions ============

    function testViewsDoNotChangeUnderlyingBalance() external {
        asset.mint(address(adapter), 1_000);
        seedPosition(10_000);
        uint256 before = asset.balanceOf(address(adapter));
        adapter.totalAssets();
        adapter.grossAssets();
        adapter.availableLiquidity();
        adapter.previewDeposit(100);
        adapter.previewRedeem(10_000);
        adapter.protocolStatus();
        assertEq(asset.balanceOf(address(adapter)), before);
    }

    function testViewsDoNotChangeLPBalance() external {
        seedPosition(10_000);
        uint256 before = lp.balanceOf(address(adapter));
        adapter.totalAssets();
        adapter.grossAssets();
        adapter.availableLiquidity();
        adapter.previewDeposit(100);
        adapter.previewRedeem(10_000);
        assertEq(lp.balanceOf(address(adapter)), before);
    }

    function testViewsDoNotCreateAllowance() external {
        seedPosition(10_000);
        adapter.totalAssets();
        adapter.grossAssets();
        adapter.availableLiquidity();
        adapter.previewDeposit(100);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
        assertEq(asset.allowance(address(adapter), router), 0);
    }

    // ============ Task 4 execution access boundary ============

    function testDepositRequiresRouter() external {
        vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
        adapter.deposit(1, 1);
    }

    function testRedeemRequiresRouter() external {
        vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
        adapter.redeem(1, 1);
    }

    function testRedeemAllRequiresRouter() external {
        vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
        adapter.redeemAll(1);
    }

    function testWithdrawLiquidRequiresRouter() external {
        vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
        adapter.withdrawLiquid(1);
    }

    function testUnauthorizedMutationsDoNotCreateAllowanceOrTransfer() external {
        asset.mint(address(adapter), 1_000);
        seedPosition(1_000);
        uint256 assetBefore = asset.balanceOf(address(adapter));
        uint256 lpBefore = lp.balanceOf(address(adapter));

        vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
        adapter.deposit(1, 1);
        vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
        adapter.redeem(1, 1);
        vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
        adapter.redeemAll(1);
        vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
        adapter.withdrawLiquid(1);

        assertEq(asset.balanceOf(address(adapter)), assetBefore);
        assertEq(lp.balanceOf(address(adapter)), lpBefore);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    // ============ Interface conformance ============

    function testImplementsIStrategyAdapterV2() external pure {
        IStrategyAdapterV2 iface = UpshiftAdapterV2(address(0));
        iface;
    }
}
