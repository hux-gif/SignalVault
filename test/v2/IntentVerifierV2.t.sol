// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IntentVerifier} from "src/IntentVerifier.sol";
import {IntentVerifierV2} from "src/v2/IntentVerifierV2.sol";
import {SignalVaultHashesV2} from "src/v2/libraries/SignalVaultHashesV2.sol";
import {AllocationV2, RebalanceLimitsV2, TEEResultV2} from "src/v2/types/SignalVaultTypesV2.sol";
import {Allocation, TEEResult} from "src/types/SignalVaultTypes.sol";

contract IntentVerifierV2Test is Test {
    uint256 internal constant TRUSTED_SIGNER_PK = 0xA11CE;
    uint256 internal constant ROTATED_SIGNER_PK = 0xB0B;
    bytes32 internal constant PROFILE = keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1");
    bytes32 internal constant TYPEHASH = keccak256(
        "TEEResultV2(address user,address vault,bytes32 intentCommitment,bytes32 capabilityProfile,bytes32 routerConfigHash,uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,uint256 minimumPostNAV,uint16 maximumRebalanceLossBps,uint16 maximumPreviewDeviationBps,uint16 allocationToleranceBps,bytes32 resultHash)"
    );

    IntentVerifierV2 internal verifier;

    function setUp() external {
        verifier = new IntentVerifierV2(vm.addr(TRUSTED_SIGNER_PK));
    }

    function testTypeHashAndFlattenedStructHashUseFrozenOrder() external view {
        TEEResultV2 memory result = fixtureResult();
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        bytes32 expected = keccak256(
            bytes.concat(
                abi.encode(
                    TYPEHASH,
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

        assertEq(verifier.TEERESULT_V2_TYPEHASH(), TYPEHASH);
        assertEq(verifier.hashTEEResult(result), expected);
    }

    function testVerifiesV2AndRejectsV1Domain() external view {
        TEEResultV2 memory result = canonicalResult();
        assertTrue(verifier.verifyTEEResult(result, signV2(result)));
        assertFalse(verifier.verifyTEEResult(result, signWithDomainVersion(result, "1")));
    }

    function testRejectsWrongVerifyingContract() external {
        TEEResultV2 memory result = canonicalResult();
        IntentVerifierV2 otherVerifier = new IntentVerifierV2(vm.addr(TRUSTED_SIGNER_PK));
        bytes memory signature = signDigest(otherVerifier.hashTypedData(result), TRUSTED_SIGNER_PK);

        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function testRejectsActualV1SignatureBytes() external {
        IntentVerifier v1Verifier = new IntentVerifier(vm.addr(TRUSTED_SIGNER_PK));
        TEEResult memory v1Result = fixtureV1Result();
        bytes memory v1Signature = signDigest(v1Verifier.hashTypedData(v1Result), TRUSTED_SIGNER_PK);

        assertFalse(verifier.verifyTEEResult(canonicalResult(), v1Signature));
    }

    function testRejectsWrongChain() external view {
        TEEResultV2 memory result = canonicalResult();
        bytes memory signature = signV2(result);
        result.chainId++;
        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function testRejectsWrongVaultMutation() external view {
        TEEResultV2 memory result = canonicalResult();
        bytes memory signature = signV2(result);
        result.vault = address(0xBAD);
        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function testRejectsWrongConfigHashMutation() external view {
        TEEResultV2 memory result = canonicalResult();
        bytes memory signature = signV2(result);
        result.routerConfigHash = keccak256("mutated config");
        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function testRejectsExpiredDeadline() external view {
        TEEResultV2 memory result = canonicalResult();
        result.deadline = block.timestamp - 1;
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsZeroUser() external view {
        TEEResultV2 memory result = canonicalResult();
        result.user = address(0);
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsZeroVault() external view {
        TEEResultV2 memory result = canonicalResult();
        result.vault = address(0);
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsZeroCapabilityProfile() external view {
        TEEResultV2 memory result = canonicalResult();
        result.capabilityProfile = bytes32(0);
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsWrongCapabilityProfile() external view {
        TEEResultV2 memory result = canonicalResult();
        result.capabilityProfile = keccak256("WRONG_PROFILE");
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsZeroConfigHash() external view {
        TEEResultV2 memory result = canonicalResult();
        result.routerConfigHash = bytes32(0);
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsInvalidResultHash() external view {
        TEEResultV2 memory result = canonicalResult();
        result.resultHash = keccak256("invalid result hash");
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsUntrustedSigner() external view {
        TEEResultV2 memory result = canonicalResult();
        assertFalse(
            verifier.verifyTEEResult(
                result, signDigest(verifier.hashTypedData(result), ROTATED_SIGNER_PK)
            )
        );
    }

    function testRejectsMalformedSignatureWithoutReverting() external view {
        assertFalse(verifier.verifyTEEResult(canonicalResult(), hex"1234"));
    }

    function testRejectsUnsupportedCoston2Weights() external view {
        TEEResultV2 memory result = canonicalResult();
        result.allocation.firelightBps = 1;
        result.allocation.idleBps -= 1;
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsUnsupportedSparkdexWeight() external view {
        TEEResultV2 memory result = canonicalResult();
        result.allocation.sparkdexBps = 1;
        result.allocation.idleBps -= 1;
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsAllocationSumOtherThanTenThousand() external view {
        TEEResultV2 memory result = canonicalResult();
        result.allocation.idleBps -= 1;
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
    }

    function testRejectsZeroInitialTrustedSigner() external {
        vm.expectRevert(IntentVerifierV2.ZeroAddress.selector);
        new IntentVerifierV2(address(0));
    }

    function testOwnerCanRotateTrustedSigner() external {
        address rotatedSigner = vm.addr(ROTATED_SIGNER_PK);
        verifier.setTrustedSigner(rotatedSigner);
        TEEResultV2 memory result = canonicalResult();

        assertEq(verifier.trustedSigner(), rotatedSigner);
        assertFalse(verifier.verifyTEEResult(result, signV2(result)));
        assertTrue(
            verifier.verifyTEEResult(
                result, signDigest(verifier.hashTypedData(result), ROTATED_SIGNER_PK)
            )
        );
    }

    function testNonOwnerCannotRotateTrustedSigner() external {
        address originalSigner = verifier.trustedSigner();
        address nonOwner = address(0xBAD);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        vm.prank(nonOwner);
        verifier.setTrustedSigner(vm.addr(ROTATED_SIGNER_PK));

        assertEq(verifier.trustedSigner(), originalSigner);
    }

    function testRejectsZeroRotatedTrustedSigner() external {
        vm.expectRevert(IntentVerifierV2.ZeroAddress.selector);
        verifier.setTrustedSigner(address(0));
    }

    function canonicalResult() internal view returns (TEEResultV2 memory result) {
        result = fixtureResult();
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
    }

    function fixtureResult() internal view returns (TEEResultV2 memory) {
        return TEEResultV2({
            user: address(0x1001),
            vault: address(0x1002),
            intentCommitment: bytes32(uint256(0x2001)),
            capabilityProfile: PROFILE,
            routerConfigHash: bytes32(uint256(0x2002)),
            allocation: AllocationV2({
                upshiftBps: 5_000, firelightBps: 0, sparkdexBps: 0, idleBps: 5_000
            }),
            nonce: 17,
            deadline: block.timestamp + 1 hours,
            ftsoPriceTimestamp: block.timestamp,
            chainId: block.chainid,
            limits: RebalanceLimitsV2({
                minimumPostNAV: 999_999_999_999_999_999,
                maximumRebalanceLossBps: 100,
                maximumPreviewDeviationBps: 50,
                allocationToleranceBps: 25
            }),
            resultHash: bytes32(0)
        });
    }

    function fixtureV1Result() internal view returns (TEEResult memory) {
        return TEEResult({
            user: address(0x1001),
            vault: address(0x1002),
            intentCommitment: bytes32(uint256(0x2001)),
            allocation: Allocation({
                upshiftBps: 5_000, firelightBps: 2_000, sparkdexBps: 1_000, idleBps: 2_000
            }),
            nonce: 17,
            deadline: block.timestamp + 1 hours,
            ftsoPriceTimestamp: block.timestamp,
            chainId: block.chainid,
            resultHash: bytes32(uint256(0x2002))
        });
    }

    function signV2(TEEResultV2 memory result) internal view returns (bytes memory) {
        return signDigest(verifier.hashTypedData(result), TRUSTED_SIGNER_PK);
    }

    function signWithDomainVersion(TEEResultV2 memory result, string memory version)
        internal
        view
        returns (bytes memory)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("SignalVault"),
                keccak256(bytes(version)),
                block.chainid,
                address(verifier)
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked(hex"1901", domainSeparator, verifier.hashTEEResult(result)));
        return signDigest(digest, TRUSTED_SIGNER_PK);
    }

    function signDigest(bytes32 digest, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
