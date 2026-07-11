// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct AllocationV2 {
    uint16 upshiftBps;
    uint16 firelightBps;
    uint16 sparkdexBps;
    uint16 idleBps;
}

struct RebalanceLimitsV2 {
    uint256 minimumPostNAV;
    uint16 maximumRebalanceLossBps;
    uint16 maximumPreviewDeviationBps;
    uint16 allocationToleranceBps;
}

struct RiskConfigurationV2 {
    uint64 minimumRebalanceInterval;
    uint16 minimumAllocationChangeBps;
    uint16 maximumRebalanceLossBps;
    uint16 maximumPreviewDeviationBps;
    uint16 allocationToleranceBps;
}

struct TEEResultV2 {
    address user;
    address vault;
    bytes32 intentCommitment;
    bytes32 capabilityProfile;
    bytes32 routerConfigHash;
    AllocationV2 allocation;
    uint256 nonce;
    uint256 deadline;
    uint256 ftsoPriceTimestamp;
    uint256 chainId;
    RebalanceLimitsV2 limits;
    bytes32 resultHash;
}
