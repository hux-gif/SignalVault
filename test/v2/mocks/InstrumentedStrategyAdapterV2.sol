// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStrategyAdapterV2} from "../../../src/v2/interfaces/IStrategyAdapterV2.sol";
import {IStrategyRecoveryV2} from "../../../src/v2/interfaces/IStrategyRecoveryV2.sol";

/// @notice Deterministic Router-bound adapter used only at the StrategyRouterV2 test seam.
contract InstrumentedStrategyAdapterV2 is IStrategyAdapterV2, IStrategyRecoveryV2 {
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;
    address public immutable router;
    address public immutable override positionToken;

    uint256 private _positionNetAssets;
    uint256 private _positionGrossAssets;
    uint256 private _positionLiquidity;
    uint256 private _positionShares;
    bool private _useExactReports;
    uint256 private _exactNetAssets;
    uint256 private _exactGrossAssets;
    uint256 private _exactLiquidity;

    bool private _depositsEnabled = true;
    bool private _withdrawalsEnabled = true;
    bool private _totalAssetsReverts;
    bool private _grossAssetsReverts;
    bool private _availableLiquidityReverts;
    bool private _statusReverts;
    bool private _previewReverts;

    struct DepositPreviewV2 {
        bool configured;
        uint256 shares;
        uint256 immediateNet;
    }

    struct RedeemPreviewV2 {
        bool configured;
        uint256 gross;
        uint256 net;
    }

    mapping(uint256 assets => DepositPreviewV2 preview) private _depositPreviews;
    mapping(uint256 shares => RedeemPreviewV2 preview) private _redeemPreviews;

    uint256 public depositCallCount;
    uint256 public withdrawLiquidCallCount;
    uint256 public redeemCallCount;
    uint256 public redeemAllCallCount;
    uint256 public stateChangingCallCount;
    uint256 public lastDepositAssets;
    uint256 public lastDepositMinSharesOut;
    uint256 public lastWithdrawLiquidAssets;
    uint256 public lastRedeemShares;
    uint256 public lastRedeemMinAssetsOut;

    uint256 public depositRouterDebit;
    uint256 public depositAdapterCredit;
    uint256 public depositSharesMinted;
    uint256 public depositReturnedShares;
    uint256 public withdrawalAdapterDebit;
    uint256 public withdrawalRouterCredit;
    uint256 public withdrawalReturnedAssets;
    uint256 public lastObservedAllowance;

    bool private _depositExecutionConfigured;
    bool private _withdrawalExecutionConfigured;
    bool private _redeemExecutionConfigured;
    bool private _ignoreMinimumChecks;
    bool private _depositPositionNetConfigured;
    uint256 private _depositPositionNetAdded;
    bool private _depositReverts;
    bool private _redeemReverts;
    bool private _requireLiquidWithdrawBeforeRedeem;
    uint256 public redeemSharesBurned;
    uint256 public redeemRouterCredit;
    uint256 public redeemReturnedAssets;
    bool private _redeemAllExecutionConfigured;
    uint256 public redeemAllSharesRemaining;
    uint256 public redeemAllUnderlyingRemaining;
    uint256 public redeemAllRouterCredit;
    uint256 public redeemAllReturnedAssets;
    address private _requiredPriorAdapter;
    address private _depositCallbackTarget;
    bytes private _depositCallbackData;
    address private _redeemCallbackTarget;
    bytes private _redeemCallbackData;

    bool private _recoveryExecutionConfigured;
    uint256 public recoveryAdapterDebit;
    uint256 public recoveryReceiverCredit;
    uint256 public recoveryReturnedShares;
    uint256 public recoverPositionCallCount;
    address public lastRecoveryReceiver;
    address private _recoveryCallbackTarget;
    bytes private _recoveryCallbackData;

    error ForcedViewRevert();
    error PreviewReverted();
    error ForcedExecutionRevert();
    error InsufficientSharesOut();
    error InsufficientAssetsOut();
    error RequiredCallOrder();

    constructor(IERC20 asset_, address router_, address positionToken_) {
        _asset = asset_;
        router = router_;
        positionToken = positionToken_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function setPositionValues(uint256 net, uint256 gross, uint256 liquidity, uint256 shares)
        external
    {
        _useExactReports = false;
        _positionNetAssets = net;
        _positionGrossAssets = gross;
        _positionLiquidity = liquidity;
        _positionShares = shares;
    }

    function setExactReportedValues(uint256 net, uint256 gross, uint256 liquidity) external {
        _useExactReports = true;
        _exactNetAssets = net;
        _exactGrossAssets = gross;
        _exactLiquidity = liquidity;
    }

    function setStatus(bool deposits, bool withdrawals) external {
        _depositsEnabled = deposits;
        _withdrawalsEnabled = withdrawals;
    }

    function setViewReverts(bool netReverts, bool grossReverts, bool liquidityReverts) external {
        _totalAssetsReverts = netReverts;
        _grossAssetsReverts = grossReverts;
        _availableLiquidityReverts = liquidityReverts;
    }

    function setStatusReverts(bool value) external {
        _statusReverts = value;
    }

    function setPreviewReverts(bool value) external {
        _previewReverts = value;
    }

    function setDepositPreview(uint256 assets, uint256 shares, uint256 immediateNet) external {
        _depositPreviews[assets] =
            DepositPreviewV2({configured: true, shares: shares, immediateNet: immediateNet});
    }

    function setRedeemPreview(uint256 shares, uint256 gross, uint256 net) external {
        _redeemPreviews[shares] = RedeemPreviewV2({configured: true, gross: gross, net: net});
    }

    function setDepositExecution(
        uint256 routerDebit,
        uint256 adapterCredit,
        uint256 sharesMinted,
        uint256 returnedShares
    ) external {
        _depositExecutionConfigured = true;
        depositRouterDebit = routerDebit;
        depositAdapterCredit = adapterCredit;
        depositSharesMinted = sharesMinted;
        depositReturnedShares = returnedShares;
    }

    function setIgnoreMinimumChecks(bool value) external {
        _ignoreMinimumChecks = value;
    }

    function setDepositPositionNetAdded(uint256 value) external {
        _depositPositionNetConfigured = true;
        _depositPositionNetAdded = value;
    }

    function setWithdrawalExecution(
        uint256 adapterDebit,
        uint256 routerCredit,
        uint256 returnedAssets
    ) external {
        _withdrawalExecutionConfigured = true;
        withdrawalAdapterDebit = adapterDebit;
        withdrawalRouterCredit = routerCredit;
        withdrawalReturnedAssets = returnedAssets;
    }

    function setRedeemExecution(uint256 sharesBurned, uint256 routerCredit, uint256 returnedAssets)
        external
    {
        _redeemExecutionConfigured = true;
        redeemSharesBurned = sharesBurned;
        redeemRouterCredit = routerCredit;
        redeemReturnedAssets = returnedAssets;
    }

    function setRedeemReverts(bool value) external {
        _redeemReverts = value;
    }

    function setRequireLiquidWithdrawBeforeRedeem(bool value) external {
        _requireLiquidWithdrawBeforeRedeem = value;
    }

    function setRequiredPriorAdapter(address priorAdapter) external {
        _requiredPriorAdapter = priorAdapter;
    }

    function setRedeemAllExecution(
        uint256 sharesRemaining,
        uint256 underlyingRemaining,
        uint256 routerCredit,
        uint256 returnedAssets
    ) external {
        _redeemAllExecutionConfigured = true;
        redeemAllSharesRemaining = sharesRemaining;
        redeemAllUnderlyingRemaining = underlyingRemaining;
        redeemAllRouterCredit = routerCredit;
        redeemAllReturnedAssets = returnedAssets;
    }

    function setDepositReverts(bool value) external {
        _depositReverts = value;
    }

    function setDepositCallback(address target, bytes calldata data) external {
        _depositCallbackTarget = target;
        _depositCallbackData = data;
    }

    function setRedeemCallback(address target, bytes calldata data) external {
        _redeemCallbackTarget = target;
        _redeemCallbackData = data;
    }

    function setRecoveryExecution(
        uint256 adapterDebit,
        uint256 receiverCredit,
        uint256 returnedShares
    ) external {
        _recoveryExecutionConfigured = true;
        recoveryAdapterDebit = adapterDebit;
        recoveryReceiverCredit = receiverCredit;
        recoveryReturnedShares = returnedShares;
    }

    function setRecoveryCallback(address target, bytes calldata data) external {
        _recoveryCallbackTarget = target;
        _recoveryCallbackData = data;
    }

    function positionShares() external view returns (uint256) {
        return _positionShares;
    }

    function totalAssets() external view returns (uint256) {
        if (_totalAssetsReverts) revert ForcedViewRevert();
        if (_useExactReports) return _exactNetAssets;
        return _asset.balanceOf(address(this)) + _positionNetAssets;
    }

    function grossAssets() external view returns (uint256) {
        if (_grossAssetsReverts) revert ForcedViewRevert();
        if (_useExactReports) return _exactGrossAssets;
        return _asset.balanceOf(address(this)) + _positionGrossAssets;
    }

    function availableLiquidity() external view returns (uint256) {
        if (_availableLiquidityReverts) revert ForcedViewRevert();
        if (_useExactReports) return _exactLiquidity;
        return _asset.balanceOf(address(this)) + _positionLiquidity;
    }

    function protocolStatus() external view returns (bool, bool, uint256, uint256) {
        if (_statusReverts) revert ForcedViewRevert();
        return (_depositsEnabled, _withdrawalsEnabled, type(uint256).max, 0);
    }

    /// @dev Preview invocation counts must be asserted with Foundry call expectations/traces:
    /// Router view calls use STATICCALL, so an onchain mock counter cannot be updated truthfully.
    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares, uint256 immediateNetValue)
    {
        if (_previewReverts) revert PreviewReverted();
        DepositPreviewV2 memory preview = _depositPreviews[assets];
        if (preview.configured) return (preview.shares, preview.immediateNet);
        return (assets, assets);
    }

    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 grossAssets_, uint256 netAssets)
    {
        if (_previewReverts) revert PreviewReverted();
        RedeemPreviewV2 memory preview = _redeemPreviews[shares];
        if (preview.configured) return (preview.gross, preview.net);
        return (shares, shares);
    }

    function withdrawLiquid(uint256 assets) external returns (uint256 assetsReceived) {
        withdrawLiquidCallCount++;
        stateChangingCallCount++;
        lastWithdrawLiquidAssets = assets;
        uint256 adapterDebit = _withdrawalExecutionConfigured ? withdrawalAdapterDebit : assets;
        uint256 routerCredit = _withdrawalExecutionConfigured ? withdrawalRouterCredit : assets;
        if (routerCredit != 0) _asset.safeTransfer(router, routerCredit);
        if (adapterDebit > routerCredit) {
            _asset.safeTransfer(address(0xdead), adapterDebit - routerCredit);
        }
        return _withdrawalExecutionConfigured ? withdrawalReturnedAssets : assets;
    }

    function deposit(uint256 assets, uint256 minSharesOut)
        external
        returns (uint256 sharesReceived)
    {
        depositCallCount++;
        stateChangingCallCount++;
        lastDepositAssets = assets;
        lastDepositMinSharesOut = minSharesOut;
        lastObservedAllowance = _asset.allowance(router, address(this));
        if (_depositReverts) revert ForcedExecutionRevert();
        if (_depositCallbackTarget != address(0)) {
            address target = _depositCallbackTarget;
            bytes memory data = _depositCallbackData;
            _depositCallbackTarget = address(0);
            delete _depositCallbackData;
            (bool success, bytes memory returnData) = target.call(data);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }

        uint256 routerDebit = _depositExecutionConfigured ? depositRouterDebit : assets;
        uint256 adapterCredit = _depositExecutionConfigured ? depositAdapterCredit : assets;
        if (routerDebit != 0) _asset.safeTransferFrom(router, address(this), routerDebit);
        if (routerDebit > adapterCredit) {
            _asset.safeTransfer(address(0xdead), routerDebit - adapterCredit);
        }
        uint256 actualShares = _depositExecutionConfigured ? depositSharesMinted : assets;
        uint256 returnedShares = _depositExecutionConfigured ? depositReturnedShares : actualShares;
        if (positionToken != address(_asset)) {
            if (adapterCredit != 0) _asset.safeTransfer(address(0xdead), adapterCredit);
            DepositPreviewV2 memory preview = _depositPreviews[assets];
            uint256 netAdded = _depositPositionNetConfigured
                ? _depositPositionNetAdded
                : preview.configured ? preview.immediateNet : assets;
            _positionShares += actualShares;
            _positionNetAssets += netAdded;
            _positionGrossAssets += assets;
            _positionLiquidity += netAdded;
        }
        if (
            !_ignoreMinimumChecks && positionToken != address(_asset) && actualShares < minSharesOut
        ) {
            revert InsufficientSharesOut();
        }
        return returnedShares;
    }

    function redeem(uint256 shares, uint256 minAssetsOut)
        external
        returns (uint256 assetsReceived)
    {
        redeemCallCount++;
        stateChangingCallCount++;
        lastRedeemShares = shares;
        lastRedeemMinAssetsOut = minAssetsOut;
        if (_redeemReverts) revert ForcedExecutionRevert();
        if (_redeemCallbackTarget != address(0)) {
            address target = _redeemCallbackTarget;
            bytes memory data = _redeemCallbackData;
            _redeemCallbackTarget = address(0);
            delete _redeemCallbackData;
            (bool success, bytes memory returnData) = target.call(data);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
        if (_requireLiquidWithdrawBeforeRedeem && withdrawLiquidCallCount == 0) {
            revert RequiredCallOrder();
        }
        if (
            _requiredPriorAdapter != address(0)
                && InstrumentedStrategyAdapterV2(_requiredPriorAdapter).withdrawLiquidCallCount()
                    == 0
        ) revert RequiredCallOrder();

        uint256 burned = _redeemExecutionConfigured ? redeemSharesBurned : shares;
        uint256 credit;
        RedeemPreviewV2 memory preview = _redeemPreviews[shares];
        if (_redeemExecutionConfigured) credit = redeemRouterCredit;
        else credit = preview.configured ? preview.net : shares;
        if (burned > _positionShares) revert ForcedExecutionRevert();
        _positionShares -= burned;

        RedeemPreviewV2 memory remaining = _redeemPreviews[_positionShares];
        if (_positionShares == 0) {
            _positionNetAssets = 0;
            _positionGrossAssets = 0;
            _positionLiquidity = 0;
        } else if (remaining.configured) {
            _positionNetAssets = remaining.net;
            _positionGrossAssets = remaining.gross;
            _positionLiquidity = remaining.net;
        } else {
            uint256 netReduction = credit > _positionNetAssets ? _positionNetAssets : credit;
            _positionNetAssets -= netReduction;
            uint256 grossReduction = credit > _positionGrossAssets ? _positionGrossAssets : credit;
            _positionGrossAssets -= grossReduction;
            uint256 liquidityReduction = credit > _positionLiquidity ? _positionLiquidity : credit;
            _positionLiquidity -= liquidityReduction;
        }

        if (credit != 0) _mintOrTransferToRouter(credit);
        assetsReceived = _redeemExecutionConfigured ? redeemReturnedAssets : credit;
        if (!_ignoreMinimumChecks && credit < minAssetsOut) revert InsufficientAssetsOut();
    }

    function redeemAll(uint256 minAssetsOut) external returns (uint256 assetsReceived) {
        redeemAllCallCount++;
        stateChangingCallCount++;
        lastRedeemMinAssetsOut = minAssetsOut;
        if (_redeemCallbackTarget != address(0)) {
            address target = _redeemCallbackTarget;
            bytes memory data = _redeemCallbackData;
            _redeemCallbackTarget = address(0);
            delete _redeemCallbackData;
            (bool success, bytes memory returnData) = target.call(data);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
        uint256 direct = _asset.balanceOf(address(this));
        uint256 remainingUnderlying =
            _redeemAllExecutionConfigured ? redeemAllUnderlyingRemaining : 0;
        if (remainingUnderlying > direct) revert ForcedExecutionRevert();
        uint256 directCredit = direct - remainingUnderlying;
        if (directCredit != 0) _asset.safeTransfer(router, directCredit);

        uint256 defaultCredit = directCredit + _positionNetAssets;
        uint256 credit = _redeemAllExecutionConfigured ? redeemAllRouterCredit : defaultCredit;
        if (credit > directCredit) _mintOrTransferToRouter(credit - directCredit);

        _positionShares = _redeemAllExecutionConfigured ? redeemAllSharesRemaining : 0;
        _positionNetAssets = 0;
        _positionGrossAssets = 0;
        _positionLiquidity = 0;
        assetsReceived = _redeemAllExecutionConfigured ? redeemAllReturnedAssets : credit;
        if (credit < minAssetsOut) revert InsufficientAssetsOut();
    }

    function recoverPosition(address receiver) external returns (uint256 sharesRecovered) {
        recoverPositionCallCount++;
        stateChangingCallCount++;
        lastRecoveryReceiver = receiver;
        if (_recoveryCallbackTarget != address(0)) {
            address target = _recoveryCallbackTarget;
            bytes memory data = _recoveryCallbackData;
            _recoveryCallbackTarget = address(0);
            delete _recoveryCallbackData;
            (bool success, bytes memory returnData) = target.call(data);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }

        IERC20 token = IERC20(positionToken);
        uint256 balance = token.balanceOf(address(this));
        uint256 debit = _recoveryExecutionConfigured ? recoveryAdapterDebit : balance;
        uint256 credit = _recoveryExecutionConfigured ? recoveryReceiverCredit : debit;
        if (debit > balance) revert ForcedExecutionRevert();
        if (credit > debit) revert ForcedExecutionRevert();

        if (debit != 0) {
            SafeERC20.safeTransfer(IERC20(positionToken), receiver, credit);
        }

        uint256 sharesToBurn = debit - credit;
        if (sharesToBurn != 0 && positionToken != address(_asset)) {
            (bool ok,) = positionToken.call(
                abi.encodeWithSignature("burn(address,uint256)", address(this), sharesToBurn)
            );
            if (!ok) revert ForcedExecutionRevert();
        }

        _positionShares = _positionShares > debit ? _positionShares - debit : 0;
        _positionNetAssets = 0;
        _positionGrossAssets = 0;
        _positionLiquidity = 0;

        return _recoveryExecutionConfigured ? recoveryReturnedShares : debit;
    }

    function resetCallCounters() external {
        depositCallCount = 0;
        withdrawLiquidCallCount = 0;
        redeemCallCount = 0;
        redeemAllCallCount = 0;
        stateChangingCallCount = 0;
    }

    function _mintOrTransferToRouter(uint256 assets) private {
        (bool minted,) =
            address(_asset).call(abi.encodeWithSignature("mint(address,uint256)", router, assets));
        if (!minted) _asset.safeTransfer(router, assets);
    }
}
