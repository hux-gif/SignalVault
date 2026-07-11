import { describe, expect, it } from "vitest";

import {
  analyzePreview,
  interpretFeeConfiguration,
  selectLiveCalibrationAmount,
} from "./upshift-coston2-economics.js";

describe("Upshift Coston2 economics helpers", () => {
  it("calculates BPS without losing small-amount integer effects", () => {
    expect(analyzePreview(10n, 9n, 9n, 9n)).toMatchObject({
      roundingLoss: 1n,
      explicitFeeAmount: 0n,
      totalLoss: 1n,
      totalLossBps: 1_000n,
      impliedRedemptionFeeBps: 0n,
      dominatedByOneUnitRounding: true,
    });
  });

  it("separates deposit/share rounding from the explicit redemption fee", () => {
    expect(analyzePreview(10_000n, 9_965n, 9_999n, 9_950n)).toEqual({
      inputAssets: 10_000n,
      previewedShares: 9_965n,
      previewedGrossAssets: 9_999n,
      previewedNetAssets: 9_950n,
      roundingLoss: 1n,
      explicitFeeAmount: 49n,
      totalLoss: 50n,
      totalLossBps: 50n,
      impliedRedemptionFeeBps: 49n,
      dominatedByOneUnitRounding: false,
    });
  });

  it("rejects zero previews", () => {
    expect(() => analyzePreview(10n, 0n, 0n, 0n)).toThrow(/nonzero/i);
    expect(() => analyzePreview(10n, 9n, 9n, 0n)).toThrow(/nonzero/i);
  });

  it("proves the fee denominator against every preview sample", () => {
    expect(
      interpretFeeConfiguration(50n, 10_000n, [
        { gross: 999n, net: 995n },
        { gross: 9_999n, net: 9_950n },
        { gross: 99_999n, net: 99_500n },
      ]),
    ).toEqual({ rawFee: 50n, denominator: 10_000n, interpretedFeeBps: 50n });
    expect(() =>
      interpretFeeConfiguration(50n, 1_000n, [{ gross: 9_999n, net: 9_950n }]),
    ).toThrow(/does not match/i);
  });

  it("chooses 0.01 FTestXRP when it is meaningful and under all limits", () => {
    const selected = selectLiveCalibrationAmount(
      10_000_000n,
      10_000_000_000n,
      [
        analyzePreview(10_000n, 9_965n, 9_999n, 9_950n),
        analyzePreview(100_000n, 99_658n, 100_007n, 99_507n),
      ],
    );
    expect(selected.inputAssets).toBe(10_000n);
  });

  it("uses 0.1 only when 0.01 remains rounding dominated", () => {
    const selected = selectLiveCalibrationAmount(
      10_000_000n,
      10_000_000_000n,
      [
        analyzePreview(10_000n, 9_999n, 9_999n, 9_999n),
        analyzePreview(100_000n, 99_658n, 100_007n, 99_507n),
      ],
    );
    expect(selected.inputAssets).toBe(100_000n);
  });

  it("enforces the maximum ten-percent wallet rule", () => {
    expect(() =>
      selectLiveCalibrationAmount(
        50_000n,
        10_000_000_000n,
        [analyzePreview(10_000n, 9_965n, 9_999n, 9_950n)],
      ),
    ).toThrow(/10%/i);
  });
});
