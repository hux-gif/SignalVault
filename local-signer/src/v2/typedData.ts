import { hashTypedData, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { TEEResultV2 } from "./types.js";
import { validateCoston2ResultV2 } from "./validation.js";

export const teeResultV2Types = {
  TEEResultV2: [
    { name: "user", type: "address" },
    { name: "vault", type: "address" },
    { name: "intentCommitment", type: "bytes32" },
    { name: "capabilityProfile", type: "bytes32" },
    { name: "routerConfigHash", type: "bytes32" },
    { name: "upshiftBps", type: "uint16" },
    { name: "firelightBps", type: "uint16" },
    { name: "sparkdexBps", type: "uint16" },
    { name: "idleBps", type: "uint16" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "ftsoPriceTimestamp", type: "uint256" },
    { name: "chainId", type: "uint256" },
    { name: "minimumPostNAV", type: "uint256" },
    { name: "maximumRebalanceLossBps", type: "uint16" },
    { name: "maximumPreviewDeviationBps", type: "uint16" },
    { name: "allocationToleranceBps", type: "uint16" },
    { name: "resultHash", type: "bytes32" },
  ],
} as const;

export function teeResultV2Domain(chainId: bigint, verifier: Address) {
  return {
    name: "SignalVault",
    version: "2",
    chainId,
    verifyingContract: verifier,
  } as const;
}

export function teeResultV2Digest(result: TEEResultV2, verifier: Address): Hex {
  return hashTypedData({
    domain: teeResultV2Domain(result.chainId, verifier),
    types: teeResultV2Types,
    primaryType: "TEEResultV2",
    message: result,
  });
}

export function signTEEResultV2(
  result: TEEResultV2,
  verifier: Address,
  privateKey: Hex,
): Promise<Hex> {
  validateCoston2ResultV2(result);
  return privateKeyToAccount(privateKey).signTypedData({
    domain: teeResultV2Domain(result.chainId, verifier),
    types: teeResultV2Types,
    primaryType: "TEEResultV2",
    message: result,
  });
}
