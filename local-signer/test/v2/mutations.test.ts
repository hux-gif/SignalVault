import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { encodeAbiParameters, keccak256, parseAbiParameters, recoverAddress, stringToHex, type Address, type Hex } from "viem";
import { computeResultHashV2 } from "../../src/v2/resultHash.js";
import { teeResultV2Digest } from "../../src/v2/typedData.js";
import type { TEEResultV2 } from "../../src/v2/types.js";

const fixture = JSON.parse(readFileSync(
  new URL("../../../fixtures/tee-result-v2.json", import.meta.url), "utf8",
));
const result: TEEResultV2 = {
  ...fixture.result,
  upshiftBps: Number(fixture.result.upshiftBps),
  firelightBps: Number(fixture.result.firelightBps),
  sparkdexBps: Number(fixture.result.sparkdexBps),
  idleBps: Number(fixture.result.idleBps),
  nonce: BigInt(fixture.result.nonce),
  deadline: BigInt(fixture.result.deadline),
  ftsoPriceTimestamp: BigInt(fixture.result.ftsoPriceTimestamp),
  chainId: BigInt(fixture.result.chainId),
  minimumPostNAV: BigInt(fixture.result.minimumPostNAV),
  maximumRebalanceLossBps: Number(fixture.result.maximumRebalanceLossBps),
  maximumPreviewDeviationBps: Number(fixture.result.maximumPreviewDeviationBps),
  allocationToleranceBps: Number(fixture.result.allocationToleranceBps),
};
const differentAddress = (address: Address): Address =>
  address.toLowerCase() === "0x9999999999999999999999999999999999999999"
    ? "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    : "0x9999999999999999999999999999999999999999";

const anotherHash = (hash: Hex): Hex => hash === `0x${"99".repeat(32)}` ? `0x${"98".repeat(32)}` : `0x${"99".repeat(32)}`;
const mutations: [string, (value: TEEResultV2) => TEEResultV2][] = [
  ["user", (v) => ({ ...v, user: differentAddress(v.user) })],
  ["vault", (v) => ({ ...v, vault: differentAddress(v.vault) })],
  ["intentCommitment", (v) => ({ ...v, intentCommitment: anotherHash(v.intentCommitment) })],
  ["capabilityProfile", (v) => ({ ...v, capabilityProfile: anotherHash(v.capabilityProfile) })],
  ["routerConfigHash", (v) => ({ ...v, routerConfigHash: anotherHash(v.routerConfigHash) })],
  ["upshiftBps", (v) => ({ ...v, upshiftBps: v.upshiftBps + 1 })],
  ["firelightBps", (v) => ({ ...v, firelightBps: v.firelightBps + 1 })],
  ["sparkdexBps", (v) => ({ ...v, sparkdexBps: v.sparkdexBps + 1 })],
  ["idleBps", (v) => ({ ...v, idleBps: v.idleBps + 1 })],
  ["nonce", (v) => ({ ...v, nonce: v.nonce + 1n })],
  ["deadline", (v) => ({ ...v, deadline: v.deadline + 1n })],
  ["ftsoPriceTimestamp", (v) => ({ ...v, ftsoPriceTimestamp: v.ftsoPriceTimestamp + 1n })],
  ["chainId", (v) => ({ ...v, chainId: v.chainId + 1n })],
  ["minimumPostNAV", (v) => ({ ...v, minimumPostNAV: v.minimumPostNAV + 1n })],
  ["maximumRebalanceLossBps", (v) => ({ ...v, maximumRebalanceLossBps: v.maximumRebalanceLossBps + 1 })],
  ["maximumPreviewDeviationBps", (v) => ({ ...v, maximumPreviewDeviationBps: v.maximumPreviewDeviationBps + 1 })],
  ["allocationToleranceBps", (v) => ({ ...v, allocationToleranceBps: v.allocationToleranceBps + 1 })],
  ["resultHash", (v) => ({ ...v, resultHash: anotherHash(v.resultHash) })],
];

describe("V2 signed-field mutation matrix", () => {
  it.each(mutations)("rejects the original signature after mutating %s", async (_field, mutate) => {
    const mutated = mutate(result);
    const recovered = await recoverAddress({
      hash: teeResultV2Digest(mutated, fixture.input.intentVerifier),
      signature: fixture.expected.signature,
    });
    const { resultHash: _, ...unsigned } = mutated;
    expect(recovered === fixture.expected.signer && computeResultHashV2(unsigned) === mutated.resultHash).toBe(false);
  });

  it("separates V2 from V1 domains, verifier addresses, V1 canonical hashes, and result domains", async () => {
    expect(await recoverAddress({ hash: fixture.expected.domainVersion1Digest, signature: fixture.expected.domainVersion1Signature })).toBe(fixture.expected.signer);
    expect(await recoverAddress({ hash: fixture.expected.typedDataDigest, signature: fixture.expected.domainVersion1Signature })).not.toBe(fixture.expected.signer);
    expect(fixture.expected.domainVersion1Digest).not.toBe(fixture.expected.typedDataDigest);
    const v1EquivalentResultHash = keccak256(encodeAbiParameters(
      parseAbiParameters("address,address,bytes32,uint16,uint16,uint16,uint16,uint256,uint256,uint256,uint256"),
      [result.user, result.vault, result.intentCommitment, result.upshiftBps, result.firelightBps,
        result.sparkdexBps, result.idleBps, result.nonce, result.deadline,
        result.ftsoPriceTimestamp, result.chainId],
    ));
    expect(v1EquivalentResultHash).toBe(fixture.expected.v1EquivalentResultHash);
    expect(result.resultHash).not.toBe(v1EquivalentResultHash);
    const wrongVerifierDigest = teeResultV2Digest(result, differentAddress(fixture.input.intentVerifier));
    expect(wrongVerifierDigest).not.toBe(fixture.expected.typedDataDigest);
    expect(await recoverAddress({ hash: wrongVerifierDigest, signature: fixture.expected.signature })).not.toBe(fixture.expected.signer);
    const replacementDomainHash = keccak256(encodeAbiParameters(
      parseAbiParameters("bytes32,address,address,bytes32,bytes32,bytes32,uint16,uint16,uint16,uint16,uint256,uint256,uint256,uint256,uint256,uint16,uint16,uint16"),
      [
        keccak256(stringToHex("SIGNALVAULT_TEE_RESULT_V2_REPLACED")), result.user, result.vault,
        result.intentCommitment, result.capabilityProfile, result.routerConfigHash, result.upshiftBps,
        result.firelightBps, result.sparkdexBps, result.idleBps, result.nonce, result.deadline,
        result.ftsoPriceTimestamp, result.chainId, result.minimumPostNAV, result.maximumRebalanceLossBps,
        result.maximumPreviewDeviationBps, result.allocationToleranceBps,
      ],
    ));
    expect(replacementDomainHash).not.toBe(result.resultHash);
  });
});
