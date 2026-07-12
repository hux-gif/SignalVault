// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Router-only emergency LP position recovery, isolated from normal accounting,
/// underlying withdrawals, and rebalance operations.
interface IStrategyRecoveryV2 {
    /// @notice Transfers the complete recoverable position token balance to a receiver through
    /// the authorized Router emergency flow; it must not masquerade as an underlying withdrawal.
    /// @param receiver Address receiving the recovered position tokens.
    /// @return sharesRecovered Position-token amount transferred to the receiver.
    function recoverPosition(address receiver) external returns (uint256 sharesRecovered);
}
