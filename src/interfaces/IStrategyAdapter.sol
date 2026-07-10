// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IStrategyAdapter {
    function asset() external view returns (address);
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 amount);
    function previewRedeem(uint256 shares) external view returns (uint256 amount);
    function totalAssets() external view returns (uint256);
    function riskScore() external view returns (uint256);
    function name() external view returns (string memory);
}
