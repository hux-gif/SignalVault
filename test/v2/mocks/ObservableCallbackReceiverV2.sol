// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Test callback target with observable success and failure paths.
contract ObservableCallbackReceiverV2 {
    uint256 public callbackCount;

    function recordCallback() external {
        callbackCount++;
    }

    function revertCallback() external pure {
        revert("callback rejected");
    }
}
