import { describe, expect, it } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import { recoverTypedDataAddress } from "viem";
import { computeIntentCommitment } from "../src/commitment.js";
import { createV2AllocationService, V2RequestValidationError } from "../src/service-v2.js";
import { allocateCoston2 } from "../src/allocation-v2.js";
import { teeResultV2Domain, teeResultV2Types } from "../src/v2/typedData.js";
import { computeResultHashV2 } from "../src/v2/resultHash.js";
import { COSTON2_CAPABILITY_PROFILE, validateCoston2ResultV2 } from "../src/v2/validation.js";
import type { AllocateInput, PlainIntent } from "../src/types.js";

const privateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const UINT256_MAX = (1n << 256n) - 1n;
const config = {
  privateKey,
  signer: privateKeyToAccount(privateKey).address,
  chainId: 114n,
  vault: "0x1000000000000000000000000000000000000001",
  verifier: "0x2000000000000000000000000000000000000002",
  ftsoMaxAgeSeconds: 120n,
  resultTtlSeconds: 300n,
  logPlaintextIntent: false,
} as const;
const routerConfigHash = `0x${"ab".repeat(32)}` as const;
const ctx = {
  routerConfigHash,
  minimumPostNAV: 1n,
  maximumRebalanceLossBps: 100,
  maximumPreviewDeviationBps: 100,
  allocationToleranceBps: 100,
} as const;
const plainIntent: PlainIntent = {
  riskLevel: 2 as const,
  targetAprBps: 900,
  maxDrawdownBps: 400,
  rebalanceWindow: 3600,
  salt: `0x${"44".repeat(32)}` as const,
};
const user = "0x3000000000000000000000000000000000000003" as const;
const base: AllocateInput = {
  user,
  vault: config.vault,
  intentVerifier: config.verifier,
  chainId: 114n,
  nonce: 7n,
  intentCommitment: computeIntentCommitment(user, plainIntent, 7n, 114n),
  plainIntent,
  ftso: { price: 100_000n, timestamp: 1_000n },
};

describe("V2 allocation service", () => {
  it.each([
    ["vault", "0x4000000000000000000000000000000000000004"],
    ["intentVerifier", "0x4000000000000000000000000000000000000004"],
    ["chainId", 31337n],
  ] as const)("rejects a mismatched %s", async (field, value) => {
    await expect(
      createV2AllocationService(config, () => 1_050n)({ ...base, [field]: value }, ctx),
    ).rejects.toBeInstanceOf(V2RequestValidationError);
  });

  it("rejects non-Coston2 chainId", async () => {
    const otherChain = { ...config, chainId: 31337n };
    await expect(
      createV2AllocationService(otherChain, () => 1_050n)(base, ctx),
    ).rejects.toBeInstanceOf(V2RequestValidationError);
  });

  it("rejects stale ftso timestamp", async () => {
    await expect(
      createV2AllocationService(config, () => 5_000n)({ ...base, ftso: { ...base.ftso, timestamp: 1_000n } }, ctx),
    ).rejects.toBeInstanceOf(V2RequestValidationError);
  });

  it("rejects zero routerConfigHash", async () => {
    await expect(
      createV2AllocationService(config, () => 1_050n)(base, { ...ctx, routerConfigHash: `0x${"00".repeat(32)}` }),
    ).rejects.toBeInstanceOf(V2RequestValidationError);
  });

  it("emits only upshift + idle (Coston2 profile)", async () => {
    const { result } = await createV2AllocationService(config, () => 1_050n)(base, ctx);
    expect(result.firelightBps).toBe(0);
    expect(result.sparkdexBps).toBe(0);
    expect(result.upshiftBps + result.idleBps).toBe(10_000);
    validateCoston2ResultV2({
      capabilityProfile: COSTON2_CAPABILITY_PROFILE,
      upshiftBps: result.upshiftBps,
      firelightBps: result.firelightBps,
      sparkdexBps: result.sparkdexBps,
      idleBps: result.idleBps,
    });
  });

  it("computes canonical resultHash matching v2/resultHash.ts", async () => {
    const { result } = await createV2AllocationService(config, () => 1_050n)(base, ctx);
    const { resultHash: _omit, ...unsigned } = result;
    expect(result.resultHash.toLowerCase()).toBe(computeResultHashV2(unsigned).toLowerCase());
  });

  it("signs every flattened V2 TEEResult field", async () => {
    const { result, signature } = await createV2AllocationService(config, () => 1_050n)(base, ctx);
    const domain = teeResultV2Domain(result.chainId, config.verifier);
    const recover = (message: typeof result) =>
      recoverTypedDataAddress({
        domain,
        types: teeResultV2Types,
        primaryType: "TEEResultV2",
        message,
        signature,
      });
    expect(await recover(result)).toBe(config.signer);
    const mutations: Array<typeof result> = [
      { ...result, user: "0x4000000000000000000000000000000000000004" },
      { ...result, vault: "0x4000000000000000000000000000000000000004" },
      { ...result, intentCommitment: `0x${"55".repeat(32)}` },
      { ...result, capabilityProfile: `0x${"66".repeat(32)}` },
      { ...result, routerConfigHash: `0x${"77".repeat(32)}` },
      { ...result, upshiftBps: result.upshiftBps - 1 },
      { ...result, firelightBps: 1 },
      { ...result, sparkdexBps: 1 },
      { ...result, idleBps: result.idleBps - 1 },
      { ...result, nonce: result.nonce + 1n },
      { ...result, deadline: result.deadline + 1n },
      { ...result, ftsoPriceTimestamp: result.ftsoPriceTimestamp + 1n },
      { ...result, chainId: result.chainId + 1n },
      { ...result, minimumPostNAV: result.minimumPostNAV + 1n },
      { ...result, maximumRebalanceLossBps: result.maximumRebalanceLossBps + 1 },
      { ...result, maximumPreviewDeviationBps: result.maximumPreviewDeviationBps + 1 },
      { ...result, allocationToleranceBps: result.allocationToleranceBps + 1 },
      { ...result, resultHash: `0x${"88".repeat(32)}` },
    ];
    for (const mutation of mutations) {
      expect(await recover(mutation)).not.toBe(config.signer);
    }
  });
});

describe("allocateCoston2 planner", () => {
  const freshFtso = { price: 100_000n, timestamp: 1_000n };
  it("emits Coston2-compliant allocations for every risk level", () => {
    for (const riskLevel of [0, 1, 2] as const) {
      const a = allocateCoston2({ riskLevel, maxDrawdownBps: 500 }, freshFtso, 1_050n, 120n);
      expect(a.firelightBps).toBe(0);
      expect(a.sparkdexBps).toBe(0);
      expect(a.upshiftBps + a.idleBps).toBe(10_000);
    }
  });
  it("collapses upshift to idle on stale FTSO", () => {
    const a = allocateCoston2({ riskLevel: 2, maxDrawdownBps: 500 }, freshFtso, 5_000n, 120n);
    expect(a.upshiftBps).toBe(0);
    expect(a.idleBps).toBe(10_000);
  });
  it("caps upshift at 3000 BPS at the 300 BPS drawdown threshold", () => {
    const a = allocateCoston2({ riskLevel: 2, maxDrawdownBps: 300 }, freshFtso, 1_000n, 120n);
    expect(a.upshiftBps).toBeLessThanOrEqual(3_000);
  });
  it("always sums to 10,000 BPS", () => {
    for (const riskLevel of [0, 1, 2] as const) {
      for (const maxDrawdownBps of [0, 100, 101, 300, 301, 10_000]) {
        const value = allocateCoston2({ riskLevel, maxDrawdownBps }, freshFtso, 2_000n, 120n);
        expect(value.firelightBps).toBe(0);
        expect(value.sparkdexBps).toBe(0);
        expect(value.upshiftBps + value.idleBps).toBe(10_000);
      }
    }
  });
});