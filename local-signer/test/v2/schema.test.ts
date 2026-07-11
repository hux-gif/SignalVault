import { describe, expect, it } from "vitest";
import { recoverAddress, type Address, type Hex } from "viem";
import {
  computeRiskConfigurationHashV2,
  computeRouterConfigHashV2,
} from "../../src/v2/configHash.js";
import { computeResultHashV2 } from "../../src/v2/resultHash.js";
import {
  signTEEResultV2,
  teeResultV2Digest,
  teeResultV2Domain,
} from "../../src/v2/typedData.js";
import type { TEEResultV2 } from "../../src/v2/types.js";

const verifier = "0x0000000000000000000000000000000000001003" as Address;
const privateKey = `0x${"11".repeat(32)}` as Hex;
const result: TEEResultV2 = {
  user: "0x0000000000000000000000000000000000001001",
  vault: "0x0000000000000000000000000000000000001002",
  intentCommitment: `0x${"20".repeat(32)}`,
  capabilityProfile: "0x7498d31e561984b05a8781d83e877e14abc931043446e1f275b8ee0a7db7f208",
  routerConfigHash: `0x${"40".repeat(32)}`,
  upshiftBps: 5_000,
  firelightBps: 0,
  sparkdexBps: 0,
  idleBps: 5_000,
  nonce: 17n,
  deadline: 1_800_000_000n,
  ftsoPriceTimestamp: 1_799_999_900n,
  chainId: 114n,
  minimumPostNAV: 999_999_999_999_999_999n,
  maximumRebalanceLossBps: 100,
  maximumPreviewDeviationBps: 50,
  allocationToleranceBps: 25,
  resultHash: `0x${"50".repeat(32)}`,
};

function signedFieldMutations(value: TEEResultV2): TEEResultV2[] {
  return [
    { ...value, user: "0x0000000000000000000000000000000000002001" },
    { ...value, vault: "0x0000000000000000000000000000000000002002" },
    { ...value, intentCommitment: `0x${"21".repeat(32)}` },
    { ...value, capabilityProfile: `0x${"31".repeat(32)}` },
    { ...value, routerConfigHash: `0x${"41".repeat(32)}` },
    { ...value, upshiftBps: 4_999 },
    { ...value, firelightBps: 1 },
    { ...value, sparkdexBps: 1 },
    { ...value, idleBps: 4_999 },
    { ...value, nonce: 18n },
    { ...value, deadline: value.deadline + 1n },
    { ...value, ftsoPriceTimestamp: value.ftsoPriceTimestamp + 1n },
    { ...value, chainId: 115n },
    { ...value, minimumPostNAV: value.minimumPostNAV + 1n },
    { ...value, maximumRebalanceLossBps: 101 },
    { ...value, maximumPreviewDeviationBps: 51 },
    { ...value, allocationToleranceBps: 26 },
    { ...value, resultHash: `0x${"51".repeat(32)}` },
  ];
}

describe("V2 canonical schema", () => {
  it("uses the V2 domain and changes the digest for every signed field", () => {
    expect(teeResultV2Domain(114n, verifier)).toEqual({
      name: "SignalVault",
      version: "2",
      chainId: 114n,
      verifyingContract: verifier,
    });
    const digest = teeResultV2Digest(result, verifier);
    for (const mutation of signedFieldMutations(result)) {
      expect(teeResultV2Digest(mutation, verifier)).not.toBe(digest);
    }
  });

  it("signs the exact V2 typed-data digest", async () => {
    const signature = await signTEEResultV2(result, verifier, privateKey);
    expect(await recoverAddress({ hash: teeResultV2Digest(result, verifier), signature }))
      .toBe("0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A");
  });

  it.each([
    ["nonzero Firelight", { firelightBps: 1, upshiftBps: 4_999 }],
    ["nonzero SparkDEX", { sparkdexBps: 1, upshiftBps: 4_999 }],
    ["total 9,999", { upshiftBps: 4_999 }],
    ["total 10,001", { upshiftBps: 5_001 }],
    ["fractional BPS", { upshiftBps: 5_000.5, idleBps: 4_999.5 }],
    ["wrong capability profile", { capabilityProfile: `0x${"30".repeat(32)}` as Hex }],
  ])("refuses to sign a Solidity-invalid Coston2 result: %s", (_name, mutation) => {
    expect(() => signTEEResultV2({ ...result, ...mutation }, verifier, privateKey))
      .toThrow(/Coston2|BPS/);
  });

  it("binds the verifier address and invalidates the original signature under another verifier", async () => {
    const otherVerifier = "0x0000000000000000000000000000000000002003" as Address;
    const signature = await signTEEResultV2(result, verifier, privateKey);
    expect(teeResultV2Digest(result, otherVerifier)).not.toBe(teeResultV2Digest(result, verifier));
    expect(await recoverAddress({ hash: teeResultV2Digest(result, otherVerifier), signature }))
      .not.toBe("0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A");
  });

  it("changes the canonical result hash for every unsigned result field", () => {
    const { resultHash: _omitted, ...unsigned } = result;
    const hash = computeResultHashV2(unsigned);
    for (const mutation of signedFieldMutations(result).slice(0, -1)) {
      const { resultHash: _mutationHash, ...mutatedUnsigned } = mutation;
      expect(computeResultHashV2(mutatedUnsigned)).not.toBe(hash);
    }
  });

  it("binds every risk and router configuration field", () => {
    const risk = {
      minimumRebalanceInterval: 301n,
      minimumAllocationChangeBps: 75,
      maximumRebalanceLossBps: 100,
      maximumPreviewDeviationBps: 50,
      allocationToleranceBps: 25,
    };
    const riskHash = computeRiskConfigurationHashV2(risk);
    const riskMutations = [
      { ...risk, minimumRebalanceInterval: 302n },
      { ...risk, minimumAllocationChangeBps: 76 },
      { ...risk, maximumRebalanceLossBps: 101 },
      { ...risk, maximumPreviewDeviationBps: 51 },
      { ...risk, allocationToleranceBps: 26 },
    ];
    for (const mutation of riskMutations) {
      expect(computeRiskConfigurationHashV2(mutation)).not.toBe(riskHash);
    }

    const config = {
      chainId: 114n,
      vault: result.vault,
      router: "0x0000000000000000000000000000000000001003" as Address,
      asset: "0x0000000000000000000000000000000000001004" as Address,
      upshiftAdapter: "0x0000000000000000000000000000000000001005" as Address,
      idleAdapter: "0x0000000000000000000000000000000000001006" as Address,
      capabilityProfile: result.capabilityProfile,
      riskConfigurationHash: riskHash,
      version: 1n,
    };
    const configHash = computeRouterConfigHashV2(config);
    const configMutations = [
      { ...config, chainId: 115n },
      { ...config, vault: result.user },
      { ...config, router: result.user },
      { ...config, asset: result.user },
      { ...config, upshiftAdapter: result.user },
      { ...config, idleAdapter: result.user },
      { ...config, capabilityProfile: result.intentCommitment },
      { ...config, riskConfigurationHash: result.routerConfigHash },
      { ...config, version: 2n },
    ];
    for (const mutation of configMutations) {
      expect(computeRouterConfigHashV2(mutation)).not.toBe(configHash);
    }
  });
});
