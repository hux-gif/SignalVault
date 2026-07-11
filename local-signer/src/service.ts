import { isAddress, isAddressEqual, isHex, type Address, type Hex } from "viem";
import { allocate } from "./allocation.js";
import { computeIntentCommitment } from "./commitment.js";
import { computeResultHash } from "./resultHash.js";
import { signTEEResult } from "./typedData.js";
import type { SignerConfig } from "./config.js";
import type { AllocateInput, AllocateResponse, PlainIntent } from "./types.js";

const UINT256_MAX = (1n << 256n) - 1n;

export class RequestValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RequestValidationError";
  }
}

function invalid(message: string): never {
  throw new RequestValidationError(message);
}

function uint(value: number, max: number, name: string): void {
  if (!Number.isSafeInteger(value) || value < 0 || value > max) invalid(`${name} is out of range`);
}

function uint256(value: bigint, name: string, allowZero = true): void {
  if (value < 0n || value > UINT256_MAX || (!allowZero && value === 0n)) invalid(`${name} is out of uint256 range`);
}

function validateIntent(intent: PlainIntent): void {
  uint(intent.riskLevel, 2, "riskLevel");
  uint(intent.targetAprBps, 65_535, "targetAprBps");
  uint(intent.maxDrawdownBps, 65_535, "maxDrawdownBps");
  uint(intent.rebalanceWindow, 4_294_967_295, "rebalanceWindow");
  if (!isHex(intent.salt, { strict: true }) || intent.salt.length !== 66) invalid("salt must be bytes32");
}

function validateInput(input: AllocateInput, currentTime: bigint): void {
  for (const [name, value] of [["user", input.user], ["vault", input.vault], ["intentVerifier", input.intentVerifier]] as const) {
    if (!isAddress(value)) invalid(`${name} must be a valid address`);
  }
  uint256(input.nonce, "nonce", false);
  uint256(input.chainId, "chainId", false);
  if (!isHex(input.intentCommitment, { strict: true }) || input.intentCommitment.length !== 66) invalid("intentCommitment must be bytes32");
  validateIntent(input.plainIntent);
  uint256(input.ftso.price, "ftso price", false);
  uint256(input.ftso.timestamp, "ftso timestamp", false);
  uint256(currentTime, "current time");
  if (input.ftso.timestamp > currentTime) invalid("ftso timestamp cannot be in the future");
}

export type AllocationService = (input: AllocateInput) => Promise<AllocateResponse>;

export function createAllocationService(config: SignerConfig, now: () => bigint = () => BigInt(Math.floor(Date.now() / 1000))): AllocationService {
  return async (input) => {
    const currentTime = now();
    validateInput(input, currentTime);
    if (!isAddressEqual(input.vault, config.vault)) invalid("vault does not match configured vault");
    if (!isAddressEqual(input.intentVerifier, config.verifier)) invalid("intentVerifier does not match configured verifier");
    if (input.chainId !== config.chainId) invalid("chainId does not match configured chainId");
    const commitment = computeIntentCommitment(input.user, input.plainIntent, input.nonce, input.chainId);
    if (commitment.toLowerCase() !== input.intentCommitment.toLowerCase()) invalid("intent commitment mismatch");
    if (config.logPlaintextIntent) console.info("Development plaintext intent", input.plainIntent);
    const allocation = allocate(input.plainIntent, input.ftso, currentTime, config.ftsoMaxAgeSeconds);
    if (config.resultTtlSeconds <= 0n || config.resultTtlSeconds > UINT256_MAX - currentTime) invalid("deadline exceeds uint256");
    const unsigned = {
      user: input.user as Address, vault: input.vault as Address, intentCommitment: input.intentCommitment as Hex,
      ...allocation, nonce: input.nonce, deadline: currentTime + config.resultTtlSeconds,
      ftsoPriceTimestamp: input.ftso.timestamp, chainId: input.chainId,
    };
    const result = { ...unsigned, resultHash: computeResultHash(unsigned) };
    return { result, signature: await signTEEResult(result, config.verifier, config.privateKey) };
  };
}
