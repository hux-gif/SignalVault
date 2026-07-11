import type { Allocation, FtsoValue, RiskLevel } from "./types.js";

const BASE: Record<RiskLevel, Allocation> = {
  0: { upshiftBps: 4000, firelightBps: 2000, sparkdexBps: 0, idleBps: 4000 },
  1: { upshiftBps: 5000, firelightBps: 2000, sparkdexBps: 1000, idleBps: 2000 },
  2: { upshiftBps: 5000, firelightBps: 2000, sparkdexBps: 2500, idleBps: 500 },
};

export function allocate(
  intent: { riskLevel: RiskLevel; maxDrawdownBps: number },
  ftso: FtsoValue,
  now: bigint,
  maxAge: bigint,
): Allocation {
  const result = { ...BASE[intent.riskLevel] };
  let sparkdexCap = result.sparkdexBps;
  if (now > ftso.timestamp && now - ftso.timestamp > maxAge) sparkdexCap = 0;
  if (intent.maxDrawdownBps <= 100) sparkdexCap = 0;
  else if (intent.maxDrawdownBps <= 300) sparkdexCap = Math.min(sparkdexCap, 500);
  result.idleBps += result.sparkdexBps - sparkdexCap;
  result.sparkdexBps = sparkdexCap;
  return result;
}
