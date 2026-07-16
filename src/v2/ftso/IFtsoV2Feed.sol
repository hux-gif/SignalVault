// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Minimal Flare FTSOv2 feed interface for read-only access.
interface IFtsoV2Feed {
    function getFeed(bytes21 feedId) external view returns (uint256 value, uint256 timestamp);
    function getFeedDecimals(bytes21 feedId) external view returns (uint256 value, uint8 decimals);
}
