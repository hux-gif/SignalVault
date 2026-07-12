// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUpshiftVaultV2} from "../../../src/v2/interfaces/IUpshiftVaultV2.sol";
import {MockLPTokenV2} from "./MockLPTokenV2.sol";

/// @notice Fee-aware Upshift vault mock for V2 adapter tests.
/// Implements the verified protocol-native ABI with configurable bindings,
/// conversion rates, deterministic previews, withdrawal limits, under-transfer,
/// and reentry callbacks.
/// Preview functions remain `view` to match the live ABI; call counts are
/// asserted via `vm.expectCall` in tests rather than storage counters.
contract FeeAwareUpshiftVaultMock is IUpshiftVaultV2 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IERC20 private immutable _actualAsset;
    MockLPTokenV2 private immutable _actualLPToken;
    address private _reportedAsset;
    address private _reportedLPToken;

    uint256 private _shareNumerator = 1;
    uint256 private _shareDenominator = 1;
    uint256 private _referenceNumerator = 1;
    uint256 private _referenceDenominator = 1;

    struct DepositPreviewOverride {
        bool enabled;
        uint256 shares;
        uint256 referenceAmount;
    }

    struct RedemptionPreviewOverride {
        bool enabled;
        uint256 gross;
        uint256 net;
        uint256 internalReference;
    }

    mapping(uint256 amountIn => DepositPreviewOverride value) private _depositPreviewOverrides;
    mapping(uint256 shares => RedemptionPreviewOverride value) private _redemptionPreviewOverrides;

    enum WithdrawalLimitMode {
        Gross,
        Net,
        InternalReference
    }

    WithdrawalLimitMode public withdrawalLimitMode;

    uint256 private _rawFee; // BPS, 0..10_000
    bool private _paused;
    uint256 private _maxWithdrawalReferenceAmount = type(uint256).max;

    uint256 private _underTransferAmount; // 0 = disabled, otherwise overrides transfer size

    bool private _reentryArmed;
    address private _reentryTarget;
    bytes private _reentryCallback;

    uint256 public reentryAttemptCount;
    bool public lastReentrySucceeded;

    error AssetMismatch();
    error InvalidDepositRate();
    error InvalidFee(uint256 fee);
    error WithdrawalsPaused();
    error WithdrawalLimitExceeded(uint256 measuredAmount, uint256 limit);
    error ZeroShares();

    constructor(address asset_, address lpToken_) {
        _actualAsset = IERC20(asset_);
        _actualLPToken = MockLPTokenV2(lpToken_);
        _reportedAsset = asset_;
        _reportedLPToken = lpToken_;
    }

    // ---- Setters ----

    function setInstantFee(uint256 fee_) external {
        if (fee_ > 10_000) revert InvalidFee(fee_);
        _rawFee = fee_;
    }

    function setPaused(bool paused_) external {
        _paused = paused_;
    }

    function setMaxWithdrawalReferenceAmount(uint256 amount_) external {
        _maxWithdrawalReferenceAmount = amount_;
    }

    function setReportedAsset(address reportedAsset_) external {
        _reportedAsset = reportedAsset_;
    }

    function setReportedLPToken(address reportedLPToken_) external {
        _reportedLPToken = reportedLPToken_;
    }

    function setDepositRates(
        uint256 shareNumerator_,
        uint256 shareDenominator_,
        uint256 referenceNumerator_,
        uint256 referenceDenominator_
    ) external {
        if (shareDenominator_ == 0 || referenceDenominator_ == 0) {
            revert InvalidDepositRate();
        }
        _shareNumerator = shareNumerator_;
        _shareDenominator = shareDenominator_;
        _referenceNumerator = referenceNumerator_;
        _referenceDenominator = referenceDenominator_;
    }

    function setDepositPreviewOverride(
        uint256 amountIn,
        bool enabled,
        uint256 shares,
        uint256 referenceAmount
    ) external {
        _depositPreviewOverrides[amountIn] =
            DepositPreviewOverride(enabled, shares, referenceAmount);
    }

    function setRedemptionPreviewOverride(
        uint256 shares,
        bool enabled,
        uint256 gross,
        uint256 net,
        uint256 internalReference
    ) external {
        _redemptionPreviewOverrides[shares] =
            RedemptionPreviewOverride(enabled, gross, net, internalReference);
    }

    function setWithdrawalLimitMode(WithdrawalLimitMode mode) external {
        withdrawalLimitMode = mode;
    }

    function setUnderTransferAmount(uint256 amount_) external {
        _underTransferAmount = amount_;
    }

    function armReentry(address target_, bytes calldata callback_) external {
        _reentryArmed = true;
        _reentryTarget = target_;
        _reentryCallback = callback_;
        reentryAttemptCount = 0;
        lastReentrySucceeded = false;
    }

    // ---- IUpshiftVaultV2 view functions ----

    function asset() external view returns (address) {
        return _reportedAsset;
    }

    function lpTokenAddress() external view returns (address) {
        return _reportedLPToken;
    }

    function instantRedemptionFee() external view returns (uint256) {
        return _rawFee;
    }

    function withdrawalsPaused() external view returns (bool) {
        return _paused;
    }

    function maxWithdrawalAmount() external view returns (uint256) {
        return _paused ? 0 : _maxWithdrawalReferenceAmount;
    }

    // ---- Preview functions (view, matching live ABI) ----

    function previewDeposit(address assetIn, uint256 amountIn)
        external
        view
        returns (uint256 shares, uint256 amountInReferenceTokens)
    {
        if (assetIn != address(_actualAsset)) revert AssetMismatch();
        DepositPreviewOverride memory previewOverride = _depositPreviewOverrides[amountIn];
        if (previewOverride.enabled) {
            return (previewOverride.shares, previewOverride.referenceAmount);
        }
        shares = Math.mulDiv(amountIn, _shareNumerator, _shareDenominator);
        amountInReferenceTokens = Math.mulDiv(amountIn, _referenceNumerator, _referenceDenominator);
    }

    function previewRedemption(uint256 shares, bool isInstant)
        external
        view
        returns (uint256 assetsAmount, uint256 assetsAfterFee)
    {
        (assetsAmount, assetsAfterFee,) = _redemptionQuote(shares, isInstant);
    }

    // ---- State-changing functions ----

    function deposit(address assetIn, uint256 amountIn, address receiverAddr)
        external
        returns (uint256 shares)
    {
        if (assetIn != address(_actualAsset)) revert AssetMismatch();
        shares = Math.mulDiv(amountIn, _shareNumerator, _shareDenominator);
        _actualAsset.safeTransferFrom(msg.sender, address(this), amountIn);
        _actualLPToken.mint(receiverAddr, shares);
    }

    function instantRedeem(uint256 shares, address receiverAddr) external {
        if (_paused) revert WithdrawalsPaused();
        if (shares == 0) revert ZeroShares();
        (uint256 gross, uint256 net, uint256 internalReference) = _redemptionQuote(shares, true);
        uint256 measuredAmount;
        if (withdrawalLimitMode == WithdrawalLimitMode.Gross) {
            measuredAmount = gross;
        } else if (withdrawalLimitMode == WithdrawalLimitMode.Net) {
            measuredAmount = net;
        } else {
            measuredAmount = internalReference;
        }
        if (measuredAmount > _maxWithdrawalReferenceAmount) {
            revert WithdrawalLimitExceeded(measuredAmount, _maxWithdrawalReferenceAmount);
        }
        // Burn LP from caller (no protocol return value to trust).
        _actualLPToken.burn(msg.sender, shares);

        // Compute transfer amount: under-transfer override, otherwise net of fee.
        uint256 transferAmount;
        if (_underTransferAmount > 0) {
            transferAmount = _underTransferAmount;
        } else {
            transferAmount = net;
        }

        _actualAsset.safeTransfer(receiverAddr, transferAmount);

        // Best-effort reentry callback; failures are swallowed so the outer call
        // does not revert purely due to the callback. Task 5 introduces a
        // dedicated ReentrantUpshiftVaultMock that propagates reverts for
        // adapter reentrancy-guard assertions.
        if (_reentryArmed) {
            _reentryArmed = false;
            address target = _reentryTarget;
            bytes memory callback = _reentryCallback;
            (bool ok,) = target.call(callback);
            reentryAttemptCount++;
            lastReentrySucceeded = ok;
        }
    }

    function _redemptionQuote(uint256 shares, bool isInstant)
        private
        view
        returns (uint256 gross, uint256 net, uint256 internalReference)
    {
        RedemptionPreviewOverride memory previewOverride = _redemptionPreviewOverrides[shares];
        if (previewOverride.enabled) {
            return (previewOverride.gross, previewOverride.net, previewOverride.internalReference);
        }
        gross = shares;
        net = isInstant ? gross - gross.mulDiv(_rawFee, 10_000) : gross;
        internalReference = gross;
    }
}
