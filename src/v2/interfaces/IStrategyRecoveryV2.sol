// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Emergency LP position recovery, isolated from the normal adapter interface.
interface IStrategyRecoveryV2 {
    function recoverPosition(address receiver) external returns (uint256 sharesRecovered);
}
