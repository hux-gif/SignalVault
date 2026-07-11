import { getAddress, isAddress, isAddressEqual, isHex, type Address, type Hex } from "viem";
import type { AllocateRequestV2, V2ValidationContext } from "./types.js";
import { validateCoston2ResultV2 } from "./validation.js";

const UINT16_MAX = (1 << 16) - 1;
const UINT256_MAX = (1n << 256n) - 1n;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const CANONICAL_DECIMAL = /^(0|[1-9]\d*)$/;

function invalid(message: string): never {
  throw new Error(message);
}

export function parseUint16(value: unknown): number {
  let parsed: number;
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) invalid("value must be an exact uint16 integer");
    parsed = value;
  } else if (typeof value === "string" && CANONICAL_DECIMAL.test(value)) {
    const numeric = BigInt(value);
    if (numeric > BigInt(UINT16_MAX)) invalid("value exceeds uint16");
    parsed = Number(numeric);
  } else {
    invalid("value must be a canonical decimal string or exact uint16 integer");
  }
  if (parsed < 0 || parsed > UINT16_MAX) invalid("value exceeds uint16");
  return parsed;
}

export function parseUint256(value: unknown): bigint {
  if (typeof value !== "string" || !CANONICAL_DECIMAL.test(value)) {
    invalid("value must be a canonical unsigned decimal string");
  }
  const parsed = BigInt(value);
  if (parsed > UINT256_MAX) invalid("value exceeds uint256");
  return parsed;
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    invalid("request must be an object");
  }
  return value as Record<string, unknown>;
}

function address(value: unknown, field: string): Address {
  if (typeof value !== "string" || !isAddress(value) || value.toLowerCase() === ZERO_ADDRESS) {
    invalid(`${field} must be a valid non-zero address`);
  }
  return getAddress(value);
}

function bytes32(value: unknown, field: string): Hex {
  if (typeof value !== "string" || !isHex(value, { strict: true }) || value.length !== 66) {
    invalid(`${field} must be exact bytes32`);
  }
  return value;
}

function bps(value: unknown, field: string): number {
  const parsed = parseUint16(value);
  if (parsed > 10_000) invalid(`${field} must not exceed 10,000 BPS`);
  return parsed;
}

function sameHex(left: Hex, right: Hex): boolean {
  return left.toLowerCase() === right.toLowerCase();
}

export function parseAllocateRequestV2(
  value: unknown,
  context: V2ValidationContext,
): AllocateRequestV2 {
  const input = object(value);
  const user = address(input.user, "user");
  const vault = address(input.vault, "vault");
  const intentVerifier = address(input.intentVerifier, "intentVerifier");
  const intentCommitment = bytes32(input.intentCommitment, "intentCommitment");
  const capabilityProfile = bytes32(input.capabilityProfile, "capabilityProfile");
  const routerConfigHash = bytes32(input.routerConfigHash, "routerConfigHash");
  const chainId = parseUint256(input.chainId);
  const upshiftBps = bps(input.upshiftBps, "upshiftBps");
  const firelightBps = bps(input.firelightBps, "firelightBps");
  const sparkdexBps = bps(input.sparkdexBps, "sparkdexBps");
  const idleBps = bps(input.idleBps, "idleBps");

  if (!isAddressEqual(vault, context.vault)) invalid("vault does not match validation context");
  if (!isAddressEqual(intentVerifier, context.intentVerifier)) {
    invalid("intentVerifier does not match validation context");
  }
  if (chainId !== context.chainId) invalid("chainId does not match validation context");
  if (!sameHex(capabilityProfile, context.capabilityProfile)) {
    invalid("capabilityProfile does not match validation context");
  }
  if (!sameHex(routerConfigHash, context.routerConfigHash)) {
    invalid("routerConfigHash does not match validation context");
  }
  validateCoston2ResultV2({
    capabilityProfile,
    upshiftBps,
    firelightBps,
    sparkdexBps,
    idleBps,
  });

  return {
    user,
    vault,
    intentVerifier,
    intentCommitment,
    capabilityProfile,
    routerConfigHash,
    upshiftBps,
    firelightBps,
    sparkdexBps,
    idleBps,
    nonce: parseUint256(input.nonce),
    deadline: parseUint256(input.deadline),
    ftsoPriceTimestamp: parseUint256(input.ftsoPriceTimestamp),
    chainId,
    minimumPostNAV: parseUint256(input.minimumPostNAV),
    maximumRebalanceLossBps: bps(input.maximumRebalanceLossBps, "maximumRebalanceLossBps"),
    maximumPreviewDeviationBps: bps(input.maximumPreviewDeviationBps, "maximumPreviewDeviationBps"),
    allocationToleranceBps: bps(input.allocationToleranceBps, "allocationToleranceBps"),
  };
}

/** JSON response codec that preserves every integer as a decimal string. */
export function stringifyV2Response(value: unknown): string {
  return JSON.stringify(value, (_key, item: unknown) => {
    if (typeof item === "bigint") return item.toString();
    if (typeof item === "number") {
      if (!Number.isFinite(item) || !Number.isSafeInteger(item)) {
        invalid("response numbers must be finite safe integers");
      }
      return item.toString();
    }
    return item;
  });
}
