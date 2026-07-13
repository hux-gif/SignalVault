// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IStrategyAdapterV2} from "../../../src/v2/interfaces/IStrategyAdapterV2.sol";

/// @notice Deliberately non-reconciling strategy adapter used by later Router security tests.
/// It never transfers tokens and can over-report every economic return value.
contract MaliciousStrategyAdapterV2 is IStrategyAdapterV2 {
    address public immutable override asset;
    address public immutable override positionToken;
    uint256 public reportedValue;

    constructor(address asset_, address positionToken_) {
        asset = asset_;
        positionToken = positionToken_;
    }

    function setReportedValue(uint256 value) external {
        reportedValue = value;
    }

    function positionShares() external view returns (uint256) {
        return reportedValue;
    }

    function totalAssets() external view returns (uint256) {
        return reportedValue;
    }

    function grossAssets() external view returns (uint256) {
        return reportedValue;
    }

    function availableLiquidity() external view returns (uint256) {
        return reportedValue;
    }

    function protocolStatus() external pure returns (bool, bool, uint256, uint256) {
        return (true, true, type(uint256).max, 0);
    }

    function previewDeposit(uint256) external view returns (uint256, uint256) {
        return (reportedValue, reportedValue);
    }

    function previewRedeem(uint256) external view returns (uint256, uint256) {
        return (reportedValue, reportedValue);
    }

    function withdrawLiquid(uint256) external view returns (uint256) {
        return reportedValue;
    }

    function deposit(uint256, uint256) external view returns (uint256) {
        return reportedValue;
    }

    function redeem(uint256, uint256) external view returns (uint256) {
        return reportedValue;
    }

    function redeemAll(uint256) external view returns (uint256) {
        return reportedValue;
    }
}
