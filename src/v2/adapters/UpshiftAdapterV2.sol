// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyAdapterV2} from "../interfaces/IStrategyAdapterV2.sol";
import {IUpshiftVaultV2} from "../interfaces/IUpshiftVaultV2.sol";

/// @notice UpshiftAdapterV2 holds underlying and Upshift LP shares and provides read-only
/// valuation views, composed deposit preview, protocol status, and a conservative bounded
/// liquidity search. State-changing execution (deposit/redeem/withdrawLiquid/redeemAll)
/// is implemented in Task 4; this contract reverts those selectors.
contract UpshiftAdapterV2 is IStrategyAdapterV2 {
    IERC20 private immutable _asset;
    address public immutable router;
    IUpshiftVaultV2 private immutable _protocol;
    IERC20 private immutable _lpToken;

    /// @notice Maximum binary-search iterations for the liquidity probe.
    uint256 public constant MAX_SEARCH_ITERATIONS = 64;

    /// @notice Maximum total previewRedemption calls per availableLiquidity() invocation.
    /// Equals 1 full-position probe + 62 binary-search probes + 1 final verification probe.
    uint256 public constant MAX_TOTAL_REDEMPTION_PREVIEWS = 64;

    error ZeroAddress();
    error AssetBindingMismatch();
    error LPBindingMismatch();
    error PreviewZeroShares();
    error PreviewZeroReferenceAmount();
    error PreviewZeroGross();
    error PreviewNetExceedsGross();
    error PreviewNetExceedsReference();
    error PreviewReverted();
    error NotImplemented();

    constructor(IERC20 asset_, address router_, IUpshiftVaultV2 protocol_, IERC20 lpToken_) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        if (router_ == address(0)) revert ZeroAddress();
        if (address(protocol_) == address(0)) revert ZeroAddress();
        if (address(lpToken_) == address(0)) revert ZeroAddress();
        if (protocol_.asset() != address(asset_)) revert AssetBindingMismatch();
        if (protocol_.lpTokenAddress() != address(lpToken_)) revert LPBindingMismatch();
        _asset = asset_;
        router = router_;
        _protocol = protocol_;
        _lpToken = lpToken_;
    }

    // ---- IStrategyAdapterV2 views ----

    function asset() external view returns (address) {
        return address(_asset);
    }

    function positionToken() external view returns (address) {
        return address(_lpToken);
    }

    function positionShares() external view returns (uint256) {
        return _lpToken.balanceOf(address(this));
    }

    function totalAssets() external view returns (uint256 netAssets) {
        _verifyBindings();
        uint256 direct = _asset.balanceOf(address(this));
        uint256 shares = _lpToken.balanceOf(address(this));
        if (shares == 0) return direct;
        (, uint256 net) = _positionPreview(shares);
        return direct + net;
    }

    function grossAssets() external view returns (uint256 grossAssets_) {
        _verifyBindings();
        uint256 direct = _asset.balanceOf(address(this));
        uint256 shares = _lpToken.balanceOf(address(this));
        if (shares == 0) return direct;
        (uint256 gross,) = _positionPreview(shares);
        return direct + gross;
    }

    function availableLiquidity() external view returns (uint256 netAssets) {
        _verifyBindings();
        uint256 direct = _asset.balanceOf(address(this));
        uint256 shares = _lpToken.balanceOf(address(this));
        if (shares == 0) return direct;
        if (_protocol.withdrawalsPaused()) return direct;
        uint256 limit = _protocol.maxWithdrawalAmount();
        if (limit == 0) return direct;

        // Probe 1: full-position fast path.
        (uint256 fullGross, uint256 fullNet) = _positionPreview(shares);
        if (fullGross <= limit && fullNet <= limit) {
            return direct + fullNet;
        }

        // Probes 2..(MAX_SEARCH_ITERATIONS-1): binary search over [1, shares].
        uint256 lo = 1;
        uint256 hi = shares;
        uint256 bestShares = 0;
        for (uint256 i = 0; i < MAX_SEARCH_ITERATIONS - 2; i++) {
            if (lo > hi) break;
            uint256 mid = lo + (hi - lo + 1) / 2;
            (uint256 g, uint256 n) = _positionPreview(mid);
            if (g <= limit && n <= limit) {
                bestShares = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }

        if (bestShares == 0) return direct;

        // Final verification probe.
        (uint256 finalGross, uint256 finalNet) = _positionPreview(bestShares);
        if (finalGross > limit || finalNet > limit) return direct;
        return direct + finalNet;
    }

    function protocolStatus()
        external
        view
        returns (
            bool depositsEnabled,
            bool withdrawalsEnabled,
            uint256 maxWithdrawalReferenceAmount,
            uint256 rawInstantRedemptionFee
        )
    {
        _verifyBindings();
        bool paused = _protocol.withdrawalsPaused();
        depositsEnabled = !paused;
        withdrawalsEnabled = !paused;
        maxWithdrawalReferenceAmount = _protocol.maxWithdrawalAmount();
        rawInstantRedemptionFee = _protocol.instantRedemptionFee();
    }

    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares, uint256 immediateNetValue)
    {
        _verifyBindings();
        (uint256 expectedShares, uint256 referenceAmount) =
            _protocol.previewDeposit(address(_asset), assets);
        if (expectedShares == 0) revert PreviewZeroShares();
        if (referenceAmount == 0) revert PreviewZeroReferenceAmount();
        (, uint256 net) = _positionPreview(expectedShares);
        if (net > referenceAmount) revert PreviewNetExceedsReference();
        return (expectedShares, net);
    }

    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 grossAssets_, uint256 netAssets)
    {
        _verifyBindings();
        if (shares == 0) return (0, 0);
        return _positionPreview(shares);
    }

    // ---- State-changing stubs (Task 4) ----

    function withdrawLiquid(uint256) external pure returns (uint256) {
        revert NotImplemented();
    }

    function deposit(uint256, uint256) external pure returns (uint256) {
        revert NotImplemented();
    }

    function redeem(uint256, uint256) external pure returns (uint256) {
        revert NotImplemented();
    }

    function redeemAll(uint256) external pure returns (uint256) {
        revert NotImplemented();
    }

    // ---- Internal helpers ----

    function _verifyBindings() internal view {
        if (_protocol.asset() != address(_asset)) revert AssetBindingMismatch();
        if (_protocol.lpTokenAddress() != address(_lpToken)) revert LPBindingMismatch();
    }

    /// @dev Calls protocol.previewRedemption(shares, true) and validates consistency.
    /// For nonzero shares: gross must be > 0 and net must be <= gross.
    /// A reverted preview propagates as PreviewReverted (fail closed).
    function _positionPreview(uint256 shares) internal view returns (uint256 gross, uint256 net) {
        try _protocol.previewRedemption(shares, true) returns (uint256 g, uint256 n) {
            if (g == 0) revert PreviewZeroGross();
            if (n > g) revert PreviewNetExceedsGross();
            return (g, n);
        } catch {
            revert PreviewReverted();
        }
    }
}
