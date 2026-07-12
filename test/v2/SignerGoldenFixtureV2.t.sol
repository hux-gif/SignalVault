// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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

    struct Result {
        address user;
        address vault;
        bytes32 intentCommitment;
        bytes32 capabilityProfile;
        bytes32 routerConfigHash;
        uint16 upshiftBps;
        uint16 firelightBps;
        uint16 sparkdexBps;
        uint16 idleBps;
        uint256 nonce;
        uint256 deadline;
        uint256 ftsoPriceTimestamp;
        uint256 chainId;
        uint256 minimumPostNAV;
        uint16 maximumRebalanceLossBps;
        uint16 maximumPreviewDeviationBps;
        uint16 allocationToleranceBps;
        bytes32 resultHash;
    }

    function testGoldenFixtureRecomputesHashesAndRecoversSigner() external view {
        string memory json = _json();
        assertTrue(json.readBool(".testOnly"));
        assertEq(json.readString(".domains.eip712.name"), "SignalVault");
        assertEq(json.readString(".domains.eip712.version"), "2");
        assertEq(_uint(json, ".domains.eip712.chainId"), 31_337);
        assertEq(json.readAddress(".domains.eip712.verifyingContract"), _verifier(json));
        assertEq(json.readBytes32(".domains.resultV2"), RESULT_V2_DOMAIN);

        bytes32 riskHash = _riskHash(json);
        assertEq(riskHash, json.readBytes32(".expected.riskConfigurationHash"));
        assertEq(json.readBytes32(".input.routerConfiguration.riskConfigurationHash"), riskHash);
        bytes32 routerHash = _routerHash(json);
        assertEq(routerHash, json.readBytes32(".expected.routerConfigHash"));

        Result memory result = _result(json);
        assertEq(result.routerConfigHash, routerHash);
        bytes32 resultHash = _resultHash(result, RESULT_V2_DOMAIN);
        assertEq(resultHash, json.readBytes32(".expected.resultHash"));
        assertEq(result.resultHash, resultHash);
        assertEq(_structHash(result), json.readBytes32(".expected.structHash"));
        assertEq(
            _domainSeparator(result.chainId, _verifier(json), "2"),
            json.readBytes32(".expected.eip712DomainSeparator")
        );
        bytes32 digest = _digest(result, _verifier(json), "2");
        assertEq(digest, json.readBytes32(".expected.typedDataDigest"));
        assertEq(
            ECDSA.recover(digest, json.readBytes(".expected.signature")),
            json.readAddress(".expected.signer")
        );
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
        Result memory result = _result(json);
        address signer = json.readAddress(".expected.signer");
        bytes memory v1Signature = json.readBytes(".expected.domainVersion1Signature");
        bytes32 v1Digest = _digest(result, _verifier(json), "1");
        assertEq(v1Digest, json.readBytes32(".expected.domainVersion1Digest"));
        assertEq(ECDSA.recover(v1Digest, v1Signature), signer);
        assertNotEq(ECDSA.recover(_digest(result, _verifier(json), "2"), v1Signature), signer);
        bytes32 v1EquivalentResultHash = _v1EquivalentResultHash(result);
        assertEq(v1EquivalentResultHash, json.readBytes32(".expected.v1EquivalentResultHash"));
        assertNotEq(result.resultHash, v1EquivalentResultHash);

        address wrongVerifier = address(0x9999999999999999999999999999999999999999);
        bytes32 wrongVerifierDigest = _digest(result, wrongVerifier, "2");
        assertNotEq(wrongVerifierDigest, json.readBytes32(".expected.typedDataDigest"));
        assertNotEq(
            ECDSA.recover(wrongVerifierDigest, json.readBytes(".expected.signature")), signer
        );
        assertNotEq(
            _resultHash(result, keccak256("SIGNALVAULT_TEE_RESULT_V2_REPLACED")), result.resultHash
        );
    }

    function _assertMutationRejected(uint256 field) private view {
        string memory json = _json();
        Result memory result = _result(json);
        if (field == 0) result.user = address(0x9999999999999999999999999999999999999999);
        else if (field == 1) result.vault = address(0x9999999999999999999999999999999999999999);
        else if (field == 2) result.intentCommitment = bytes32(uint256(999));
        else if (field == 3) result.capabilityProfile = bytes32(uint256(999));
        else if (field == 4) result.routerConfigHash = bytes32(uint256(999));
        else if (field == 5) result.upshiftBps++;
        else if (field == 6) result.firelightBps++;
        else if (field == 7) result.sparkdexBps++;
        else if (field == 8) result.idleBps++;
        else if (field == 9) result.nonce++;
        else if (field == 10) result.deadline++;
        else if (field == 11) result.ftsoPriceTimestamp++;
        else if (field == 12) result.chainId++;
        else if (field == 13) result.minimumPostNAV++;
        else if (field == 14) result.maximumRebalanceLossBps++;
        else if (field == 15) result.maximumPreviewDeviationBps++;
        else if (field == 16) result.allocationToleranceBps++;
        else result.resultHash = bytes32(uint256(999));

        (address recovered, ECDSA.RecoverError error,) = ECDSA.tryRecover(
            _digest(result, _verifier(json), "2"), json.readBytes(".expected.signature")
        );
        bool canonicalHashMatches = _resultHash(result, RESULT_V2_DOMAIN) == result.resultHash;
        assertTrue(
            error != ECDSA.RecoverError.NoError || recovered != json.readAddress(".expected.signer")
                || !canonicalHashMatches
        );
    }

    function _json() private view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/fixtures/tee-result-v2.json"));
    }

    function _uint(string memory json, string memory path) private pure returns (uint256) {
        return vm.parseUint(json.readString(path));
    }

    function _verifier(string memory json) private pure returns (address) {
        return json.readAddress(".input.intentVerifier");
    }

    function _riskHash(string memory json) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RISK_CONFIG_V1_DOMAIN,
                uint64(_uint(json, ".input.riskConfiguration.minimumRebalanceInterval")),
                uint16(_uint(json, ".input.riskConfiguration.minimumAllocationChangeBps")),
                uint16(_uint(json, ".input.riskConfiguration.maximumRebalanceLossBps")),
                uint16(_uint(json, ".input.riskConfiguration.maximumPreviewDeviationBps")),
                uint16(_uint(json, ".input.riskConfiguration.allocationToleranceBps"))
            )
        );
    }

    function _routerHash(string memory json) private pure returns (bytes32) {
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

    function _result(string memory json) private pure returns (Result memory r) {
        r.user = json.readAddress(".result.user");
        r.vault = json.readAddress(".result.vault");
        r.intentCommitment = json.readBytes32(".result.intentCommitment");
        r.capabilityProfile = json.readBytes32(".result.capabilityProfile");
        r.routerConfigHash = json.readBytes32(".result.routerConfigHash");
        r.upshiftBps = uint16(_uint(json, ".result.upshiftBps"));
        r.firelightBps = uint16(_uint(json, ".result.firelightBps"));
        r.sparkdexBps = uint16(_uint(json, ".result.sparkdexBps"));
        r.idleBps = uint16(_uint(json, ".result.idleBps"));
        r.nonce = _uint(json, ".result.nonce");
        r.deadline = _uint(json, ".result.deadline");
        r.ftsoPriceTimestamp = _uint(json, ".result.ftsoPriceTimestamp");
        r.chainId = _uint(json, ".result.chainId");
        r.minimumPostNAV = _uint(json, ".result.minimumPostNAV");
        r.maximumRebalanceLossBps = uint16(_uint(json, ".result.maximumRebalanceLossBps"));
        r.maximumPreviewDeviationBps = uint16(_uint(json, ".result.maximumPreviewDeviationBps"));
        r.allocationToleranceBps = uint16(_uint(json, ".result.allocationToleranceBps"));
        r.resultHash = json.readBytes32(".result.resultHash");
    }

    function _resultHash(Result memory r, bytes32 domain) private pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    domain,
                    r.user,
                    r.vault,
                    r.intentCommitment,
                    r.capabilityProfile,
                    r.routerConfigHash,
                    r.upshiftBps,
                    r.firelightBps,
                    r.sparkdexBps
                ),
                abi.encode(
                    r.idleBps,
                    r.nonce,
                    r.deadline,
                    r.ftsoPriceTimestamp,
                    r.chainId,
                    r.minimumPostNAV,
                    r.maximumRebalanceLossBps,
                    r.maximumPreviewDeviationBps,
                    r.allocationToleranceBps
                )
            )
        );
    }

    function _v1EquivalentResultHash(Result memory r) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                r.user,
                r.vault,
                r.intentCommitment,
                r.upshiftBps,
                r.firelightBps,
                r.sparkdexBps,
                r.idleBps,
                r.nonce,
                r.deadline,
                r.ftsoPriceTimestamp,
                r.chainId
            )
        );
    }

    function _structHash(Result memory r) private pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    TEERESULT_V2_TYPEHASH,
                    r.user,
                    r.vault,
                    r.intentCommitment,
                    r.capabilityProfile,
                    r.routerConfigHash,
                    r.upshiftBps,
                    r.firelightBps,
                    r.sparkdexBps
                ),
                abi.encode(
                    r.idleBps,
                    r.nonce,
                    r.deadline,
                    r.ftsoPriceTimestamp,
                    r.chainId,
                    r.minimumPostNAV,
                    r.maximumRebalanceLossBps,
                    r.maximumPreviewDeviationBps,
                    r.allocationToleranceBps,
                    r.resultHash
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

    function _digest(Result memory r, address verifier, string memory version)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                hex"1901", _domainSeparator(r.chainId, verifier, version), _structHash(r)
            )
        );
    }
}
