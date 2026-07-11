import type { Hex } from "viem";
import type { AllocationV2 } from "./types.js";

const COSTON2_CAPABILITY_PROFILE: Hex =
  "0x7498d31e561984b05a8781d83e877e14abc931043446e1f275b8ee0a7db7f208";

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
