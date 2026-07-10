// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

struct Allocation {
    uint16 upshiftBps;
    uint16 firelightBps;
    uint16 sparkdexBps;
    uint16 idleBps;
}

struct TEEResult {
    address user;
    address vault;
    bytes32 intentCommitment;
    Allocation allocation;
    uint256 nonce;
    uint256 deadline;
    uint256 ftsoPriceTimestamp;
    uint256 chainId;
    bytes32 resultHash;
}
