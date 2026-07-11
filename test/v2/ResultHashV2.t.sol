// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {SignalVaultHashesV2} from "src/v2/libraries/SignalVaultHashesV2.sol";
import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2,
    TEEResultV2
} from "src/v2/types/SignalVaultTypesV2.sol";

contract ResultHashV2Test is Test {
    address internal constant USER = address(0x1001);
    address internal constant VAULT = address(0x1002);
    address internal constant ROUTER = address(0x1003);
    address internal constant ASSET = address(0x1004);
    address internal constant UPSHIFT = address(0x1005);
    address internal constant IDLE = address(0x1006);
    bytes32 internal constant PROFILE = keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1");
    bytes32 internal constant RISK = bytes32(uint256(0x1007));

    function testResultHashStartsWithV2DomainAndUsesFrozenOrder() external pure {
        TEEResultV2 memory result = fixtureResult();
        bytes32 expected = keccak256(
            bytes.concat(
                abi.encode(
                    keccak256("SIGNALVAULT_TEE_RESULT_V2"),
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

        assertEq(SignalVaultHashesV2.computeResultHash(result), expected);
    }

    function testRiskConfigurationHashUsesFrozenFieldOrder() external pure {
        RiskConfigurationV2 memory risk = RiskConfigurationV2({
            minimumRebalanceInterval: 301,
            minimumAllocationChangeBps: 75,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 50,
            allocationToleranceBps: 25
        });
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("SIGNALVAULT_ROUTER_RISK_CONFIG_V1"),
                risk.minimumRebalanceInterval,
                risk.minimumAllocationChangeBps,
                risk.maximumRebalanceLossBps,
                risk.maximumPreviewDeviationBps,
                risk.allocationToleranceBps
            )
        );

        assertEq(SignalVaultHashesV2.computeRiskConfigurationHash(risk), expected);
    }

    function testRouterConfigHashUsesFrozenDomainAndOrder() external pure {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("SIGNALVAULT_ROUTER_CONFIG_V1"),
                uint256(114),
                VAULT,
                ROUTER,
                ASSET,
                UPSHIFT,
                IDLE,
                PROFILE,
                RISK,
                uint256(1)
            )
        );

        assertEq(configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1), expected);
    }

    function testRouterConfigHashMutatesForEveryBinding() external pure {
        bytes32 base = configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1);
        assertNotEq(base, configHash(115, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1));
        assertNotEq(
            base, configHash(114, address(1), ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1)
        );
        assertNotEq(
            base, configHash(114, VAULT, address(2), ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1)
        );
        assertNotEq(
            base, configHash(114, VAULT, ROUTER, address(3), UPSHIFT, IDLE, PROFILE, RISK, 1)
        );
        assertNotEq(base, configHash(114, VAULT, ROUTER, ASSET, address(4), IDLE, PROFILE, RISK, 1));
        assertNotEq(
            base, configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, address(5), PROFILE, RISK, 1)
        );
        assertNotEq(
            base, configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, bytes32(uint256(6)), RISK, 1)
        );
        assertNotEq(
            base,
            configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, bytes32(uint256(7)), 1)
        );
        assertNotEq(base, configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 2));
    }

    function fixtureResult() internal pure returns (TEEResultV2 memory) {
        return TEEResultV2({
            user: USER,
            vault: VAULT,
            intentCommitment: bytes32(uint256(0x2001)),
            capabilityProfile: PROFILE,
            routerConfigHash: bytes32(uint256(0x2002)),
            allocation: AllocationV2({
                upshiftBps: 5_000, firelightBps: 0, sparkdexBps: 0, idleBps: 5_000
            }),
            nonce: 17,
            deadline: 1_800_000_000,
            ftsoPriceTimestamp: 1_799_999_900,
            chainId: 114,
            limits: RebalanceLimitsV2({
                minimumPostNAV: 999_999_999_999_999_999,
                maximumRebalanceLossBps: 100,
                maximumPreviewDeviationBps: 50,
                allocationToleranceBps: 25
            }),
            resultHash: bytes32(uint256(0xDEAD))
        });
    }

    function configHash(
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
        return SignalVaultHashesV2.computeRouterConfigHash(
            chainId,
            vault,
            router,
            asset,
            upshiftAdapter,
            idleAdapter,
            capabilityProfile,
            riskConfigurationHash,
            version
        );
    }
}
