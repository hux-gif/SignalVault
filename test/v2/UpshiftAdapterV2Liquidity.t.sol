// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUpshiftVaultV2} from "../../src/v2/interfaces/IUpshiftVaultV2.sol";
import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {FeeAwareUpshiftVaultMock} from "./mocks/FeeAwareUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";

/// @notice Tests for UpshiftAdapterV2 availableLiquidity, conservative dual-limit
/// search, 64-call bound, and boundary conditions.
contract UpshiftAdapterV2LiquidityTest is Test {
    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lp;
    FeeAwareUpshiftVaultMock internal protocol;
    UpshiftAdapterV2 internal adapter;

    address internal router = address(0xA11CE);

    uint256 internal constant FEE_50_BPS = 50;

    function setUp() public {
        asset = new MockLPTokenV2("MockFXRP", "MFXRP", 6);
        lp = new MockLPTokenV2("MockUpshiftLP", "MULP", 6);
        protocol = new FeeAwareUpshiftVaultMock(address(asset), address(lp));
        protocol.setInstantFee(FEE_50_BPS);
        adapter =
            new UpshiftAdapterV2(IERC20(address(asset)), router, protocol, IERC20(address(lp)));
    }

    function seedPosition(uint256 shares) internal {
        lp.mint(address(adapter), shares);
    }

    // ============ Fast paths ============

    function testZeroSharesReturnsDirectOnly() external {
        asset.mint(address(adapter), 500);
        assertEq(adapter.availableLiquidity(), 500);
    }

    function testPausedReturnsDirectOnly() external {
        asset.mint(address(adapter), 300);
        seedPosition(10_000);
        protocol.setPaused(true);
        assertEq(adapter.availableLiquidity(), 300);
    }

    function testZeroLimitReturnsDirectOnly() external {
        asset.mint(address(adapter), 300);
        seedPosition(10_000);
        protocol.setMaxWithdrawalReferenceAmount(0);
        assertEq(adapter.availableLiquidity(), 300);
    }

    function testFullPositionWithinLimitFastPath() external {
        asset.mint(address(adapter), 100);
        seedPosition(10_000);
        // Default mock maxWithdrawalAmount is type(uint256).max.
        (, uint256 expectedNet) = protocol.previewRedemption(10_000, true);
        assertEq(adapter.availableLiquidity(), 100 + expectedNet);
    }

    function testFullPositionFastPathMakesOnePreviewCall() external {
        seedPosition(10_000);
        vm.expectCall(
            address(protocol), abi.encodePacked(IUpshiftVaultV2.previewRedemption.selector), 1
        );
        adapter.availableLiquidity();
    }

    function testZeroSharesMakesNoPreviewCall() external {
        asset.mint(address(adapter), 100);
        vm.expectCall(
            address(protocol), abi.encodePacked(IUpshiftVaultV2.previewRedemption.selector), 0
        );
        adapter.availableLiquidity();
    }

    function testPausedMakesNoPreviewCall() external {
        seedPosition(10_000);
        protocol.setPaused(true);
        vm.expectCall(
            address(protocol), abi.encodePacked(IUpshiftVaultV2.previewRedemption.selector), 0
        );
        adapter.availableLiquidity();
    }

    // ============ Conservative dual-limit boundary ============

    function testGrossAtLimitIsSafe() external {
        seedPosition(10_000);
        // gross = 10_000, net = 9_950. Set limit = 10_000 so gross == limit.
        protocol.setMaxWithdrawalReferenceAmount(10_000);
        (, uint256 expectedNet) = protocol.previewRedemption(10_000, true);
        assertEq(adapter.availableLiquidity(), expectedNet);
    }

    function testGrossAboveLimitTriggersSearch() external {
        seedPosition(10_000);
        // gross = 10_000, limit = 9_999. Full position not safe.
        protocol.setMaxWithdrawalReferenceAmount(9_999);
        uint256 liq = adapter.availableLiquidity();
        // Must be <= net of 9_999 shares (the safe upper bound).
        (, uint256 net9999) = protocol.previewRedemption(9_999, true);
        assertEq(liq, net9999);
    }

    function testNetAtLimitIsSafe() external {
        seedPosition(10_000);
        protocol.setInstantFee(50);
        // net = 10_000 * 9950 / 10000 = 9950. Set limit = 9950.
        protocol.setMaxWithdrawalReferenceAmount(9950);
        // Full position: gross=10000 > 9950=limit → search triggered.
        // But net=9950 == limit → safe for net. gross > limit → not safe.
        // Search finds candidate where both gross <= 9950 and net <= 9950.
        uint256 liq = adapter.availableLiquidity();
        assertGt(liq, 0);
        // Verify the returned value is conservative.
        (, uint256 net9950) = protocol.previewRedemption(9950, true);
        assertEq(liq, net9950);
    }

    function testNetAboveLimitTriggersSearch() external {
        seedPosition(10_000);
        protocol.setInstantFee(50);
        // net = 9950, limit = 9949.
        protocol.setMaxWithdrawalReferenceAmount(9949);
        uint256 liq = adapter.availableLiquidity();
        assertGt(liq, 0);
        (, uint256 net9949) = protocol.previewRedemption(9949, true);
        assertEq(liq, net9949);
    }

    // ============ Partial-position bounded search ============

    function testPartialPositionSearchReturnsVerifiedLowerBound() external {
        seedPosition(10_000);
        // Set limit to 5_000 → only first ~5_000 shares are redeemable.
        protocol.setMaxWithdrawalReferenceAmount(5_000);
        uint256 liq = adapter.availableLiquidity();
        (, uint256 expectedNet) = protocol.previewRedemption(5_000, true);
        assertEq(liq, expectedNet);
    }

    function testPositionExceedingLimitReturnsConservativeLowerBound() external {
        seedPosition(1_000_000);
        protocol.setMaxWithdrawalReferenceAmount(100_000);
        uint256 liq = adapter.availableLiquidity();
        // Must not exceed 100_000 net.
        assertLe(liq, 100_000);
        assertGt(liq, 0);
    }

    // ============ 64-call bound ============

    function testWorstCaseDoesNotExceedMaxRedemptionPreviews() external {
        // Use a very large position to prevent early convergence.
        uint256 largeShares = 1 << 128;
        seedPosition(largeShares);
        // Limit = half the gross so full position is unsafe but half is safe.
        protocol.setMaxWithdrawalReferenceAmount(largeShares / 2);
        vm.expectCall(
            address(protocol), abi.encodePacked(IUpshiftVaultV2.previewRedemption.selector), 64
        );
        adapter.availableLiquidity();
    }

    function testMaxSearchIterationsIs64() external view {
        assertEq(adapter.MAX_SEARCH_ITERATIONS(), 64);
        assertEq(adapter.MAX_TOTAL_REDEMPTION_PREVIEWS(), 64);
    }

    function testMidpointOverflowSafetyWithMaxShares() external {
        // Mint near-max shares to force lo + hi overflow with unsafe midpoint formula.
        // With unsafe (lo + hi) / 2, the first iteration computes (1 + type(uint256).max) / 2
        // which overflows and reverts in Solidity 0.8. The safe formula avoids this.
        seedPosition(type(uint256).max);
        protocol.setMaxWithdrawalReferenceAmount(type(uint256).max / 2);
        uint256 liq = adapter.availableLiquidity();
        assertGt(liq, 0);
    }

    // ============ Selector-prefix varying calldata count ============

    function testSearchProbesVaryCalldata() external {
        seedPosition(10_000);
        protocol.setMaxWithdrawalReferenceAmount(5_000);
        // Binary search probes with different share values.
        // 1 full-position + 13 binary-search iterations + 1 final verification = 15.
        vm.expectCall(
            address(protocol), abi.encodePacked(IUpshiftVaultV2.previewRedemption.selector), 15
        );
        adapter.availableLiquidity();
    }

    // ============ Read-only assertions ============

    function testLiquidityDoesNotChangeBalances() external {
        asset.mint(address(adapter), 1_000);
        seedPosition(10_000);
        protocol.setMaxWithdrawalReferenceAmount(5_000);
        uint256 assetBefore = asset.balanceOf(address(adapter));
        uint256 lpBefore = lp.balanceOf(address(adapter));
        adapter.availableLiquidity();
        assertEq(asset.balanceOf(address(adapter)), assetBefore);
        assertEq(lp.balanceOf(address(adapter)), lpBefore);
    }

    function testLiquidityDoesNotCreateAllowance() external {
        seedPosition(10_000);
        protocol.setMaxWithdrawalReferenceAmount(5_000);
        adapter.availableLiquidity();
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    // ============ Direct underlying always counted ============

    function testDirectUnderlyingCountedEvenWhenPositionExceedsLimit() external {
        asset.mint(address(adapter), 777);
        seedPosition(10_000);
        protocol.setMaxWithdrawalReferenceAmount(1);
        uint256 liq = adapter.availableLiquidity();
        // Even with limit=1, direct underlying is always returned.
        // Position component may be 0 or 1, but direct is 777.
        assertGe(liq, 777);
    }

    function testDirectUnderlyingCountedWhenPaused() external {
        asset.mint(address(adapter), 999);
        seedPosition(10_000);
        protocol.setPaused(true);
        assertEq(adapter.availableLiquidity(), 999);
    }

    function testDirectUnderlyingCountedWithZeroLimit() external {
        asset.mint(address(adapter), 888);
        seedPosition(10_000);
        protocol.setMaxWithdrawalReferenceAmount(0);
        assertEq(adapter.availableLiquidity(), 888);
    }

    /// @dev Verifies that returned liquidity never exceeds the limit, testing
    /// both gross and net boundary. With the mock's invariant net <= gross,
    /// the gross check is always binding; this test documents that the adapter
    /// enforces both and would catch a mutation that removes the net check
    /// if the mock ever produced net > gross.
    function testReturnedLiquidityNeverExceedsLimit() external {
        seedPosition(10_000);
        protocol.setMaxWithdrawalReferenceAmount(5000);
        uint256 liq = adapter.availableLiquidity();
        assertLe(liq, 5000);
        // Verify the returned value equals the net at the found shares.
        (, uint256 net5000) = protocol.previewRedemption(5000, true);
        assertEq(liq, net5000);
    }
}
