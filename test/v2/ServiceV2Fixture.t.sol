// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IntentVerifierV2} from "src/v2/IntentVerifierV2.sol";
import {SignalVaultHashesV2} from "src/v2/libraries/SignalVaultHashesV2.sol";
import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2,
    TEEResultV2
} from "src/v2/types/SignalVaultTypesV2.sol";

/// @notice Cross-language integration: proves a V2 signature produced by
/// `local-signer/src/service-v2.ts` (TypeScript) verifies through the
/// production `IntentVerifierV2.verifyTEEResult` (Solidity) and that the
/// canonical `resultHash` matches `SignalVaultHashesV2.computeResultHash`.
///
/// Fixture: fixtures/service-v2-fixture.json
/// Generator: local-signer/scripts/generate-service-v2-fixture.ts
contract ServiceV2FixtureTest is Test {
    using stdJson for string;

    function setUp() public {
        string memory json = _json();
        vm.chainId(uint256(vm.parseUint(json.readString(".chainId"))));
        vm.warp(vm.parseUint(json.readString(".now")));
        deployCodeTo(
            "src/v2/IntentVerifierV2.sol:IntentVerifierV2",
            abi.encode(json.readAddress(".expected.signer")),
            json.readAddress(".input.intentVerifier")
        );
    }

    function testServiceV2SignatureVerifiesOnChain() external view {
        string memory json = _json();
        assertTrue(json.readBool(".testOnly"));

        TEEResultV2 memory result = _result(json);
        bytes memory signature = json.readBytes(".signature");

        // Canonical result hash parity.
        bytes32 canonical = SignalVaultHashesV2.computeResultHash(result);
        assertEq(canonical, result.resultHash, "resultHash mismatch");
        assertEq(canonical, json.readBytes32(".result.resultHash"), "fixture resultHash drift");

        // On-chain verifier accepts the TypeScript-produced signature.
        IntentVerifierV2 verifier = IntentVerifierV2(json.readAddress(".input.intentVerifier"));
        address recovered = ECDSA.recover(verifier.hashTypedData(result), signature);
        assertEq(
            recovered, json.readAddress(".expected.signer"), "signature does not recover to signer"
        );
        assertTrue(
            verifier.verifyTEEResult(result, signature),
            "verifyTEEResult rejected service-v2 signature"
        );

        // Coston2 capability profile is enforced (firelight/sparkdex must be zero).
        assertEq(result.allocation.firelightBps, 0, "firelightBps not zero");
        assertEq(result.allocation.sparkdexBps, 0, "sparkdexBps not zero");
        assertEq(
            uint256(result.allocation.upshiftBps) + uint256(result.allocation.idleBps),
            10_000,
            "Coston2 allocation must sum to 10000"
        );
    }

    function testServiceV2RouterConfigHashMatchesProduction() external view {
        string memory json = _json();
        bytes32 expected = json.readBytes32(".expected.routerConfigHash");
        bytes32 actual = SignalVaultHashesV2.computeRouterConfigHash(
            vm.parseUint(json.readString(".routerConfiguration.chainId")),
            json.readAddress(".routerConfiguration.vault"),
            json.readAddress(".routerConfiguration.router"),
            json.readAddress(".routerConfiguration.asset"),
            json.readAddress(".routerConfiguration.upshiftAdapter"),
            json.readAddress(".routerConfiguration.idleAdapter"),
            json.readBytes32(".routerConfiguration.capabilityProfile"),
            json.readBytes32(".routerConfiguration.riskConfigurationHash"),
            vm.parseUint(json.readString(".routerConfiguration.version"))
        );
        assertEq(actual, expected, "routerConfigHash drift between TS and Solidity");
    }

    function testServiceV2RiskConfigHashMatchesProduction() external view {
        string memory json = _json();
        RiskConfigurationV2 memory risk = _risk(json);
        bytes32 expected = json.readBytes32(".expected.riskConfigurationHash");
        bytes32 actual = SignalVaultHashesV2.computeRiskConfigurationHash(risk);
        assertEq(actual, expected, "riskConfigurationHash drift between TS and Solidity");
    }

    function _json() private view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/fixtures/service-v2-fixture.json"));
    }

    function _risk(string memory json) private pure returns (RiskConfigurationV2 memory risk) {
        risk.minimumRebalanceInterval =
            uint64(vm.parseUint(json.readString(".riskConfiguration.minimumRebalanceInterval")));
        risk.minimumAllocationChangeBps =
            uint16(vm.parseUint(json.readString(".riskConfiguration.minimumAllocationChangeBps")));
        risk.maximumRebalanceLossBps =
            uint16(vm.parseUint(json.readString(".riskConfiguration.maximumRebalanceLossBps")));
        risk.maximumPreviewDeviationBps =
            uint16(vm.parseUint(json.readString(".riskConfiguration.maximumPreviewDeviationBps")));
        risk.allocationToleranceBps =
            uint16(vm.parseUint(json.readString(".riskConfiguration.allocationToleranceBps")));
    }

    function _result(string memory json) private pure returns (TEEResultV2 memory result) {
        result.user = json.readAddress(".result.user");
        result.vault = json.readAddress(".result.vault");
        result.intentCommitment = json.readBytes32(".result.intentCommitment");
        result.capabilityProfile = json.readBytes32(".result.capabilityProfile");
        result.routerConfigHash = json.readBytes32(".result.routerConfigHash");
        result.allocation = AllocationV2({
            upshiftBps: uint16(vm.parseUint(json.readString(".result.upshiftBps"))),
            firelightBps: uint16(vm.parseUint(json.readString(".result.firelightBps"))),
            sparkdexBps: uint16(vm.parseUint(json.readString(".result.sparkdexBps"))),
            idleBps: uint16(vm.parseUint(json.readString(".result.idleBps")))
        });
        result.nonce = vm.parseUint(json.readString(".result.nonce"));
        result.deadline = vm.parseUint(json.readString(".result.deadline"));
        result.ftsoPriceTimestamp = vm.parseUint(json.readString(".result.ftsoPriceTimestamp"));
        result.chainId = vm.parseUint(json.readString(".result.chainId"));
        result.limits = RebalanceLimitsV2({
            minimumPostNAV: vm.parseUint(json.readString(".result.minimumPostNAV")),
            maximumRebalanceLossBps: uint16(
                vm.parseUint(json.readString(".result.maximumRebalanceLossBps"))
            ),
            maximumPreviewDeviationBps: uint16(
                vm.parseUint(json.readString(".result.maximumPreviewDeviationBps"))
            ),
            allocationToleranceBps: uint16(
                vm.parseUint(json.readString(".result.allocationToleranceBps"))
            )
        });
        result.resultHash = json.readBytes32(".result.resultHash");
    }
}
