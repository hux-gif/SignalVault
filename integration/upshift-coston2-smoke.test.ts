import { describe, expect, it } from "vitest";

import {
  assertAddressMatch,
  assertAssetMatch,
  assertCoston2Chain,
  assertAllowancesZero,
  assertWithinTolerance,
  calculateFeeBps,
  calculateRoundTrip,
  deriveReportStatus,
  isAllowanceRelatedError,
  positiveDelta,
  selectSmallestPracticalAmount,
  stringifyReport,
} from "./upshift-coston2-smoke.js";

describe("Upshift Coston2 smoke helpers", () => {
  it("calculates fee basis points from gross and net output", () => {
    expect(calculateFeeBps(1_000_000n, 990_000n)).toBe(100n);
    expect(calculateFeeBps(3n, 2n)).toBe(3_333n);
  });

  it("rejects invalid fee inputs", () => {
    expect(() => calculateFeeBps(0n, 0n)).toThrow(/gross/i);
    expect(() => calculateFeeBps(100n, 101n)).toThrow(/net/i);
  });

  it("measures positive balance deltas", () => {
    expect(positiveDelta(25n, 40n, "shares")).toBe(15n);
  });

  it("rejects zero and negative balance deltas", () => {
    expect(() => positiveDelta(10n, 10n, "shares")).toThrow(/positive/i);
    expect(() => positiveDelta(11n, 10n, "assets")).toThrow(/positive/i);
  });

  it("normalizes checksummed addresses before comparison", () => {
    expect(() =>
      assertAddressMatch(
        "0x0b6A3645c240605887a5532109323A3E12273dc7",
        "0x0b6a3645c240605887a5532109323a3e12273dc7",
        "FXRP",
      ),
    ).not.toThrow();
    expect(() =>
      assertAddressMatch(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        "vault",
      ),
    ).toThrow(/vault/);
  });

  it("rejects an unexpected chain ID", () => {
    expect(() => assertCoston2Chain(114)).not.toThrow();
    expect(() => assertCoston2Chain(14)).toThrow(/114/);
  });

  it("rejects a vault asset mismatch", () => {
    expect(() =>
      assertAssetMatch(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
      ),
    ).toThrow(/asset mismatch/i);
  });

  it("serializes bigint report values without precision loss", () => {
    expect(stringifyReport({ amount: 9007199254740993n })).toContain(
      '"9007199254740993"',
    );
  });

  it("accepts only explicitly bounded preview deviations", () => {
    expect(() => assertWithinTolerance(100n, 99n, 1n, "redemption")).not.toThrow();
    expect(() => assertWithinTolerance(100n, 98n, 1n, "redemption")).toThrow(
      /redemption.*deviation/i,
    );
  });

  it("selects the smallest candidate with nonzero round-trip previews", () => {
    expect(
      selectSmallestPracticalAmount(
        [
          { amount: 1n, previewShares: 0n, redemptionGross: 0n, redemptionNet: 0n },
          { amount: 10n, previewShares: 9n, redemptionGross: 9n, redemptionNet: 8n },
          { amount: 100n, previewShares: 99n, redemptionGross: 99n, redemptionNet: 98n },
        ],
        50n,
      ).amount,
    ).toBe(10n);
  });

  it("rejects candidates that exceed the instant withdrawal limit", () => {
    expect(() =>
      selectSmallestPracticalAmount(
        [{ amount: 10n, previewShares: 9n, redemptionGross: 9n, redemptionNet: 8n }],
        5n,
      ),
    ).toThrow(/practical amount/i);
  });

  it("derives only the four Gate 2B terminal statuses", () => {
    expect(deriveReportStatus({ preflightPassed: false })).toBe("preflight_failed");
    expect(deriveReportStatus({ preflightPassed: true, depositConfirmed: false })).toBe("deposit_failed");
    expect(deriveReportStatus({ preflightPassed: true, depositConfirmed: true, redemptionConfirmed: false })).toBe("deposit_confirmed_redemption_failed");
    expect(deriveReportStatus({ preflightPassed: true, depositConfirmed: true, redemptionConfirmed: true, reconciled: true, cleanupVerified: true })).toBe("success");
    expect(deriveReportStatus({ preflightPassed: true, depositConfirmed: true, redemptionConfirmed: true, reconciled: true, cleanupVerified: false })).toBe("deposit_confirmed_redemption_failed");
  });

  it("calculates bigint-safe round-trip loss without calling it a fee", () => {
    expect(calculateRoundTrip(1_000_000n, 989_999n)).toEqual({
      absoluteLoss: 10_001n,
      roundTripLossBps: 100n,
    });
    expect(calculateRoundTrip(100n, 101n)).toEqual({
      absoluteLoss: 0n,
      roundTripLossBps: 0n,
    });
  });

  it("only treats explicit allowance failures as LP approval requirements", () => {
    expect(isAllowanceRelatedError(new Error("ERC20: insufficient allowance"))).toBe(true);
    expect(isAllowanceRelatedError(new Error("transfer amount exceeds allowance"))).toBe(true);
    expect(isAllowanceRelatedError(new Error("withdrawals paused"))).toBe(false);
    expect(isAllowanceRelatedError(new Error("execution reverted"))).toBe(false);
  });

  it("requires both final protocol allowances to be zero", () => {
    expect(() => assertAllowancesZero(0n, 0n)).not.toThrow();
    expect(() => assertAllowancesZero(1n, 0n)).toThrow(/FXRP allowance/i);
    expect(() => assertAllowancesZero(0n, 1n)).toThrow(/LP allowance/i);
  });
});
