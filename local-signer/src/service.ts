import { isAddress, isAddressEqual, isHex, type Address, type Hex } from "viem";
import { allocate } from "./allocation.js";
import { computeIntentCommitment } from "./commitment.js";
import { computeResultHash } from "./resultHash.js";
import { signTEEResult } from "./typedData.js";
import type { SignerConfig } from "./config.js";
import type { AllocateInput, AllocateResponse, PlainIntent } from "./types.js";

function uint(value: number, max: number, name: string): void {
  if (!Number.isSafeInteger(value) || value < 0 || value > max) throw new Error(`${name} is out of range`);
}

function validateIntent(intent: PlainIntent): void {
  uint(intent.riskLevel, 2, "riskLevel");
  uint(intent.targetAprBps, 65_535, "targetAprBps");
  uint(intent.maxDrawdownBps, 65_535, "maxDrawdownBps");
  uint(intent.rebalanceWindow, 4_294_967_295, "rebalanceWindow");
  if (!isHex(intent.salt, { strict: true }) || intent.salt.length !== 66) throw new Error("salt must be bytes32");
}

function validateInput(input: AllocateInput, currentTime: bigint): void {
  for (const [name, value] of [["user", input.user], ["vault", input.vault], ["intentVerifier", input.intentVerifier]] as const) {
    if (!isAddress(value)) throw new Error(`${name} must be a valid address`);
  }
  if (input.nonce <= 0n) throw new Error("nonce must be positive");
  if (input.chainId <= 0n) throw new Error("chainId must be positive");
  if (!isHex(input.intentCommitment, { strict: true }) || input.intentCommitment.length !== 66) throw new Error("intentCommitment must be bytes32");
  validateIntent(input.plainIntent);
  if (input.ftso.price <= 0n || input.ftso.timestamp <= 0n || input.ftso.timestamp > currentTime) {
    throw new Error("ftso price and timestamp must be positive and timestamp cannot be in the future");
  }
}

export type AllocationService = (input: AllocateInput) => Promise<AllocateResponse>;

export function createAllocationService(config: SignerConfig, now: () => bigint = () => BigInt(Math.floor(Date.now() / 1000))): AllocationService {
  return async (input) => {
    const currentTime = now();
    validateInput(input, currentTime);
    if (!isAddressEqual(input.vault, config.vault)) throw new Error("vault does not match configured vault");
    if (!isAddressEqual(input.intentVerifier, config.verifier)) throw new Error("intentVerifier does not match configured verifier");
    if (input.chainId !== config.chainId) throw new Error("chainId does not match configured chainId");
    const commitment = computeIntentCommitment(input.user, input.plainIntent, input.nonce, input.chainId);
    if (commitment.toLowerCase() !== input.intentCommitment.toLowerCase()) throw new Error("intent commitment mismatch");
    if (config.logPlaintextIntent) console.info("Development plaintext intent", input.plainIntent);
    const allocation = allocate(input.plainIntent, input.ftso, currentTime, config.ftsoMaxAgeSeconds);
    const unsigned = {
      user: input.user as Address, vault: input.vault as Address, intentCommitment: input.intentCommitment as Hex,
      ...allocation, nonce: input.nonce, deadline: currentTime + config.resultTtlSeconds,
      ftsoPriceTimestamp: input.ftso.timestamp, chainId: input.chainId,
    };
    const result = { ...unsigned, resultHash: computeResultHash(unsigned) };
    return { result, signature: await signTEEResult(result, config.verifier, config.privateKey) };
  };
}
