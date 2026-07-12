// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Protocol-native Upshift vault interface matching the verified Coston2 ABI.
interface IUpshiftVaultV2 {
    /// @notice Returns the protocol-reported underlying asset binding.
    function asset() external view returns (address);

    /// @notice Returns the protocol-reported LP token binding.
    function lpTokenAddress() external view returns (address);

    /// @notice Previews LP shares and reference-token value for an asset deposit.
    /// @param assetIn Underlying asset supplied to the protocol.
    /// @param amountIn Amount of underlying in token smallest units.
    /// @return shares Expected LP shares in LP-token smallest units.
    /// @return amountInReferenceTokens Protocol reference-token value in reference-token smallest
    /// units.
    function previewDeposit(address assetIn, uint256 amountIn)
        external
        view
        returns (uint256 shares, uint256 amountInReferenceTokens);

    /// @notice Deposits underlying and mints LP shares to a receiver.
    /// @param assetIn Underlying asset supplied to the protocol.
    /// @param amountIn Amount of underlying in token smallest units.
    /// @param receiverAddr Address receiving the LP shares.
    /// @return shares Actual LP shares in LP-token smallest units.
    function deposit(address assetIn, uint256 amountIn, address receiverAddr)
        external
        returns (uint256 shares);

    /// @notice Previews gross and after-fee redemption assets for LP shares.
    /// @param shares LP shares to redeem in LP-token smallest units.
    /// @param isInstant Whether the instant-redemption fee applies.
    /// @return assetsAmount Gross assets before fees in underlying-token smallest units.
    /// @return assetsAfterFee Net assets after applicable fees in underlying-token smallest units.
    function previewRedemption(uint256 shares, bool isInstant)
        external
        view
        returns (uint256 assetsAmount, uint256 assetsAfterFee);

    /// @notice Instantly redeems LP shares without returning the transferred asset amount.
    /// @param shares LP shares burned from the caller in LP-token smallest units.
    /// @param receiverAddr Address receiving the underlying assets.
    function instantRedeem(uint256 shares, address receiverAddr) external;

    /// @notice Returns whether protocol withdrawals are paused.
    function withdrawalsPaused() external view returns (bool);

    /// @notice Returns the live withdrawal limit in protocol reference-asset units.
    function maxWithdrawalAmount() external view returns (uint256);

    /// @notice Returns the raw live instant-redemption fee configuration.
    function instantRedemptionFee() external view returns (uint256);
}
