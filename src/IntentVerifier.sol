// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Allocation, TEEResult} from "./types/SignalVaultTypes.sol";

contract IntentVerifier is EIP712, Ownable {
    bytes32 public constant TEERESULT_TYPEHASH = keccak256(
        "TEEResult(address user,address vault,bytes32 intentCommitment,"
        "uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps,"
        "uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,bytes32 resultHash)"
    );

    address public trustedSigner;

    event TrustedSignerUpdated(address indexed previousSigner, address indexed newSigner);

    constructor(address initialTrustedSigner) EIP712("SignalVault", "1") Ownable(msg.sender) {
        if (initialTrustedSigner == address(0)) revert ZeroAddress();
        trustedSigner = initialTrustedSigner;
    }

    function setTrustedSigner(address newTrustedSigner) external onlyOwner {
        if (newTrustedSigner == address(0)) revert ZeroAddress();
        emit TrustedSignerUpdated(trustedSigner, newTrustedSigner);
        trustedSigner = newTrustedSigner;
    }

    function hashTEEResult(TEEResult memory result) public pure returns (bytes32) {
        Allocation memory allocation = result.allocation;
        return keccak256(
            abi.encode(
                TEERESULT_TYPEHASH,
                result.user,
                result.vault,
                result.intentCommitment,
                allocation.upshiftBps,
                allocation.firelightBps,
                allocation.sparkdexBps,
                allocation.idleBps,
                result.nonce,
                result.deadline,
                result.ftsoPriceTimestamp,
                result.chainId,
                result.resultHash
            )
        );
    }

    function hashTypedData(TEEResult memory result) public view returns (bytes32) {
        return _hashTypedDataV4(hashTEEResult(result));
    }

    function verifyTEEResult(TEEResult memory result, bytes memory signature)
        public
        view
        returns (bool)
    {
        // forge-lint: disable-next-item(block-timestamp)
        if (
            result.chainId != block.chainid || result.deadline < block.timestamp
                || !_isValidAllocation(result.allocation)
        ) {
            return false;
        }

        (address recoveredSigner, ECDSA.RecoverError error,) =
            ECDSA.tryRecover(hashTypedData(result), signature);
        return error == ECDSA.RecoverError.NoError && recoveredSigner == trustedSigner;
    }

    function _isValidAllocation(Allocation memory allocation) private pure returns (bool) {
        return uint256(allocation.upshiftBps) + allocation.firelightBps + allocation.sparkdexBps
                + allocation.idleBps == 10_000;
    }

    error ZeroAddress();
}
