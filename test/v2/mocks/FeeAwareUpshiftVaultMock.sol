// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUpshiftVaultV2} from "../../../src/v2/interfaces/IUpshiftVaultV2.sol";
import {MockLPTokenV2} from "./MockLPTokenV2.sol";

/// @notice Fee-aware Upshift vault mock for V2 adapter tests.
/// Implements the verified protocol-native ABI with configurable fee, pause,
/// reference limit, preview inconsistency, under-transfer, and reentry callback.
/// Preview functions remain `view` to match the live ABI; call counts are
/// asserted via `vm.expectCall` in tests rather than storage counters.
contract FeeAwareUpshiftVaultMock is IUpshiftVaultV2 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;
    MockLPTokenV2 private immutable _lpToken;

    uint256 private _rawFee; // BPS, 0..10_000
    bool private _paused;
    uint256 private _maxWithdrawalReferenceAmount = type(uint256).max;

    bool private _previewInconsistent;

    uint256 private _underTransferAmount; // 0 = disabled, otherwise overrides transfer size

    bool private _reentryArmed;
    address private _reentryTarget;
    bytes private _reentryCallback;

    uint256 public reentryAttemptCount;
    bool public lastReentrySucceeded;

    error AssetMismatch();
    error InvalidFee(uint256 fee);
    error ZeroShares();

    constructor(address asset_, address lpToken_) {
        _asset = IERC20(asset_);
        _lpToken = MockLPTokenV2(lpToken_);
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

    function setPreviewInconsistent(bool inconsistent_) external {
        _previewInconsistent = inconsistent_;
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
        return address(_asset);
    }

    function lpTokenAddress() external view returns (address) {
        return address(_lpToken);
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
        if (assetIn != address(_asset)) revert AssetMismatch();
        if (_previewInconsistent) {
            // Use block.timestamp so tests can force divergence via vm.warp.
            shares = amountIn + block.timestamp;
        } else {
            shares = amountIn;
        }
        amountInReferenceTokens = amountIn;
    }

    function previewRedemption(uint256 shares, bool isInstant)
        external
        view
        returns (uint256 assetsAmount, uint256 assetsAfterFee)
    {
        // gross = shares (1:1 mock exchange rate)
        assetsAmount = shares;
        if (isInstant) {
            // net = gross - floor(gross * fee / 10_000)
            assetsAfterFee = assetsAmount - assetsAmount.mulDiv(_rawFee, 10_000);
        } else {
            assetsAfterFee = assetsAmount;
        }
    }

    // ---- State-changing functions ----

    function deposit(address assetIn, uint256 amountIn, address receiverAddr)
        external
        returns (uint256 shares)
    {
        if (assetIn != address(_asset)) revert AssetMismatch();
        shares = amountIn;
        _asset.safeTransferFrom(msg.sender, address(this), amountIn);
        _lpToken.mint(receiverAddr, shares);
    }

    function instantRedeem(uint256 shares, address receiverAddr) external {
        if (shares == 0) revert ZeroShares();
        // Burn LP from caller (no protocol return value to trust).
        _lpToken.burn(msg.sender, shares);

        // Compute transfer amount: under-transfer override, otherwise net of fee.
        uint256 transferAmount;
        if (_underTransferAmount > 0) {
            transferAmount = _underTransferAmount;
        } else {
            transferAmount = shares - shares.mulDiv(_rawFee, 10_000);
        }

        _asset.safeTransfer(receiverAddr, transferAmount);

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
}
