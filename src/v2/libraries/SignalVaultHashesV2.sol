// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RiskConfigurationV2, TEEResultV2} from "../types/SignalVaultTypesV2.sol";

library SignalVaultHashesV2 {
    bytes32 internal constant RESULT_V2_DOMAIN = keccak256("SIGNALVAULT_TEE_RESULT_V2");
    bytes32 internal constant RISK_CONFIG_V1_DOMAIN =
        keccak256("SIGNALVAULT_ROUTER_RISK_CONFIG_V1");
    bytes32 internal constant ROUTER_CONFIG_V1_DOMAIN = keccak256("SIGNALVAULT_ROUTER_CONFIG_V1");
    bytes32 internal constant COSTON2_PROFILE = keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1");
    uint256 internal constant ROUTER_CONFIG_VERSION = 1;

    function computeResultHash(TEEResultV2 memory result) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    RESULT_V2_DOMAIN,
                    result.user,
                    result.vault,
                    result.intentCommitment,
                    result.capabilityProfile,
                    result.routerConfigHash,
                    result.allocation.upshiftBps,
                    result.allocation.firelightBps,
                    result.allocation.sparkdexBps
                ),
                abi.encode(
                    result.allocation.idleBps,
                    result.nonce,
                    result.deadline,
                    result.ftsoPriceTimestamp,
                    result.chainId,
                    result.limits.minimumPostNAV,
                    result.limits.maximumRebalanceLossBps,
                    result.limits.maximumPreviewDeviationBps,
                    result.limits.allocationToleranceBps
                )
            )
        );
    }

    function computeRiskConfigurationHash(RiskConfigurationV2 memory riskConfiguration)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                RISK_CONFIG_V1_DOMAIN,
                riskConfiguration.minimumRebalanceInterval,
                riskConfiguration.minimumAllocationChangeBps,
                riskConfiguration.maximumRebalanceLossBps,
                riskConfiguration.maximumPreviewDeviationBps,
                riskConfiguration.allocationToleranceBps
            )
        );
    }

    function computeRouterConfigHash(
        uint256 chainId,
        address vault,
        address router,
        address asset,
        address upshiftAdapter,
        address idleAdapter,
        bytes32 capabilityProfile,
        bytes32 riskConfigurationHash,
        uint256 version
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ROUTER_CONFIG_V1_DOMAIN,
                chainId,
                vault,
                router,
                asset,
                upshiftAdapter,
                idleAdapter,
                capabilityProfile,
                riskConfigurationHash,
                version
            )
        );
    }
}
