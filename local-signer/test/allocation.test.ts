import { describe, expect, it } from "vitest";
import { allocate } from "../src/allocation.js";

const freshFtso = { price: 100_000n, timestamp: 1_000n };

describe("deterministic allocation", () => {
  it.each([
    [0, { upshiftBps: 4000, firelightBps: 2000, sparkdexBps: 0, idleBps: 4000 }],
    [1, { upshiftBps: 5000, firelightBps: 2000, sparkdexBps: 1000, idleBps: 2000 }],
    [2, { upshiftBps: 5000, firelightBps: 2000, sparkdexBps: 2500, idleBps: 500 }],
  ] as const)("uses the base allocation for risk level %i", (riskLevel, expected) => {
    expect(allocate({ riskLevel, maxDrawdownBps: 500 }, freshFtso, 1_050n, 120n)).toEqual(expected);
  });

  it("moves SparkDEX allocation to Idle when the FTSO value is stale", () => {
    expect(allocate({ riskLevel: 2, maxDrawdownBps: 500 }, freshFtso, 1_121n, 120n)).toEqual({
      upshiftBps: 5000, firelightBps: 2000, sparkdexBps: 0, idleBps: 3000,
    });
  });

  it("caps SparkDEX at 500 BPS at the 300 BPS drawdown threshold", () => {
    expect(allocate({ riskLevel: 2, maxDrawdownBps: 300 }, freshFtso, 1_000n, 120n)).toEqual({
      upshiftBps: 5000, firelightBps: 2000, sparkdexBps: 500, idleBps: 2500,
    });
  });

  it("sets SparkDEX to zero at the 100 BPS drawdown threshold", () => {
    expect(allocate({ riskLevel: 2, maxDrawdownBps: 100 }, freshFtso, 1_000n, 120n)).toEqual({
      upshiftBps: 5000, firelightBps: 2000, sparkdexBps: 0, idleBps: 3000,
    });
  });

  it("always sums to 10,000 BPS", () => {
    for (const riskLevel of [0, 1, 2] as const) {
      for (const maxDrawdownBps of [0, 100, 101, 300, 301, 10_000]) {
        const value = allocate({ riskLevel, maxDrawdownBps }, freshFtso, 2_000n, 120n);
        expect(Object.values(value).reduce((sum, bps) => sum + bps, 0)).toBe(10_000);
      }
    }
  });
});
