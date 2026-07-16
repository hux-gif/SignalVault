import {
  isAddress,
  isAddressEqual,
  isHex,
  type Address,
  type Hex,
} from "viem";
import { computeIntentCommitment } from "./commitment.js";
import { allocateCoston2 } from "./allocation-v2.js";
import { computeResultHashV2 } from "./v2/resultHash.js";
import { signTEEResultV2 } from "./v2/typedData.js";
import { COSTON2_CAPABILITY_PROFILE, validateCoston2ResultV2 } from "./v2/validation.js";
import type { SignerConfig } from "./config.js";
import type { AllocateInput, PlainIntent } from "./types.js";
import type { TEEResultV2 } from "./v2/types.js";

const UINT256_MAX = (1n << 256n) - 1n;
const ZERO_BYTES32 = `0x${"00".repeat(32)}`;

export class V2RequestValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "V2RequestValidationError";
  }
}

function invalid(message: string): never {
  throw new V2RequestValidationError(message);
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

export interface V2SignerContext {
  /** Coston2 routerConfigHash, computed off-chain from the deployed V2 router. */
  routerConfigHash: Hex;
  /** Minimum acceptable post-rebalance NAV (clamped at 1 for first deposit). */
  minimumPostNAV: bigint;
  /** Mirror of RouterV2 risk configuration, used to bind limits into resultHash. */
  maximumRebalanceLossBps: number;
  maximumPreviewDeviationBps: number;
  allocationToleranceBps: number;
}

function validateInput(input: AllocateInput, ctx: V2SignerContext, currentTime: bigint): void {
  for (const [name, value] of [
    ["user", input.user],
    ["vault", input.vault],
    ["intentVerifier", input.intentVerifier],
  ] as const) {
    if (!isAddress(value)) invalid(`${name} must be a valid address`);
  }
  uint256(input.nonce, "nonce", false);
  uint256(input.chainId, "chainId", false);
  if (!isHex(input.intentCommitment, { strict: true }) || input.intentCommitment.length !== 66) {
    invalid("intentCommitment must be bytes32");
  }
  validateIntent(input.plainIntent);
  uint256(input.ftso.price, "ftso price", false);
  uint256(input.ftso.timestamp, "ftso timestamp", false);
  uint256(currentTime, "current time");
  if (input.ftso.timestamp > currentTime) invalid("ftso timestamp cannot be in the future");
  if (
    !isHex(ctx.routerConfigHash, { strict: true })
    || ctx.routerConfigHash.length !== 66
    || ctx.routerConfigHash.toLowerCase() === ZERO_BYTES32
  ) {
    invalid("routerConfigHash must be non-zero bytes32");
  }
  uint(ctx.maximumRebalanceLossBps, 65_535, "maximumRebalanceLossBps");
  uint(ctx.maximumPreviewDeviationBps, 65_535, "maximumPreviewDeviationBps");
  uint(ctx.allocationToleranceBps, 65_535, "allocationToleranceBps");
  uint256(ctx.minimumPostNAV, "minimumPostNAV");
}

export type V2AllocationService = (
  input: AllocateInput,
  ctx: V2SignerContext,
) => Promise<{ result: TEEResultV2; signature: Hex }>;

export function createV2AllocationService(
  config: SignerConfig,
  now: () => bigint = () => BigInt(Math.floor(Date.now() / 1000)),
  expectedChainId: bigint = 114n,
): V2AllocationService {
  return async (input, ctx) => {
    const currentTime = now();
    validateInput(input, ctx, currentTime);
    if (!isAddressEqual(input.vault, config.vault)) invalid("vault does not match configured vault");
    if (!isAddressEqual(input.intentVerifier, config.verifier)) {
      invalid("intentVerifier does not match configured verifier");
    }
    if (input.chainId !== config.chainId) invalid("chainId does not match configured chainId");
    if (config.chainId !== expectedChainId) {
      invalid(`V2 signer is locked to chainId=${expectedChainId}; refusing to sign for another chain`);
    }
    const commitment = computeIntentCommitment(
      input.user,
      input.plainIntent,
      input.nonce,
      input.chainId,
    );
    if (commitment.toLowerCase() !== input.intentCommitment.toLowerCase()) {
      invalid("intent commitment mismatch");
    }
    if (config.logPlaintextIntent) console.info("Development plaintext intent", input.plainIntent);
    if (currentTime - input.ftso.timestamp > config.ftsoMaxAgeSeconds) {
      invalid("ftso timestamp exceeds configured freshness window");
    }
    if (config.resultTtlSeconds <= 0n || config.resultTtlSeconds > UINT256_MAX - currentTime) {
      invalid("deadline exceeds uint256");
    }
    const allocation = allocateCoston2(
      input.plainIntent,
      input.ftso,
      currentTime,
      config.ftsoMaxAgeSeconds,
    );
    validateCoston2ResultV2({ capabilityProfile: COSTON2_CAPABILITY_PROFILE, ...allocation });
    const unsigned = {
      user: input.user as Address,
      vault: input.vault as Address,
      intentCommitment: input.intentCommitment as Hex,
      capabilityProfile: COSTON2_CAPABILITY_PROFILE,
      routerConfigHash: ctx.routerConfigHash,
      ...allocation,
      nonce: input.nonce,
      deadline: currentTime + config.resultTtlSeconds,
      ftsoPriceTimestamp: input.ftso.timestamp,
      chainId: input.chainId,
      minimumPostNAV: ctx.minimumPostNAV,
      maximumRebalanceLossBps: ctx.maximumRebalanceLossBps,
      maximumPreviewDeviationBps: ctx.maximumPreviewDeviationBps,
      allocationToleranceBps: ctx.allocationToleranceBps,
    };
    const resultHash = computeResultHashV2(unsigned);
    const result: TEEResultV2 = { ...unsigned, resultHash };
    const signature = await signTEEResultV2(result, config.verifier, config.privateKey);
    return { result, signature };
  };
}
