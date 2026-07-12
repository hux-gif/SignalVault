import { isAddress, isHex, keccak256, stringToHex, type Address, type Hex } from "viem";
import { computeResultHashV2 } from "./resultHash.js";
import type { AllocationV2, TEEResultV2 } from "./types.js";

export const COSTON2_UPSHIFT_IDLE_PROFILE_NAME = "SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1";
export const COSTON2_CAPABILITY_PROFILE: Hex = keccak256(
  stringToHex(COSTON2_UPSHIFT_IDLE_PROFILE_NAME),
);
const ZERO_ADDRESS: Address = "0x0000000000000000000000000000000000000000";
const ZERO_BYTES32: Hex = `0x${"00".repeat(32)}`;

export interface Coston2ResultFieldsV2 extends AllocationV2 {
  capabilityProfile: Hex;
}

function validateBps(value: number, field: string): void {
  if (!Number.isSafeInteger(value) || value < 0 || value > 10_000) {
    throw new Error(`${field} must be an exact integer BPS value from 0 to 10,000`);
  }
}

/** Enforces the allocation semantics accepted by IntentVerifierV2. */
export function validateCoston2ResultV2(value: Coston2ResultFieldsV2): void {
  validateBps(value.upshiftBps, "upshiftBps");
  validateBps(value.firelightBps, "firelightBps");
  validateBps(value.sparkdexBps, "sparkdexBps");
  validateBps(value.idleBps, "idleBps");

  if (value.capabilityProfile.toLowerCase() !== COSTON2_CAPABILITY_PROFILE) {
    throw new Error("capabilityProfile must be the exact Coston2 capability profile");
  }
  if (value.firelightBps !== 0) {
    throw new Error("Coston2 allocation requires firelightBps to equal 0");
  }
  if (value.sparkdexBps !== 0) {
    throw new Error("Coston2 allocation requires sparkdexBps to equal 0");
  }
  if (value.upshiftBps + value.idleBps !== 10_000) {
    throw new Error("Coston2 allocation requires upshiftBps plus idleBps to equal 10,000");
  }
}

function validateNonZeroAddress(value: Address, field: string): void {
  if (!isAddress(value) || value.toLowerCase() === ZERO_ADDRESS) {
    throw new Error(`${field} must be a valid non-zero address`);
  }
}

function validateNonZeroBytes32(value: Hex, field: string): void {
  if (
    typeof value !== "string"
    || !isHex(value, { strict: true })
    || value.length !== 66
    || value.toLowerCase() === ZERO_BYTES32
  ) {
    throw new Error(`${field} must be exact non-zero bytes32`);
  }
}

/** Validates every invariant required before a V2 result is safe to sign. */
export function validateSignableTEEResultV2(value: TEEResultV2): void {
  validateCoston2ResultV2(value);
  validateNonZeroAddress(value.user, "user");
  validateNonZeroAddress(value.vault, "vault");
  validateNonZeroBytes32(value.routerConfigHash, "routerConfigHash");

  const { resultHash, ...resultFields } = value;
  if (resultHash.toLowerCase() !== computeResultHashV2(resultFields).toLowerCase()) {
    throw new Error("resultHash must equal the canonical V2 result hash");
  }
}
