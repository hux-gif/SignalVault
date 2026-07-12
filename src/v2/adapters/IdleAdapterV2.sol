// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IStrategyAdapterV2} from "../interfaces/IStrategyAdapterV2.sol";

/// @notice IdleAdapterV2 holds direct underlying without invoking any external yield protocol.
/// All asset views are equal to the direct underlying balance, including donations.
/// No protocol approval is ever created. All state-changing methods are Router-only and
/// non-reentrant, and reconcile actual output via balance deltas.
contract IdleAdapterV2 is IStrategyAdapterV2, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;
    address public immutable router;

    error ZeroAddress();
    error ZeroAmount();
    error OnlyRouter();
    error InsufficientBalance();
    error InsufficientSharesOut();
    error InsufficientAssetsOut();

    constructor(IERC20 asset_, address router_) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        if (router_ == address(0)) revert ZeroAddress();
        _asset = asset_;
        router = router_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    modifier onlyRouter() {
        if (msg.sender != router) revert OnlyRouter();
        _;
    }

    // ---- IStrategyAdapterV2 views ----

    function positionToken() external view returns (address) {
        return address(_asset);
    }

    function positionShares() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function totalAssets() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function grossAssets() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function availableLiquidity() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function protocolStatus()
        external
        pure
        returns (
            bool depositsEnabled,
            bool withdrawalsEnabled,
            uint256 maxWithdrawalReferenceAmount,
            uint256 rawInstantRedemptionFee
        )
    {
        depositsEnabled = true;
        withdrawalsEnabled = true;
        maxWithdrawalReferenceAmount = type(uint256).max;
        rawInstantRedemptionFee = 0;
    }

    function previewDeposit(uint256 assets)
        external
        pure
        returns (uint256 shares, uint256 immediateNetValue)
    {
        shares = assets;
        immediateNetValue = assets;
    }

    function previewRedeem(uint256 shares)
        external
        pure
        returns (uint256 grossAssets_, uint256 netAssets)
    {
        grossAssets_ = shares;
        netAssets = shares;
    }

    // ---- State-changing methods (Router-only, non-reentrant) ----

    function withdrawLiquid(uint256 assets)
        external
        onlyRouter
        nonReentrant
        returns (uint256 assetsReceived)
    {
        if (assets == 0) revert ZeroAmount();
        if (_asset.balanceOf(address(this)) < assets) revert InsufficientBalance();
        uint256 routerBefore = _asset.balanceOf(msg.sender);
        _asset.safeTransfer(msg.sender, assets);
        assetsReceived = _asset.balanceOf(msg.sender) - routerBefore;
    }

    function deposit(uint256 assets, uint256 minSharesOut)
        external
        onlyRouter
        nonReentrant
        returns (uint256 sharesReceived)
    {
        if (assets == 0) revert ZeroAmount();
        uint256 adapterBefore = _asset.balanceOf(address(this));
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        sharesReceived = _asset.balanceOf(address(this)) - adapterBefore;
        if (sharesReceived < minSharesOut) revert InsufficientSharesOut();
    }

    function redeem(uint256 shares, uint256 minAssetsOut)
        external
        onlyRouter
        nonReentrant
        returns (uint256 assetsReceived)
    {
        if (shares == 0) revert ZeroAmount();
        if (_asset.balanceOf(address(this)) < shares) revert InsufficientBalance();
        uint256 routerBefore = _asset.balanceOf(msg.sender);
        _asset.safeTransfer(msg.sender, shares);
        assetsReceived = _asset.balanceOf(msg.sender) - routerBefore;
        if (assetsReceived < minAssetsOut) revert InsufficientAssetsOut();
    }

    function redeemAll(uint256 minAssetsOut)
        external
        onlyRouter
        nonReentrant
        returns (uint256 assetsReceived)
    {
        uint256 balance = _asset.balanceOf(address(this));
        if (balance == 0) revert ZeroAmount();
        uint256 routerBefore = _asset.balanceOf(msg.sender);
        _asset.safeTransfer(msg.sender, balance);
        assetsReceived = _asset.balanceOf(msg.sender) - routerBefore;
        if (assetsReceived < minAssetsOut) revert InsufficientAssetsOut();
    }
}
