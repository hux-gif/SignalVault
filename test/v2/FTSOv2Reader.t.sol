// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {FTSOv2Reader} from "../../src/v2/ftso/FTSOv2Reader.sol";
import {IFtsoV2Feed} from "../../src/v2/ftso/IFtsoV2Feed.sol";

contract MockFTSOv2Feed is IFtsoV2Feed {
    uint256 private _value;
    uint256 private _timestamp;
    uint8 private _decimals;

    function setFeed(uint256 value_, uint256 timestamp_, uint8 decimals_) external {
        _value = value_;
        _timestamp = timestamp_;
        _decimals = decimals_;
    }

    function getFeed(bytes21) external view returns (uint256 value, uint256 timestamp) {
        return (_value, _timestamp);
    }

    function getFeedDecimals(bytes21) external view returns (uint256 value, uint8 decimals) {
        return (_value, _decimals);
    }
}

contract FTSOv2ReaderTest is Test {
    MockFTSOv2Feed internal feed;
    FTSOv2Reader internal reader;
    bytes21 internal constant FLR_USD = bytes21(0x01464c525553440000000000000000000000000000);

    function setUp() public {
        vm.warp(1 hours);
        feed = new MockFTSOv2Feed();
        reader = new FTSOv2Reader(address(feed), 5 minutes);
    }

    function testReadFeedReturnsValueAndTimestamp() public {
        feed.setFeed(1_234_567_890, block.timestamp, 6);
        (uint256 value, uint256 timestamp) = reader.readFeed(FLR_USD);
        assertEq(value, 1_234_567_890);
        assertEq(timestamp, block.timestamp);
    }

    function testReadFeedRejectsStaleTimestamp() public {
        feed.setFeed(1_000, block.timestamp - 10 minutes, 6);
        vm.expectRevert(
            abi.encodeWithSelector(
                FTSOv2Reader.StaleFeed.selector,
                block.timestamp - 10 minutes,
                block.timestamp,
                5 minutes
            )
        );
        reader.readFeed(FLR_USD);
    }

    function testReadFeedRejectsZeroTimestamp() public {
        feed.setFeed(1_000, 0, 6);
        vm.expectRevert();
        reader.readFeed(FLR_USD);
    }

    function testReadFeedDecimals() public {
        feed.setFeed(1_000, block.timestamp, 8);
        (uint256 value, uint8 decimals) = reader.readFeedDecimals(FLR_USD);
        assertEq(value, 1_000);
        assertEq(decimals, 8);
    }

    function testFreshFeedAtBoundaryPasses() public {
        feed.setFeed(1_000, block.timestamp - 5 minutes, 6);
        (uint256 value,) = reader.readFeed(FLR_USD);
        assertEq(value, 1_000);
    }
}
