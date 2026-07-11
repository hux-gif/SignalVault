import { describe, expect, it } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import { recoverTypedDataAddress } from "viem";
import { computeIntentCommitment } from "../src/commitment.js";
import { createAllocationService } from "../src/service.js";
import { teeResultDomain, teeResultTypes } from "../src/typedData.js";
import type { AllocateInput } from "../src/types.js";

const privateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const UINT256_MAX = (1n << 256n) - 1n;
const config = {
  privateKey, signer: privateKeyToAccount(privateKey).address, chainId: 31337n,
  vault: "0x1000000000000000000000000000000000000001", verifier: "0x2000000000000000000000000000000000000002",
  ftsoMaxAgeSeconds: 120n, resultTtlSeconds: 300n, logPlaintextIntent: false,
} as const;
const plainIntent = { riskLevel: 2 as const, targetAprBps: 900, maxDrawdownBps: 400, rebalanceWindow: 3600, salt: `0x${"44".repeat(32)}` as const };
const user = "0x3000000000000000000000000000000000000003" as const;
const base: AllocateInput = {
  user, vault: config.vault, intentVerifier: config.verifier,
  chainId: 31337n, nonce: 7n, intentCommitment: computeIntentCommitment(user, plainIntent, 7n, 31337n), plainIntent,
  ftso: { price: 100_000n, timestamp: 1_000n },
};

describe("allocation service", () => {
  it.each([
    ["vault", "0x4000000000000000000000000000000000000004"],
    ["intentVerifier", "0x4000000000000000000000000000000000000004"],
    ["intentVerifier", "0x0000000000000000000000000000000000000000"],
    ["chainId", 1n],
  ] as const)("rejects a mismatched %s", async (field, value) => {
    await expect(createAllocationService(config, () => 1_050n)({ ...base, [field]: value })).rejects.toThrow(field);
  });

  it("rejects commitment mismatch and invalid input ranges", async () => {
    const service = createAllocationService(config, () => 1_050n);
    await expect(service({ ...base, user: "not-an-address" as never })).rejects.toThrow("user");
    await expect(service({ ...base, vault: "not-an-address" as never })).rejects.toThrow("vault");
    await expect(service({ ...base, intentVerifier: "not-an-address" as never })).rejects.toThrow("intentVerifier");
    await expect(service({ ...base, chainId: 0n })).rejects.toThrow("chainId");
    await expect(service({ ...base, intentCommitment: `0x${"00".repeat(32)}` })).rejects.toThrow("commitment");
    await expect(service({ ...base, nonce: 0n })).rejects.toThrow("nonce");
    await expect(service({ ...base, plainIntent: { ...plainIntent, targetAprBps: 65_536 } })).rejects.toThrow("targetAprBps");
    await expect(service({ ...base, plainIntent: { ...plainIntent, riskLevel: 3 as never } })).rejects.toThrow("riskLevel");
    await expect(service({ ...base, plainIntent: { ...plainIntent, targetAprBps: -1 } })).rejects.toThrow("targetAprBps");
    await expect(service({ ...base, plainIntent: { ...plainIntent, maxDrawdownBps: 65_536 } })).rejects.toThrow("maxDrawdownBps");
    await expect(service({ ...base, plainIntent: { ...plainIntent, rebalanceWindow: 4_294_967_296 } })).rejects.toThrow("rebalanceWindow");
    await expect(service({ ...base, plainIntent: { ...plainIntent, salt: "0x12" } })).rejects.toThrow("salt");
    await expect(service({ ...base, intentCommitment: "0x12" })).rejects.toThrow("intentCommitment");
    await expect(service({ ...base, ftso: { ...base.ftso, timestamp: -1n } })).rejects.toThrow("ftso");
    await expect(service({ ...base, ftso: { ...base.ftso, price: 0n } })).rejects.toThrow("ftso");
    await expect(service({ ...base, ftso: { ...base.ftso, timestamp: 1_051n } })).rejects.toThrow("ftso");
    await expect(service({ ...base, chainId: UINT256_MAX + 1n })).rejects.toThrow("chainId");
    await expect(service({ ...base, nonce: UINT256_MAX + 1n })).rejects.toThrow("nonce");
    await expect(service({ ...base, ftso: { ...base.ftso, price: UINT256_MAX + 1n } })).rejects.toThrow("ftso");
    await expect(service({ ...base, ftso: { ...base.ftso, timestamp: UINT256_MAX + 1n } })).rejects.toThrow("ftso");
  });

  it("rejects a deadline that would overflow uint256", async () => {
    const overflowConfig = { ...config, resultTtlSeconds: 10n };
    await expect(createAllocationService(overflowConfig, () => UINT256_MAX - 5n)({
      ...base, ftso: { ...base.ftso, timestamp: UINT256_MAX - 6n },
    })).rejects.toThrow("deadline");
  });

  it("signs every flattened Solidity TEEResult field", async () => {
    const { result, signature } = await createAllocationService(config, () => 1_050n)(base);
    const domain = teeResultDomain(result.chainId, config.verifier);
    const recover = (message: typeof result) => recoverTypedDataAddress({ domain, types: teeResultTypes, primaryType: "TEEResult", message, signature });
    expect(await recover(result)).toBe(config.signer);
    const mutations: Array<typeof result> = [
      { ...result, user: "0x4000000000000000000000000000000000000004" },
      { ...result, vault: "0x4000000000000000000000000000000000000004" },
      { ...result, intentCommitment: `0x${"55".repeat(32)}` },
      { ...result, upshiftBps: result.upshiftBps - 1 }, { ...result, firelightBps: result.firelightBps - 1 },
      { ...result, sparkdexBps: result.sparkdexBps - 1 }, { ...result, idleBps: result.idleBps - 1 },
      { ...result, nonce: result.nonce + 1n }, { ...result, deadline: result.deadline + 1n },
      { ...result, ftsoPriceTimestamp: result.ftsoPriceTimestamp + 1n }, { ...result, chainId: result.chainId + 1n },
      { ...result, resultHash: `0x${"66".repeat(32)}` },
    ];
    for (const mutation of mutations) expect(await recover(mutation)).not.toBe(config.signer);
  });
});
