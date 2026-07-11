import { describe, expect, it } from "vitest";
import { encodeAbiParameters, keccak256, parseAbiParameters, stringToHex } from "viem";
import { PLAIN_INTENT_TYPEHASH, SIGNALVAULT_DOMAIN, computeIntentCommitment, computePlainIntentHash } from "../src/commitment.js";

const user = "0x3000000000000000000000000000000000000003";
const salt = `0x${"44".repeat(32)}` as const;
const intent = { riskLevel: 1 as const, targetAprBps: 800, maxDrawdownBps: 250, rebalanceWindow: 86_400, salt };

describe("private intent commitment", () => {
  it("uses the stable type hash and Solidity abi.encode semantics", () => {
    expect(PLAIN_INTENT_TYPEHASH).toBe(keccak256(stringToHex("PrivateIntent(uint8 riskLevel,uint16 targetAprBps,uint16 maxDrawdownBps,uint32 rebalanceWindow)")));
    expect(SIGNALVAULT_DOMAIN).toBe(keccak256(stringToHex("SignalVault.PrivateIntent.v1")));
    const expectedPlainHash = keccak256(encodeAbiParameters(parseAbiParameters("bytes32,uint8,uint16,uint16,uint32"), [PLAIN_INTENT_TYPEHASH, 1, 800, 250, 86_400]));
    expect(computePlainIntentHash(intent)).toBe(expectedPlainHash);
    expect(computeIntentCommitment(user, intent, 7n, 31337n)).toBe(
      keccak256(encodeAbiParameters(parseAbiParameters("bytes32,address,bytes32,bytes32,uint256,uint256"), [SIGNALVAULT_DOMAIN, user, expectedPlainHash, salt, 7n, 31337n])),
    );
  });
});
