import type { AllocationV2 } from "./v2/types.js";
import type { FtsoValue, PlainIntent, RiskLevel } from "./types.js";

/**
 * Coston2-constrained allocation planner.
 *
 * Coston2 capability profile (COSTON2_CAPABILITY_PROFILE) requires
 * firelightBps === 0 and sparkdexBps === 0; only upshift + idle are allowed,
 * and they must sum to exactly 10_000.
 *
 * The mapping from private intent to public allocation is deterministic,
 * simple, and explainable:
 *   riskLevel 0 (Conservative): 30% upshift / 70% idle
 *   riskLevel 1 (Balanced):    50% upshift / 50% idle
 *   riskLevel 2 (Growth):      70% upshift / 30% idle
 *
 * Stale FTSO or low drawdown tolerance collapses upshift toward idle to
 * preserve capital. Output is always Coston2-compliant.
 */
const BASE_V2: Record<RiskLevel, Omit<AllocationV2, "firelightBps" | "sparkdexBps">> = {
  0: { upshiftBps: 3_000, idleBps: 7_000 },
  1: { upshiftBps: 5_000, idleBps: 5_000 },
  2: { upshiftBps: 7_000, idleBps: 3_000 },
};

export function allocateCoston2(
  intent: { riskLevel: RiskLevel; maxDrawdownBps: number },
  ftso: FtsoValue,
  now: bigint,
  maxAge: bigint,
): AllocationV2 {
  const base = { ...BASE_V2[intent.riskLevel] };
  let upshiftCap = base.upshiftBps;
  if (now > ftso.timestamp && now - ftso.timestamp > maxAge) upshiftCap = 0;
  if (intent.maxDrawdownBps <= 100) upshiftCap = 0;
  else if (intent.maxDrawdownBps <= 300) upshiftCap = Math.min(upshiftCap, 3_000);
  const moved = base.upshiftBps - upshiftCap;
  return {
    upshiftBps: upshiftCap,
    firelightBps: 0,
    sparkdexBps: 0,
    idleBps: base.idleBps + moved,
  };
}