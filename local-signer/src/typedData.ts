import { hashTypedData, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { TEEResult } from "./types.js";

export const teeResultTypes = {
  TEEResult: [
    { name: "user", type: "address" }, { name: "vault", type: "address" },
    { name: "intentCommitment", type: "bytes32" }, { name: "upshiftBps", type: "uint16" },
    { name: "firelightBps", type: "uint16" }, { name: "sparkdexBps", type: "uint16" },
    { name: "idleBps", type: "uint16" }, { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" }, { name: "ftsoPriceTimestamp", type: "uint256" },
    { name: "chainId", type: "uint256" }, { name: "resultHash", type: "bytes32" },
  ],
} as const;

export function teeResultDomain(chainId: bigint, verifier: Address) {
  return { name: "SignalVault", version: "1", chainId, verifyingContract: verifier } as const;
}

export function teeResultDigest(result: TEEResult, verifier: Address): Hex {
  return hashTypedData({ domain: teeResultDomain(result.chainId, verifier), types: teeResultTypes, primaryType: "TEEResult", message: result });
}

export function signTEEResult(result: TEEResult, verifier: Address, privateKey: Hex): Promise<Hex> {
  return privateKeyToAccount(privateKey).signTypedData({
    domain: teeResultDomain(result.chainId, verifier), types: teeResultTypes,
    primaryType: "TEEResult", message: result,
  });
}
