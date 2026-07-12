// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Emergency LP position recovery, isolated from the normal adapter interface.
interface IStrategyRecoveryV2 {
    /// @notice Transfers the complete recoverable position token balance to a receiver.
    /// @param receiver Address receiving the recovered position tokens.
    /// @return sharesRecovered Position-token amount transferred to the receiver.
    function recoverPosition(address receiver) external returns (uint256 sharesRecovered);
}
