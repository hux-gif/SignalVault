// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyAdapterV2} from "../../../src/v2/interfaces/IStrategyAdapterV2.sol";

/// @notice Deterministic Router-bound adapter used only at the StrategyRouterV2 test seam.
contract InstrumentedStrategyAdapterV2 is IStrategyAdapterV2 {
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

    error ForcedViewRevert();
    error PreviewReverted();

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
        depositRouterDebit = routerDebit;
        depositAdapterCredit = adapterCredit;
        depositSharesMinted = sharesMinted;
        depositReturnedShares = returnedShares;
    }

    function setWithdrawalExecution(
        uint256 adapterDebit,
        uint256 routerCredit,
        uint256 returnedAssets
    ) external {
        withdrawalAdapterDebit = adapterDebit;
        withdrawalRouterCredit = routerCredit;
        withdrawalReturnedAssets = returnedAssets;
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
        return withdrawalReturnedAssets == 0 ? assets : withdrawalReturnedAssets;
    }

    function deposit(uint256 assets, uint256 minSharesOut)
        external
        returns (uint256 sharesReceived)
    {
        depositCallCount++;
        stateChangingCallCount++;
        lastDepositAssets = assets;
        lastDepositMinSharesOut = minSharesOut;
        return depositReturnedShares == 0 ? assets : depositReturnedShares;
    }

    function redeem(uint256 shares, uint256 minAssetsOut)
        external
        returns (uint256 assetsReceived)
    {
        redeemCallCount++;
        stateChangingCallCount++;
        lastRedeemShares = shares;
        lastRedeemMinAssetsOut = minAssetsOut;
        return withdrawalReturnedAssets == 0 ? shares : withdrawalReturnedAssets;
    }

    function redeemAll(uint256 minAssetsOut) external returns (uint256 assetsReceived) {
        redeemAllCallCount++;
        stateChangingCallCount++;
        lastRedeemMinAssetsOut = minAssetsOut;
        return withdrawalReturnedAssets;
    }

    function resetCallCounters() external {
        depositCallCount = 0;
        withdrawLiquidCallCount = 0;
        redeemCallCount = 0;
        redeemAllCallCount = 0;
        stateChangingCallCount = 0;
    }
}
