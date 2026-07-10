// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Allocation} from "../types/SignalVaultTypes.sol";

interface IStrategyRouter {
    function asset() external view returns (address);

    function vault() external view returns (address);

    function totalAssets() external view returns (uint256);

    function rebalance(Allocation calldata allocation) external returns (uint256 totalAssetsAfter);

    function withdrawProRata(uint256 vaultShares, uint256 totalVaultShares)
        external
        returns (uint256 assetsOut);
}
