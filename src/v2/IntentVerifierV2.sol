// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {SignalVaultHashesV2} from "./libraries/SignalVaultHashesV2.sol";
import {TEEResultV2} from "./types/SignalVaultTypesV2.sol";

contract IntentVerifierV2 is EIP712, Ownable {
    bytes32 public constant TEERESULT_V2_TYPEHASH = keccak256(
        "TEEResultV2(address user,address vault,bytes32 intentCommitment,bytes32 capabilityProfile,bytes32 routerConfigHash,uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,uint256 minimumPostNAV,uint16 maximumRebalanceLossBps,uint16 maximumPreviewDeviationBps,uint16 allocationToleranceBps,bytes32 resultHash)"
    );
    address public trustedSigner;

    event TrustedSignerUpdated(address indexed previousSigner, address indexed newSigner);

    constructor(address initialTrustedSigner) EIP712("SignalVault", "2") Ownable(msg.sender) {
        if (initialTrustedSigner == address(0)) revert ZeroAddress();
        trustedSigner = initialTrustedSigner;
    }

    function setTrustedSigner(address newTrustedSigner) external onlyOwner {
        if (newTrustedSigner == address(0)) revert ZeroAddress();
        emit TrustedSignerUpdated(trustedSigner, newTrustedSigner);
        trustedSigner = newTrustedSigner;
    }

    function hashTEEResult(TEEResultV2 memory result) public pure returns (bytes32) {
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

    function hashTypedData(TEEResultV2 memory result) public view returns (bytes32) {
        return _hashTypedDataV4(hashTEEResult(result));
    }

    function verifyTEEResult(TEEResultV2 memory result, bytes memory signature)
        public
        view
        returns (bool)
    {
        // forge-lint: disable-next-item(block-timestamp)
        if (
            result.user == address(0) || result.vault == address(0)
                || result.chainId != block.chainid || result.deadline < block.timestamp
                || result.capabilityProfile != SignalVaultHashesV2.COSTON2_PROFILE
                || result.routerConfigHash == bytes32(0)
                || result.resultHash != SignalVaultHashesV2.computeResultHash(result)
                || result.allocation.firelightBps != 0 || result.allocation.sparkdexBps != 0
                || uint256(result.allocation.upshiftBps) + result.allocation.idleBps != 10_000
        ) {
            return false;
        }

        (address recoveredSigner, ECDSA.RecoverError error,) =
            ECDSA.tryRecover(hashTypedData(result), signature);
        return error == ECDSA.RecoverError.NoError && recoveredSigner == trustedSigner;
    }

    error ZeroAddress();
}
