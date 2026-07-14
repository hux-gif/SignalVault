// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IStrategyAdapterV2} from "../../../src/v2/interfaces/IStrategyAdapterV2.sol";

contract RouterBindingAdapterMockV2 is IStrategyAdapterV2 {
    address public immutable override asset;
    address public immutable router;
    address public immutable override positionToken;

    error UnsupportedOperation();

    constructor(address asset_, address router_, address positionToken_) {
        asset = asset_;
        router = router_;
        positionToken = positionToken_;
    }

    function positionShares() external pure returns (uint256) {
        return 0;
    }

    function totalAssets() external pure returns (uint256) {
        return 0;
    }

    function grossAssets() external pure returns (uint256) {
        return 0;
    }

    function availableLiquidity() external pure returns (uint256) {
        return 0;
    }

    function protocolStatus() external pure returns (bool, bool, uint256, uint256) {
        return (true, true, type(uint256).max, 0);
    }

    function previewDeposit(uint256 assets)
        external
        pure
        returns (uint256 shares, uint256 immediateNetValue)
    {
        return (assets, assets);
    }

    function previewRedeem(uint256 shares)
        external
        pure
        returns (uint256 grossAssets_, uint256 netAssets)
    {
        return (shares, shares);
    }

    function withdrawLiquid(uint256) external pure returns (uint256) {
        revert UnsupportedOperation();
    }

    function deposit(uint256, uint256) external pure returns (uint256) {
        revert UnsupportedOperation();
    }

    function redeem(uint256, uint256) external pure returns (uint256) {
        revert UnsupportedOperation();
    }

    function redeemAll(uint256) external pure returns (uint256) {
        revert UnsupportedOperation();
    }
}
