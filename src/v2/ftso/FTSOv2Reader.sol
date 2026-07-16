// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IFtsoV2Feed} from "./IFtsoV2Feed.sol";

/// @notice Read-only FTSOv2 feed reader with freshness validation.
/// Returns (value, timestamp) for a given feed ID.
contract FTSOv2Reader {
    IFtsoV2Feed public immutable feedContract;
    uint256 public immutable maxStaleSeconds;

    error StaleFeed(uint256 feedTimestamp, uint256 currentTime, uint256 maxStaleSeconds);

    constructor(address feedContract_, uint256 maxStaleSeconds_) {
        feedContract = IFtsoV2Feed(feedContract_);
        maxStaleSeconds = maxStaleSeconds_;
    }

    function readFeed(bytes21 feedId) external view returns (uint256 value, uint256 timestamp) {
        (value, timestamp) = feedContract.getFeed(feedId);
        if (timestamp == 0 || block.timestamp - timestamp > maxStaleSeconds) {
            revert StaleFeed(timestamp, block.timestamp, maxStaleSeconds);
        }
    }

    function readFeedDecimals(bytes21 feedId)
        external
        view
        returns (uint256 value, uint8 decimals)
    {
        (value, decimals) = feedContract.getFeedDecimals(feedId);
    }
}
