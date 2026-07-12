// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Protocol-native Upshift vault interface matching the verified Coston2 ABI.
interface IUpshiftVaultV2 {
    function asset() external view returns (address);
    function lpTokenAddress() external view returns (address);

    function previewDeposit(address assetIn, uint256 amountIn)
        external
        view
        returns (uint256 shares, uint256 amountInReferenceTokens);

    function deposit(address assetIn, uint256 amountIn, address receiverAddr)
        external
        returns (uint256 shares);

    function previewRedemption(uint256 shares, bool isInstant)
        external
        view
        returns (uint256 assetsAmount, uint256 assetsAfterFee);

    function instantRedeem(uint256 shares, address receiverAddr) external;

    function withdrawalsPaused() external view returns (bool);
    function maxWithdrawalAmount() external view returns (uint256);
    function instantRedemptionFee() external view returns (uint256);
}
