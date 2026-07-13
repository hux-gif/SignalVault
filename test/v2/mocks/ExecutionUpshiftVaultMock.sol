// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IUpshiftVaultV2} from "../../../src/v2/interfaces/IUpshiftVaultV2.sol";
import {MockLPTokenV2} from "./MockLPTokenV2.sol";

/// @notice Task 4 execution mock with independently configurable protocol returns,
/// token deltas, partial allowance consumption, reverts, and propagating callbacks.
contract ExecutionUpshiftVaultMock is IUpshiftVaultV2 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 private immutable _actualAsset;
    MockLPTokenV2 private immutable _actualLPToken;
    address private _reportedAsset;
    address private _reportedLPToken;

    uint256 private _fee;
    bool private _paused;
    uint256 private _limit = type(uint256).max;
    bool private _previewReverts;
    bool private _depositReverts;
    bool private _redeemReverts;
    bool private _bindingGettersRevert;
    bool private _changeBindingOnDeposit;
    bool private _changeBindingOnRedeem;

    bool private _depositPullOverrideEnabled;
    uint256 private _depositPullOverride;
    bool private _depositMintOverrideEnabled;
    uint256 private _depositMintOverride;
    bool private _depositReturnOverrideEnabled;
    uint256 private _depositReturnOverride;
    bool private _redeemBurnOverrideEnabled;
    uint256 private _redeemBurnOverride;
    bool private _redeemTransferOverrideEnabled;
    uint256 private _redeemTransferOverride;

    address private _depositCallbackTarget;
    bytes private _depositCallback;
    address private _redeemCallbackTarget;
    bytes private _redeemCallback;

    uint256 public depositCallCount;
    uint256 public redeemCallCount;
    uint256 public lastObservedDepositAllowance;
    uint256 public lastRequestedDepositAmount;

    error ConfiguredRevert();
    error CallbackFailed();

    constructor(address asset_, address lpToken_) {
        _actualAsset = IERC20(asset_);
        _actualLPToken = MockLPTokenV2(lpToken_);
        _reportedAsset = asset_;
        _reportedLPToken = lpToken_;
    }

    function setFee(uint256 fee_) external {
        _fee = fee_;
    }

    function setPaused(bool paused_) external {
        _paused = paused_;
    }

    function setLimit(uint256 limit_) external {
        _limit = limit_;
    }

    function setReportedAsset(address asset_) external {
        _reportedAsset = asset_;
    }

    function setReportedLPToken(address lpToken_) external {
        _reportedLPToken = lpToken_;
    }

    function setPreviewReverts(bool enabled) external {
        _previewReverts = enabled;
    }

    function setDepositReverts(bool enabled) external {
        _depositReverts = enabled;
    }

    function setRedeemReverts(bool enabled) external {
        _redeemReverts = enabled;
    }

    function setBindingGettersRevert(bool enabled) external {
        _bindingGettersRevert = enabled;
    }

    function setChangeBindingOnDeposit(bool enabled) external {
        _changeBindingOnDeposit = enabled;
    }

    function setChangeBindingOnRedeem(bool enabled) external {
        _changeBindingOnRedeem = enabled;
    }

    function setDepositPullOverride(bool enabled, uint256 amount) external {
        _depositPullOverrideEnabled = enabled;
        _depositPullOverride = amount;
    }

    function setDepositMintOverride(bool enabled, uint256 shares) external {
        _depositMintOverrideEnabled = enabled;
        _depositMintOverride = shares;
    }

    function setDepositReturnOverride(bool enabled, uint256 shares) external {
        _depositReturnOverrideEnabled = enabled;
        _depositReturnOverride = shares;
    }

    function setRedeemBurnOverride(bool enabled, uint256 shares) external {
        _redeemBurnOverrideEnabled = enabled;
        _redeemBurnOverride = shares;
    }

    function setRedeemTransferOverride(bool enabled, uint256 assets) external {
        _redeemTransferOverrideEnabled = enabled;
        _redeemTransferOverride = assets;
    }

    function armDepositCallback(address target, bytes calldata data) external {
        _depositCallbackTarget = target;
        _depositCallback = data;
    }

    function armRedeemCallback(address target, bytes calldata data) external {
        _redeemCallbackTarget = target;
        _redeemCallback = data;
    }

    function asset() external view returns (address) {
        if (_bindingGettersRevert) revert ConfiguredRevert();
        return _reportedAsset;
    }

    function lpTokenAddress() external view returns (address) {
        if (_bindingGettersRevert) revert ConfiguredRevert();
        return _reportedLPToken;
    }

    function withdrawalsPaused() external view returns (bool) {
        return _paused;
    }

    function maxWithdrawalAmount() external view returns (uint256) {
        return _paused ? 0 : _limit;
    }

    function instantRedemptionFee() external view returns (uint256) {
        return _fee;
    }

    function previewDeposit(address assetIn, uint256 amountIn)
        external
        view
        returns (uint256 shares, uint256 referenceAmount)
    {
        if (_previewReverts) revert ConfiguredRevert();
        require(assetIn == address(_actualAsset));
        return (amountIn, amountIn);
    }

    function previewRedemption(uint256 shares, bool isInstant)
        external
        view
        returns (uint256 gross, uint256 net)
    {
        if (_previewReverts) revert ConfiguredRevert();
        gross = shares;
        net = isInstant ? gross - gross.mulDiv(_fee, 10_000) : gross;
    }

    function deposit(address assetIn, uint256 amountIn, address receiver)
        external
        returns (uint256 shares)
    {
        depositCallCount++;
        if (_depositReverts) revert ConfiguredRevert();
        require(assetIn == address(_actualAsset));
        _runCallback(_depositCallbackTarget, _depositCallback);
        lastRequestedDepositAmount = amountIn;
        lastObservedDepositAllowance = _actualAsset.allowance(msg.sender, address(this));
        uint256 pulled = _depositPullOverrideEnabled ? _depositPullOverride : amountIn;
        _actualAsset.safeTransferFrom(msg.sender, address(this), pulled);
        uint256 minted = _depositMintOverrideEnabled ? _depositMintOverride : pulled;
        if (minted > 0) _actualLPToken.mint(receiver, minted);
        if (_changeBindingOnDeposit) _reportedAsset = address(0xDEAD);
        return _depositReturnOverrideEnabled ? _depositReturnOverride : minted;
    }

    function instantRedeem(uint256 shares, address receiver) external {
        redeemCallCount++;
        if (_redeemReverts) revert ConfiguredRevert();
        require(!_paused);
        _runCallback(_redeemCallbackTarget, _redeemCallback);
        uint256 burned = _redeemBurnOverrideEnabled ? _redeemBurnOverride : shares;
        if (burned > 0) _actualLPToken.burn(msg.sender, burned);
        uint256 net = shares - shares.mulDiv(_fee, 10_000);
        uint256 transferred = _redeemTransferOverrideEnabled ? _redeemTransferOverride : net;
        if (transferred > 0) _actualAsset.safeTransfer(receiver, transferred);
        if (_changeBindingOnRedeem) _reportedLPToken = address(0xDEAD);
    }

    function _runCallback(address target, bytes storage data) private {
        if (target == address(0)) return;
        bytes memory callback = data;
        (bool ok, bytes memory returndata) = target.call(callback);
        if (!ok) {
            if (returndata.length == 0) revert CallbackFailed();
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }
    }
}
