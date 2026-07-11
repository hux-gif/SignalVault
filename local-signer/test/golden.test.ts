import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import { computeIntentCommitment } from "../src/commitment.js";
import { computeResultHash } from "../src/resultHash.js";
import { teeResultDigest } from "../src/typedData.js";
import type { PlainIntent, TEEResult } from "../src/types.js";

const fixture = JSON.parse(readFileSync(new URL("../../fixtures/signer-golden.json", import.meta.url), "utf8"));

describe("cross-language signer fixture", () => {
  it("matches commitment, canonical result hash, typed-data digest, and signer", () => {
    expect(fixture.testOnly).toBe(true);
    const plainIntent: PlainIntent = { ...fixture.input.plainIntent };
    const result: TEEResult = {
      ...fixture.result,
      nonce: BigInt(fixture.result.nonce), deadline: BigInt(fixture.result.deadline),
      ftsoPriceTimestamp: BigInt(fixture.result.ftsoPriceTimestamp), chainId: BigInt(fixture.result.chainId),
    };
    expect(computeIntentCommitment(fixture.input.user, plainIntent, BigInt(fixture.input.nonce), BigInt(fixture.input.chainId))).toBe(fixture.expected.commitment);
    const { resultHash: _, ...unsigned } = result;
    expect(computeResultHash(unsigned)).toBe(fixture.expected.resultHash);
    expect(teeResultDigest(result, fixture.input.intentVerifier)).toBe(fixture.expected.typedDataDigest);
    expect(privateKeyToAccount(fixture.testPrivateKey).address).toBe(fixture.expected.signer);
  });
});
