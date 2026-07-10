// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IntentVerifier} from "src/IntentVerifier.sol";
import {Allocation, TEEResult} from "src/types/SignalVaultTypes.sol";

contract IntentVerifierTest is Test {
    uint256 internal constant TRUSTED_SIGNER_PK = 0xA11CE;
    address internal trustedSigner;
    IntentVerifier internal verifier;

    function setUp() external {
        trustedSigner = vm.addr(TRUSTED_SIGNER_PK);
        verifier = new IntentVerifier(trustedSigner);
    }

    function testVerifiesValidFlattenedEIP712Result() external view {
        TEEResult memory result = _result();
        bytes memory signature = _sign(result, TRUSTED_SIGNER_PK);

        assertTrue(verifier.verifyTEEResult(result, signature));
    }

    function testRejectsSignatureFromUntrustedSigner() external view {
        TEEResult memory result = _result();
        bytes memory signature = _sign(result, 0xB0B);

        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function testRejectsExpiredResult() external view {
        TEEResult memory result = _result();
        result.deadline = block.timestamp - 1;
        bytes memory signature = _sign(result, TRUSTED_SIGNER_PK);

        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function testRejectsWrongChain() external view {
        TEEResult memory result = _result();
        result.chainId = block.chainid + 1;
        bytes memory signature = _sign(result, TRUSTED_SIGNER_PK);

        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function testRejectsAllocationThatDoesNotTotalTenThousandBps() external view {
        TEEResult memory result = _result();
        result.allocation.idleBps = 1_999;
        bytes memory signature = _sign(result, TRUSTED_SIGNER_PK);

        assertFalse(verifier.verifyTEEResult(result, signature));
    }

    function _result() internal view returns (TEEResult memory) {
        return TEEResult({
            user: address(0xA11CE),
            vault: address(0xBEEF),
            intentCommitment: keccak256("commitment"),
            allocation: Allocation({
                upshiftBps: 5_000, firelightBps: 2_000, sparkdexBps: 1_000, idleBps: 2_000
            }),
            nonce: 1,
            deadline: block.timestamp + 1 hours,
            ftsoPriceTimestamp: block.timestamp,
            chainId: block.chainid,
            resultHash: keccak256("result")
        });
    }

    function _sign(TEEResult memory result, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = verifier.hashTypedData(result);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
