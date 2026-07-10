// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IStrategyRouter {
    function totalAssets() external view returns (uint256);

    function withdrawProRata(uint256 userShares, uint256 totalVaultShares)
        external
        returns (uint256 assetsOut);
}
