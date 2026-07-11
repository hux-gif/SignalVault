import { encodeAbiParameters, keccak256, parseAbiParameters, stringToHex, type Address, type Hex } from "viem";
import type { PlainIntent } from "./types.js";

export const PLAIN_INTENT_TYPEHASH = keccak256(stringToHex("PrivateIntent(uint8 riskLevel,uint16 targetAprBps,uint16 maxDrawdownBps,uint32 rebalanceWindow)"));
export const SIGNALVAULT_DOMAIN = keccak256(stringToHex("SignalVault.PrivateIntent.v1"));

export function computePlainIntentHash(intent: PlainIntent): Hex {
  return keccak256(encodeAbiParameters(
    parseAbiParameters("bytes32,uint8,uint16,uint16,uint32"),
    [PLAIN_INTENT_TYPEHASH, intent.riskLevel, intent.targetAprBps, intent.maxDrawdownBps, intent.rebalanceWindow],
  ));
}

export function computeIntentCommitment(user: Address, intent: PlainIntent, nonce: bigint, chainId: bigint): Hex {
  return keccak256(encodeAbiParameters(
    parseAbiParameters("bytes32,address,bytes32,bytes32,uint256,uint256"),
    [SIGNALVAULT_DOMAIN, user, computePlainIntentHash(intent), intent.salt, nonce, chainId],
  ));
}
