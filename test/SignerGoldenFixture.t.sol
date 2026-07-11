// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SignerGoldenFixtureTest is Test {
    using stdJson for string;

    bytes32 private constant PLAIN_INTENT_TYPEHASH = keccak256(
        "PrivateIntent(uint8 riskLevel,uint16 targetAprBps,uint16 maxDrawdownBps,uint32 rebalanceWindow)"
    );
    bytes32 private constant SIGNALVAULT_DOMAIN = keccak256("SignalVault.PrivateIntent.v1");
    bytes32 private constant TEERESULT_TYPEHASH = keccak256(
        "TEEResult(address user,address vault,bytes32 intentCommitment,uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,bytes32 resultHash)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    struct Golden {
        address user;
        address vault;
        address verifier;
        bytes32 salt;
        uint8 riskLevel;
        uint16 targetAprBps;
        uint16 maxDrawdownBps;
        uint32 rebalanceWindow;
        uint16 upshiftBps;
        uint16 firelightBps;
        uint16 sparkdexBps;
        uint16 idleBps;
        uint256 nonce;
        uint256 deadline;
        uint256 ftsoTimestamp;
        uint256 chainId;
    }

    function testCrossLanguageGoldenFixture() external view {
        string memory json =
            vm.readFile(string.concat(vm.projectRoot(), "/fixtures/signer-golden.json"));
        assertTrue(json.readBool(".testOnly"));
        Golden memory fixture = _readFixture(json);
        bytes32 commitment = _commitment(fixture);
        assertEq(commitment, json.readBytes32(".expected.commitment"));
        bytes32 resultHash = _resultHash(fixture, commitment);
        assertEq(resultHash, json.readBytes32(".expected.resultHash"));
        bytes32 digest = _digest(fixture, commitment, resultHash);
        assertEq(digest, json.readBytes32(".expected.typedDataDigest"));

        uint256 privateKey = json.readUint(".testPrivateKey");
        assertEq(vm.addr(privateKey), json.readAddress(".expected.signer"));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        assertEq(ECDSA.recover(digest, v, r, s), json.readAddress(".expected.signer"));
    }

    function _readFixture(string memory json) private pure returns (Golden memory f) {
        f.user = json.readAddress(".input.user");
        f.vault = json.readAddress(".input.vault");
        f.verifier = json.readAddress(".input.intentVerifier");
        f.salt = json.readBytes32(".input.plainIntent.salt");
        f.riskLevel = uint8(json.readUint(".input.plainIntent.riskLevel"));
        f.targetAprBps = uint16(json.readUint(".input.plainIntent.targetAprBps"));
        f.maxDrawdownBps = uint16(json.readUint(".input.plainIntent.maxDrawdownBps"));
        f.rebalanceWindow = uint32(json.readUint(".input.plainIntent.rebalanceWindow"));
        f.upshiftBps = uint16(json.readUint(".result.upshiftBps"));
        f.firelightBps = uint16(json.readUint(".result.firelightBps"));
        f.sparkdexBps = uint16(json.readUint(".result.sparkdexBps"));
        f.idleBps = uint16(json.readUint(".result.idleBps"));
        f.nonce = json.readUint(".input.nonce");
        f.deadline = json.readUint(".result.deadline");
        f.ftsoTimestamp = json.readUint(".result.ftsoPriceTimestamp");
        f.chainId = json.readUint(".input.chainId");
    }

    function _commitment(Golden memory f) private pure returns (bytes32) {
        bytes32 plainHash = keccak256(
            abi.encode(
                PLAIN_INTENT_TYPEHASH,
                f.riskLevel,
                f.targetAprBps,
                f.maxDrawdownBps,
                f.rebalanceWindow
            )
        );
        return
            keccak256(abi.encode(SIGNALVAULT_DOMAIN, f.user, plainHash, f.salt, f.nonce, f.chainId));
    }

    function _resultHash(Golden memory f, bytes32 commitment) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                f.user,
                f.vault,
                commitment,
                f.upshiftBps,
                f.firelightBps,
                f.sparkdexBps,
                f.idleBps,
                f.nonce,
                f.deadline,
                f.ftsoTimestamp,
                f.chainId
            )
        );
    }

    function _digest(Golden memory f, bytes32 commitment, bytes32 resultHash)
        private
        pure
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                TEERESULT_TYPEHASH,
                f.user,
                f.vault,
                commitment,
                f.upshiftBps,
                f.firelightBps,
                f.sparkdexBps,
                f.idleBps,
                f.nonce,
                f.deadline,
                f.ftsoTimestamp,
                f.chainId,
                resultHash
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("SignalVault"),
                keccak256("1"),
                f.chainId,
                f.verifier
            )
        );
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
    }
}
