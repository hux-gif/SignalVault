// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Frozen V2 adapter interface separating net accounting, gross telemetry,
/// direct liquidity, preview composition, and state-changing execution.
interface IStrategyAdapterV2 {
    function asset() external view returns (address);
    function positionToken() external view returns (address);
    function positionShares() external view returns (uint256);
    function totalAssets() external view returns (uint256 netAssets);
    function grossAssets() external view returns (uint256 grossAssets_);
    function availableLiquidity() external view returns (uint256 netAssets);

    function protocolStatus()
        external
        view
        returns (
            bool depositsEnabled,
            bool withdrawalsEnabled,
            uint256 maxWithdrawalReferenceAmount,
            uint256 rawInstantRedemptionFee
        );

    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares, uint256 immediateNetValue);

    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 grossAssets_, uint256 netAssets);

    function withdrawLiquid(uint256 assets) external returns (uint256 assetsReceived);
    function deposit(uint256 assets, uint256 minSharesOut) external returns (uint256 sharesReceived);
    function redeem(uint256 shares, uint256 minAssetsOut) external returns (uint256 assetsReceived);
    function redeemAll(uint256 minAssetsOut) external returns (uint256 assetsReceived);
}
