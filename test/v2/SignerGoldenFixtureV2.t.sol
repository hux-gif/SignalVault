// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IntentVerifierV2} from "../../src/v2/IntentVerifierV2.sol";
import {SignalVaultHashesV2} from "../../src/v2/libraries/SignalVaultHashesV2.sol";
import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2,
    TEEResultV2
} from "../../src/v2/types/SignalVaultTypesV2.sol";

contract SignerGoldenFixtureV2Test is Test {
    using stdJson for string;

    bytes32 private constant RESULT_V2_DOMAIN = keccak256("SIGNALVAULT_TEE_RESULT_V2");
    bytes32 private constant RISK_CONFIG_V1_DOMAIN = keccak256("SIGNALVAULT_ROUTER_RISK_CONFIG_V1");
    bytes32 private constant ROUTER_CONFIG_V1_DOMAIN = keccak256("SIGNALVAULT_ROUTER_CONFIG_V1");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant TEERESULT_V2_TYPEHASH = keccak256(
        "TEEResultV2(address user,address vault,bytes32 intentCommitment,bytes32 capabilityProfile,bytes32 routerConfigHash,uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,uint256 minimumPostNAV,uint16 maximumRebalanceLossBps,uint16 maximumPreviewDeviationBps,uint16 allocationToleranceBps,bytes32 resultHash)"
    );

    function setUp() public {
        vm.chainId(31_337);
        vm.warp(1_999_999_500);
        string memory json = _json();
        deployCodeTo(
            "src/v2/IntentVerifierV2.sol:IntentVerifierV2",
            abi.encode(json.readAddress(".expected.signer")),
            _verifierAddress(json)
        );
    }

    function testGoldenFixtureExercisesProductionHashesAndVerifier() external view {
        string memory json = _json();
        assertTrue(json.readBool(".testOnly"));
        assertEq(json.readString(".domains.eip712.name"), "SignalVault");
        assertEq(json.readString(".domains.eip712.version"), "2");
        assertEq(_uint(json, ".domains.eip712.chainId"), 31_337);
        assertEq(json.readAddress(".domains.eip712.verifyingContract"), _verifierAddress(json));
        assertEq(json.readBytes32(".domains.resultV2"), RESULT_V2_DOMAIN);

        RiskConfigurationV2 memory risk = _riskConfiguration(json);
        bytes32 riskHash = SignalVaultHashesV2.computeRiskConfigurationHash(risk);
        assertEq(riskHash, _independentRiskHash(risk));
        assertEq(riskHash, json.readBytes32(".expected.riskConfigurationHash"));
        assertEq(json.readBytes32(".input.routerConfiguration.riskConfigurationHash"), riskHash);

        bytes32 routerHash = _productionRouterHash(json);
        assertEq(routerHash, _independentRouterHash(json));
        assertEq(routerHash, json.readBytes32(".expected.routerConfigHash"));

        TEEResultV2 memory result = _result(json);
        assertEq(result.routerConfigHash, routerHash);
        bytes32 resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertEq(resultHash, _independentResultHash(result, RESULT_V2_DOMAIN));
        assertEq(resultHash, json.readBytes32(".expected.resultHash"));
        assertEq(result.resultHash, resultHash);

        IntentVerifierV2 verifier = _verifier(json);
        address signer = json.readAddress(".expected.signer");
        assertEq(verifier.trustedSigner(), signer);
        bytes32 structHash = verifier.hashTEEResult(result);
        assertEq(structHash, _independentStructHash(result));
        assertEq(structHash, json.readBytes32(".expected.structHash"));
        assertEq(
            _domainSeparator(result.chainId, address(verifier), "2"),
            json.readBytes32(".expected.eip712DomainSeparator")
        );
        bytes32 digest = verifier.hashTypedData(result);
        assertEq(digest, _independentDigest(result, address(verifier), "2"));
        assertEq(digest, json.readBytes32(".expected.typedDataDigest"));
        bytes memory signature = json.readBytes(".expected.signature");
        assertEq(ECDSA.recover(digest, signature), signer);
        assertTrue(verifier.verifyTEEResult(result, signature));
    }

    function testMutation_user() external view {
        _assertMutationRejected(0);
    }

    function testMutation_vault() external view {
        _assertMutationRejected(1);
    }

    function testMutation_intentCommitment() external view {
        _assertMutationRejected(2);
    }

    function testMutation_capabilityProfile() external view {
        _assertMutationRejected(3);
    }

    function testMutation_routerConfigHash() external view {
        _assertMutationRejected(4);
    }

    function testMutation_upshiftBps() external view {
        _assertMutationRejected(5);
    }

    function testMutation_firelightBps() external view {
        _assertMutationRejected(6);
    }

    function testMutation_sparkdexBps() external view {
        _assertMutationRejected(7);
    }

    function testMutation_idleBps() external view {
        _assertMutationRejected(8);
    }

    function testMutation_nonce() external view {
        _assertMutationRejected(9);
    }

    function testMutation_deadline() external view {
        _assertMutationRejected(10);
    }

    function testMutation_ftsoPriceTimestamp() external view {
        _assertMutationRejected(11);
    }

    function testMutation_chainId() external view {
        _assertMutationRejected(12);
    }

    function testMutation_minimumPostNAV() external view {
        _assertMutationRejected(13);
    }

    function testMutation_maximumRebalanceLossBps() external view {
        _assertMutationRejected(14);
    }

    function testMutation_maximumPreviewDeviationBps() external view {
        _assertMutationRejected(15);
    }

    function testMutation_allocationToleranceBps() external view {
        _assertMutationRejected(16);
    }

    function testMutation_resultHash() external view {
        _assertMutationRejected(17);
    }

    function testDomainAndV1Separation() external view {
        string memory json = _json();
        TEEResultV2 memory result = _result(json);
        address signer = json.readAddress(".expected.signer");
        bytes memory v1Signature = json.readBytes(".expected.domainVersion1Signature");
        bytes32 v1Digest = _independentDigest(result, address(_verifier(json)), "1");
        assertEq(v1Digest, json.readBytes32(".expected.domainVersion1Digest"));
        assertEq(ECDSA.recover(v1Digest, v1Signature), signer);
        assertNotEq(ECDSA.recover(_verifier(json).hashTypedData(result), v1Signature), signer);
        bytes32 v1EquivalentResultHash = _v1EquivalentResultHash(result);
        assertEq(v1EquivalentResultHash, json.readBytes32(".expected.v1EquivalentResultHash"));
        assertNotEq(result.resultHash, v1EquivalentResultHash);

        address wrongVerifier = address(0x9999999999999999999999999999999999999999);
        bytes32 wrongVerifierDigest = _independentDigest(result, wrongVerifier, "2");
        assertNotEq(wrongVerifierDigest, json.readBytes32(".expected.typedDataDigest"));
        assertNotEq(
            ECDSA.recover(wrongVerifierDigest, json.readBytes(".expected.signature")), signer
        );
        assertNotEq(
            _independentResultHash(result, keccak256("SIGNALVAULT_TEE_RESULT_V2_REPLACED")),
            result.resultHash
        );
    }

    function _assertMutationRejected(uint256 field) private view {
        string memory json = _json();
        TEEResultV2 memory result = _result(json);
        bytes32 originalResultHash = result.resultHash;
        _mutate(result, field);

        IntentVerifierV2 verifier = _verifier(json);
        bytes memory signature = json.readBytes(".expected.signature");
        (address recovered, ECDSA.RecoverError error,) =
            ECDSA.tryRecover(verifier.hashTypedData(result), signature);
        assertEq(uint256(error), uint256(ECDSA.RecoverError.NoError));
        assertNotEq(recovered, json.readAddress(".expected.signer"));

        bytes32 recomputedCanonicalHash = SignalVaultHashesV2.computeResultHash(result);
        if (field == 17) {
            assertEq(recomputedCanonicalHash, originalResultHash);
            assertNotEq(recomputedCanonicalHash, result.resultHash);
        } else {
            assertNotEq(recomputedCanonicalHash, originalResultHash);
            assertNotEq(recomputedCanonicalHash, result.resultHash);
        }
        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function _mutate(TEEResultV2 memory result, uint256 field) private pure {
        if (field == 0) result.user = address(0x9999999999999999999999999999999999999999);
        else if (field == 1) result.vault = address(0x9999999999999999999999999999999999999999);
        else if (field == 2) result.intentCommitment = bytes32(uint256(999));
        else if (field == 3) result.capabilityProfile = bytes32(uint256(999));
        else if (field == 4) result.routerConfigHash = bytes32(uint256(999));
        else if (field == 5) result.allocation.upshiftBps++;
        else if (field == 6) result.allocation.firelightBps++;
        else if (field == 7) result.allocation.sparkdexBps++;
        else if (field == 8) result.allocation.idleBps++;
        else if (field == 9) result.nonce++;
        else if (field == 10) result.deadline++;
        else if (field == 11) result.ftsoPriceTimestamp++;
        else if (field == 12) result.chainId++;
        else if (field == 13) result.limits.minimumPostNAV++;
        else if (field == 14) result.limits.maximumRebalanceLossBps++;
        else if (field == 15) result.limits.maximumPreviewDeviationBps++;
        else if (field == 16) result.limits.allocationToleranceBps++;
        else result.resultHash = bytes32(uint256(999));
    }

    function _json() private view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/fixtures/tee-result-v2.json"));
    }

    function _uint(string memory json, string memory path) private pure returns (uint256) {
        return vm.parseUint(json.readString(path));
    }

    function _verifierAddress(string memory json) private pure returns (address) {
        return json.readAddress(".input.intentVerifier");
    }

    function _verifier(string memory json) private pure returns (IntentVerifierV2) {
        return IntentVerifierV2(_verifierAddress(json));
    }

    function _riskConfiguration(string memory json)
        private
        pure
        returns (RiskConfigurationV2 memory risk)
    {
        risk.minimumRebalanceInterval =
            uint64(_uint(json, ".input.riskConfiguration.minimumRebalanceInterval"));
        risk.minimumAllocationChangeBps =
            uint16(_uint(json, ".input.riskConfiguration.minimumAllocationChangeBps"));
        risk.maximumRebalanceLossBps =
            uint16(_uint(json, ".input.riskConfiguration.maximumRebalanceLossBps"));
        risk.maximumPreviewDeviationBps =
            uint16(_uint(json, ".input.riskConfiguration.maximumPreviewDeviationBps"));
        risk.allocationToleranceBps =
            uint16(_uint(json, ".input.riskConfiguration.allocationToleranceBps"));
    }

    function _productionRouterHash(string memory json) private pure returns (bytes32) {
        return SignalVaultHashesV2.computeRouterConfigHash(
            _uint(json, ".input.routerConfiguration.chainId"),
            json.readAddress(".input.routerConfiguration.vault"),
            json.readAddress(".input.routerConfiguration.router"),
            json.readAddress(".input.routerConfiguration.asset"),
            json.readAddress(".input.routerConfiguration.upshiftAdapter"),
            json.readAddress(".input.routerConfiguration.idleAdapter"),
            json.readBytes32(".input.routerConfiguration.capabilityProfile"),
            json.readBytes32(".input.routerConfiguration.riskConfigurationHash"),
            _uint(json, ".input.routerConfiguration.version")
        );
    }

    function _result(string memory json) private pure returns (TEEResultV2 memory result) {
        result.user = json.readAddress(".result.user");
        result.vault = json.readAddress(".result.vault");
        result.intentCommitment = json.readBytes32(".result.intentCommitment");
        result.capabilityProfile = json.readBytes32(".result.capabilityProfile");
        result.routerConfigHash = json.readBytes32(".result.routerConfigHash");
        result.allocation = AllocationV2({
            upshiftBps: uint16(_uint(json, ".result.upshiftBps")),
            firelightBps: uint16(_uint(json, ".result.firelightBps")),
            sparkdexBps: uint16(_uint(json, ".result.sparkdexBps")),
            idleBps: uint16(_uint(json, ".result.idleBps"))
        });
        result.nonce = _uint(json, ".result.nonce");
        result.deadline = _uint(json, ".result.deadline");
        result.ftsoPriceTimestamp = _uint(json, ".result.ftsoPriceTimestamp");
        result.chainId = _uint(json, ".result.chainId");
        result.limits = RebalanceLimitsV2({
            minimumPostNAV: _uint(json, ".result.minimumPostNAV"),
            maximumRebalanceLossBps: uint16(_uint(json, ".result.maximumRebalanceLossBps")),
            maximumPreviewDeviationBps: uint16(_uint(json, ".result.maximumPreviewDeviationBps")),
            allocationToleranceBps: uint16(_uint(json, ".result.allocationToleranceBps"))
        });
        result.resultHash = json.readBytes32(".result.resultHash");
    }

    function _independentRiskHash(RiskConfigurationV2 memory risk) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RISK_CONFIG_V1_DOMAIN,
                risk.minimumRebalanceInterval,
                risk.minimumAllocationChangeBps,
                risk.maximumRebalanceLossBps,
                risk.maximumPreviewDeviationBps,
                risk.allocationToleranceBps
            )
        );
    }

    function _independentRouterHash(string memory json) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ROUTER_CONFIG_V1_DOMAIN,
                _uint(json, ".input.routerConfiguration.chainId"),
                json.readAddress(".input.routerConfiguration.vault"),
                json.readAddress(".input.routerConfiguration.router"),
                json.readAddress(".input.routerConfiguration.asset"),
                json.readAddress(".input.routerConfiguration.upshiftAdapter"),
                json.readAddress(".input.routerConfiguration.idleAdapter"),
                json.readBytes32(".input.routerConfiguration.capabilityProfile"),
                json.readBytes32(".input.routerConfiguration.riskConfigurationHash"),
                _uint(json, ".input.routerConfiguration.version")
            )
        );
    }

    function _independentResultHash(TEEResultV2 memory result, bytes32 domain)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            bytes.concat(
                abi.encode(
                    domain,
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

    function _v1EquivalentResultHash(TEEResultV2 memory result) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                result.user,
                result.vault,
                result.intentCommitment,
                result.allocation.upshiftBps,
                result.allocation.firelightBps,
                result.allocation.sparkdexBps,
                result.allocation.idleBps,
                result.nonce,
                result.deadline,
                result.ftsoPriceTimestamp,
                result.chainId
            )
        );
    }

    function _independentStructHash(TEEResultV2 memory result) private pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    TEERESULT_V2_TYPEHASH,
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
                    result.limits.allocationToleranceBps,
                    result.resultHash
                )
            )
        );
    }

    function _domainSeparator(uint256 chainId, address verifier, string memory version)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("SignalVault"),
                keccak256(bytes(version)),
                chainId,
                verifier
            )
        );
    }

    function _independentDigest(TEEResultV2 memory result, address verifier, string memory version)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                hex"1901",
                _domainSeparator(result.chainId, verifier, version),
                _independentStructHash(result)
            )
        );
    }
}
