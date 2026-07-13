// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IStrategyAdapterV2} from "../interfaces/IStrategyAdapterV2.sol";
import {IStrategyRecoveryV2} from "../interfaces/IStrategyRecoveryV2.sol";
import {IUpshiftVaultV2} from "../interfaces/IUpshiftVaultV2.sol";

/// @notice UpshiftAdapterV2 holds underlying and Upshift LP shares and provides read-only
/// valuation views, composed deposit preview, protocol status, and a conservative bounded
/// liquidity search and measured Router-only execution.
contract UpshiftAdapterV2 is IStrategyAdapterV2, IStrategyRecoveryV2, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;
    address public immutable router;
    IUpshiftVaultV2 private immutable _protocol;
    IERC20 private immutable _lpToken;

    bool public positionRecovered;

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
    error PreviewZeroNet();
    error PreviewNetExceedsGross();
    error PreviewNetExceedsReference();
    error PreviewReverted();
    error OnlyRouter();
    error ZeroAmount();
    error InsufficientBalance();
    error InsufficientSharesOut();
    error InsufficientAssetsOut();
    error ProtocolPaused();
    error WithdrawalLimitExceeded();
    error ZeroAssetsReceived();
    error AssetDeltaMismatch();
    error ZeroSharesReceived();
    error ShareDeltaMismatch();
    error RouterDeltaMismatch();
    error ResidualUnderlying();
    error ResidualShares();
    error AssetAllowanceNotCleared();
    error LPAllowanceCreated();
    error ZeroPosition();
    error PositionRecovered();
    error RecoveryDeltaMismatch();

    event LiquidWithdrawn(uint256 requestedAssets, uint256 actualAssetsReceived);
    event Deposited(
        uint256 requestedAssets,
        uint256 previewedShares,
        uint256 actualAssetsReceived,
        uint256 actualSharesReceived,
        uint256 rawInstantRedemptionFee
    );
    event Redeemed(
        uint256 requestedShares,
        uint256 previewedNetAssets,
        uint256 actualSharesBurned,
        uint256 actualAssetsReceived,
        uint256 rawInstantRedemptionFee
    );
    event RedeemedAll(
        uint256 requestedShares,
        uint256 previewedNetAssets,
        uint256 actualSharesBurned,
        uint256 actualAssetsReceived,
        uint256 rawInstantRedemptionFee
    );
    event EmergencyPositionRecovered(address indexed token, uint256 amount, address receiver);

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

    modifier onlyRouter() {
        if (msg.sender != router) revert OnlyRouter();
        _;
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
        _requireOperational();
        _verifyBindings();
        uint256 direct = _asset.balanceOf(address(this));
        uint256 shares = _lpToken.balanceOf(address(this));
        if (shares == 0) return direct;
        (, uint256 net) = _positionPreview(shares);
        return direct + net;
    }

    function grossAssets() external view returns (uint256 grossAssets_) {
        _requireOperational();
        _verifyBindings();
        uint256 direct = _asset.balanceOf(address(this));
        uint256 shares = _lpToken.balanceOf(address(this));
        if (shares == 0) return direct;
        (uint256 gross,) = _positionPreview(shares);
        return direct + gross;
    }

    function availableLiquidity() external view returns (uint256 netAssets) {
        _requireOperational();
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
        _requireOperational();
        bool bindingsMatch = _bindingsMatch();
        bool paused = _protocol.withdrawalsPaused();
        depositsEnabled = bindingsMatch && !paused;
        withdrawalsEnabled = bindingsMatch && !paused;
        maxWithdrawalReferenceAmount = _protocol.maxWithdrawalAmount();
        rawInstantRedemptionFee = _protocol.instantRedemptionFee();
    }

    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares, uint256 immediateNetValue)
    {
        return _previewDeposit(assets);
    }

    function _previewDeposit(uint256 assets)
        internal
        view
        returns (uint256 shares, uint256 immediateNetValue)
    {
        _requireOperational();
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
        _requireOperational();
        _verifyBindings();
        if (shares == 0) return (0, 0);
        return _positionPreview(shares);
    }

    // ---- State-changing execution ----

    function withdrawLiquid(uint256 assets)
        external
        onlyRouter
        nonReentrant
        returns (uint256 assetsReceived)
    {
        if (!positionRecovered) _verifyBindings();
        if (assets == 0) revert ZeroAmount();
        uint256 adapterBefore = _asset.balanceOf(address(this));
        if (adapterBefore < assets) revert InsufficientBalance();

        uint256 routerBefore = _asset.balanceOf(msg.sender);
        _asset.safeTransfer(msg.sender, assets);
        uint256 adapterAfter = _asset.balanceOf(address(this));
        uint256 routerAfter = _asset.balanceOf(msg.sender);
        if (adapterAfter > adapterBefore || adapterBefore - adapterAfter != assets) {
            revert AssetDeltaMismatch();
        }
        if (routerAfter < routerBefore || routerAfter - routerBefore != assets) {
            revert RouterDeltaMismatch();
        }
        assetsReceived = assets;
        _assertNoAllowances();
        emit LiquidWithdrawn(assets, assetsReceived);
    }

    function deposit(uint256 assets, uint256 minSharesOut)
        external
        onlyRouter
        nonReentrant
        returns (uint256 sharesReceived)
    {
        _requireOperational();
        _verifyBindings();
        if (assets == 0) revert ZeroAmount();
        if (_protocol.withdrawalsPaused()) revert ProtocolPaused();

        uint256 adapterAssetsBefore = _asset.balanceOf(address(this));
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        uint256 adapterAssetsAfter = _asset.balanceOf(address(this));
        if (adapterAssetsAfter <= adapterAssetsBefore) revert ZeroAssetsReceived();
        uint256 actualAssetsReceived = adapterAssetsAfter - adapterAssetsBefore;
        if (actualAssetsReceived != assets) revert AssetDeltaMismatch();

        (uint256 previewedShares,) = _previewDeposit(actualAssetsReceived);
        uint256 rawFee = _protocol.instantRedemptionFee();
        uint256 lpBefore = _lpToken.balanceOf(address(this));
        _asset.forceApprove(address(_protocol), actualAssetsReceived);
        _protocol.deposit(address(_asset), actualAssetsReceived, address(this));
        _asset.forceApprove(address(_protocol), 0);
        _verifyBindings();
        uint256 lpAfter = _lpToken.balanceOf(address(this));
        if (lpAfter <= lpBefore) revert ZeroSharesReceived();
        sharesReceived = lpAfter - lpBefore;
        if (sharesReceived < minSharesOut) revert InsufficientSharesOut();
        _assertNoAllowances();

        emit Deposited(assets, previewedShares, actualAssetsReceived, sharesReceived, rawFee);
    }

    function redeem(uint256 shares, uint256 minAssetsOut)
        external
        onlyRouter
        nonReentrant
        returns (uint256 assetsReceived)
    {
        _requireOperational();
        (uint256 previewedNet, uint256 rawFee) = _prepareRedemption(shares);
        uint256 directBefore = _asset.balanceOf(address(this));
        uint256 lpBefore = _lpToken.balanceOf(address(this));

        _protocol.instantRedeem(shares, address(this));
        _verifyBindings();

        uint256 lpAfter = _lpToken.balanceOf(address(this));
        if (lpAfter > lpBefore || lpBefore - lpAfter != shares) revert ShareDeltaMismatch();
        uint256 adapterAfter = _asset.balanceOf(address(this));
        if (adapterAfter <= directBefore) revert ZeroAssetsReceived();
        uint256 protocolAssetsReceived = adapterAfter - directBefore;

        uint256 routerBefore = _asset.balanceOf(msg.sender);
        _asset.safeTransfer(msg.sender, protocolAssetsReceived);
        assetsReceived = _asset.balanceOf(msg.sender) - routerBefore;
        if (assetsReceived != protocolAssetsReceived) revert RouterDeltaMismatch();
        if (assetsReceived < minAssetsOut) revert InsufficientAssetsOut();
        if (_asset.balanceOf(address(this)) != directBefore) revert ResidualUnderlying();
        _assertNoAllowances();

        emit Redeemed(shares, previewedNet, shares, assetsReceived, rawFee);
    }

    function redeemAll(uint256 minAssetsOut)
        external
        onlyRouter
        nonReentrant
        returns (uint256 assetsReceived)
    {
        _requireOperational();
        _verifyBindings();
        uint256 shares = _lpToken.balanceOf(address(this));
        uint256 directBefore = _asset.balanceOf(address(this));
        if (shares == 0 && directBefore == 0) revert ZeroAmount();

        uint256 previewedNet;
        uint256 rawFee;
        uint256 sharesBurned;
        if (shares > 0) {
            (previewedNet, rawFee) = _prepareRedemption(shares);
            _protocol.instantRedeem(shares, address(this));
            _verifyBindings();
            uint256 lpAfter = _lpToken.balanceOf(address(this));
            if (lpAfter > shares || shares - lpAfter != shares) revert ShareDeltaMismatch();
            sharesBurned = shares;
        }

        uint256 assetsToSweep = _asset.balanceOf(address(this));
        if (assetsToSweep == 0) revert ZeroAssetsReceived();
        uint256 routerBefore = _asset.balanceOf(msg.sender);
        _asset.safeTransfer(msg.sender, assetsToSweep);
        assetsReceived = _asset.balanceOf(msg.sender) - routerBefore;
        if (assetsReceived != assetsToSweep) revert RouterDeltaMismatch();
        if (assetsReceived < minAssetsOut) revert InsufficientAssetsOut();
        if (_asset.balanceOf(address(this)) != 0) revert ResidualUnderlying();
        if (_lpToken.balanceOf(address(this)) != 0) revert ResidualShares();
        _assertNoAllowances();

        emit RedeemedAll(shares, previewedNet, sharesBurned, assetsReceived, rawFee);
    }

    function recoverPosition(address receiver)
        external
        onlyRouter
        nonReentrant
        returns (uint256 sharesRecovered)
    {
        if (positionRecovered) revert PositionRecovered();
        if (receiver == address(0)) revert ZeroAddress();
        uint256 adapterBefore = _lpToken.balanceOf(address(this));
        if (adapterBefore == 0) revert ZeroPosition();
        uint256 receiverBefore = _lpToken.balanceOf(receiver);

        _lpToken.safeTransfer(receiver, adapterBefore);

        uint256 adapterAfter = _lpToken.balanceOf(address(this));
        uint256 receiverAfter = _lpToken.balanceOf(receiver);
        if (
            adapterAfter > adapterBefore || adapterBefore - adapterAfter != adapterBefore
                || receiverAfter < receiverBefore || receiverAfter - receiverBefore != adapterBefore
        ) revert RecoveryDeltaMismatch();
        sharesRecovered = adapterBefore;
        positionRecovered = true;
        _assertNoAllowances();
        emit EmergencyPositionRecovered(address(_lpToken), sharesRecovered, receiver);
    }

    // ---- Internal helpers ----

    function _verifyBindings() internal view {
        if (_protocol.asset() != address(_asset)) revert AssetBindingMismatch();
        if (_protocol.lpTokenAddress() != address(_lpToken)) revert LPBindingMismatch();
    }

    function _bindingsMatch() internal view returns (bool) {
        try _protocol.asset() returns (address reportedAsset) {
            if (reportedAsset != address(_asset)) return false;
        } catch {
            return false;
        }
        try _protocol.lpTokenAddress() returns (address reportedLPToken) {
            return reportedLPToken == address(_lpToken);
        } catch {
            return false;
        }
    }

    function _requireOperational() internal view {
        if (positionRecovered) revert PositionRecovered();
    }

    function _prepareRedemption(uint256 shares)
        internal
        view
        returns (uint256 previewedNet, uint256 rawFee)
    {
        _verifyBindings();
        if (shares == 0) revert ZeroAmount();
        if (_lpToken.balanceOf(address(this)) < shares) revert InsufficientBalance();
        if (_protocol.withdrawalsPaused()) revert ProtocolPaused();
        (uint256 gross, uint256 net) = _positionPreview(shares);
        uint256 limit = _protocol.maxWithdrawalAmount();
        if (gross > limit || net > limit) revert WithdrawalLimitExceeded();
        return (net, _protocol.instantRedemptionFee());
    }

    function _assertNoAllowances() internal view {
        if (_asset.allowance(address(this), address(_protocol)) != 0) {
            revert AssetAllowanceNotCleared();
        }
        if (_lpToken.allowance(address(this), address(_protocol)) != 0) {
            revert LPAllowanceCreated();
        }
    }

    /// @dev Calls protocol.previewRedemption(shares, true) and validates consistency.
    /// For nonzero shares: gross must be > 0 and net must be <= gross.
    /// A reverted preview propagates as PreviewReverted (fail closed).
    function _positionPreview(uint256 shares) internal view returns (uint256 gross, uint256 net) {
        try _protocol.previewRedemption(shares, true) returns (uint256 g, uint256 n) {
            if (g == 0) revert PreviewZeroGross();
            if (n == 0) revert PreviewZeroNet();
            if (n > g) revert PreviewNetExceedsGross();
            return (g, n);
        } catch {
            revert PreviewReverted();
        }
    }
}
