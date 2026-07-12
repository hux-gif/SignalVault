// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Frozen V2 adapter interface separating net accounting, gross telemetry,
/// direct liquidity, preview composition, and state-changing execution.
interface IStrategyAdapterV2 {
    /// @notice Returns the adapter's immutable underlying asset.
    function asset() external view returns (address);

    /// @notice Returns the protocol position token held by the adapter.
    function positionToken() external view returns (address);

    /// @notice Returns position-token shares currently held by the adapter, denominated in
    /// position-token smallest units.
    function positionShares() external view returns (uint256);

    /// @notice Returns net liquidation value, including direct underlying, denominated in
    /// underlying-token smallest units.
    function totalAssets() external view returns (uint256 netAssets);

    /// @notice Returns gross value before redemption fees for telemetry only, denominated in
    /// underlying-token smallest units.
    function grossAssets() external view returns (uint256 grossAssets_);

    /// @notice Returns conservatively and immediately withdrawable net underlying, denominated in
    /// underlying-token smallest units.
    function availableLiquidity() external view returns (uint256 netAssets);

    /// @notice Returns live deposit, withdrawal, limit, and fee protocol state.
    /// @return depositsEnabled Whether new protocol deposits are accepted.
    /// @return withdrawalsEnabled Whether normal protocol withdrawals are available.
    /// @return maxWithdrawalReferenceAmount Live limit in protocol reference-asset units.
    /// @return rawInstantRedemptionFee Raw protocol fee configuration without interpretation.
    function protocolStatus()
        external
        view
        returns (
            bool depositsEnabled,
            bool withdrawalsEnabled,
            uint256 maxWithdrawalReferenceAmount,
            uint256 rawInstantRedemptionFee
        );

    /// @notice Previews shares and immediate net liquidation value for a deposit.
    /// @param assets Underlying amount in token smallest units.
    /// @return shares Expected position-token shares in position-token smallest units.
    /// @return immediateNetValue Expected after-fee liquidation value in underlying-token
    /// smallest units.
    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares, uint256 immediateNetValue);

    /// @notice Previews gross and net underlying for a position redemption.
    /// @param shares Position-token shares in position-token smallest units.
    /// @return grossAssets_ Gross underlying before redemption fees in underlying-token smallest
    /// units.
    /// @return netAssets Net underlying after redemption fees in underlying-token smallest units.
    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 grossAssets_, uint256 netAssets);

    /// @notice Router-only normal operation that transfers direct underlying to the Router caller
    /// without redeeming position shares; it is not an emergency position-recovery path.
    /// @param assets Requested underlying amount in underlying-token smallest units.
    /// @return assetsReceived Measured underlying delivered to the caller in underlying-token
    /// smallest units.
    function withdrawLiquid(uint256 assets) external returns (uint256 assetsReceived);

    /// @notice Router-only normal operation that pulls underlying from the Router caller and
    /// deposits it using an exact, temporary protocol approval.
    /// @param assets Underlying amount supplied by the Router caller in underlying-token smallest
    /// units.
    /// @param minSharesOut Minimum acceptable measured shares in position-token smallest units.
    /// @return sharesReceived Measured position shares in position-token smallest units.
    function deposit(uint256 assets, uint256 minSharesOut) external returns (uint256 sharesReceived);

    /// @notice Router-only normal operation that redeems position shares and transfers the
    /// measured underlying output to the Router caller.
    /// @param shares Position shares to redeem in position-token smallest units.
    /// @param minAssetsOut Minimum acceptable measured underlying in underlying-token smallest
    /// units.
    /// @return assetsReceived Measured underlying received by the caller in underlying-token
    /// smallest units.
    function redeem(uint256 shares, uint256 minAssetsOut) external returns (uint256 assetsReceived);

    /// @notice Router-only normal operation that redeems the complete position, transfers every
    /// recoverable underlying unit to the Router caller, and succeeds only with zero underlying
    /// and zero position-token balance remaining in the adapter. Non-redeemable position tokens
    /// require the separate emergency recovery interface.
    /// @param minAssetsOut Minimum acceptable measured underlying in underlying-token smallest
    /// units.
    /// @return assetsReceived Measured underlying received by the caller in underlying-token
    /// smallest units.
    function redeemAll(uint256 minAssetsOut) external returns (uint256 assetsReceived);
}
