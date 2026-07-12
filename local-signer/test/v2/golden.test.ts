import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  encodeAbiParameters,
  keccak256,
  parseAbiParameters,
  recoverAddress,
  stringToHex,
  type Address,
  type Hex,
} from "viem";
import { computeRiskConfigurationHashV2, computeRouterConfigHashV2 } from "../../src/v2/configHash.js";
import { computeResultHashV2 } from "../../src/v2/resultHash.js";
import { teeResultV2Digest } from "../../src/v2/typedData.js";
import type { RiskConfigurationV2, RouterConfigurationV2, TEEResultV2 } from "../../src/v2/types.js";
import { COSTON2_CAPABILITY_PROFILE } from "../../src/v2/validation.js";

export const fixture = JSON.parse(readFileSync(
  new URL("../../../fixtures/tee-result-v2.json", import.meta.url), "utf8",
));

export const riskConfiguration: RiskConfigurationV2 = {
  minimumRebalanceInterval: BigInt(fixture.input.riskConfiguration.minimumRebalanceInterval),
  minimumAllocationChangeBps: Number(fixture.input.riskConfiguration.minimumAllocationChangeBps),
  maximumRebalanceLossBps: Number(fixture.input.riskConfiguration.maximumRebalanceLossBps),
  maximumPreviewDeviationBps: Number(fixture.input.riskConfiguration.maximumPreviewDeviationBps),
  allocationToleranceBps: Number(fixture.input.riskConfiguration.allocationToleranceBps),
};

export const routerConfiguration: RouterConfigurationV2 = {
  ...fixture.input.routerConfiguration,
  chainId: BigInt(fixture.input.routerConfiguration.chainId),
  version: BigInt(fixture.input.routerConfiguration.version),
};

export const result: TEEResultV2 = {
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

export const structHash = (message: TEEResultV2): Hex => keccak256(encodeAbiParameters(
  parseAbiParameters("bytes32,address,address,bytes32,bytes32,bytes32,uint16,uint16,uint16,uint16,uint256,uint256,uint256,uint256,uint256,uint16,uint16,uint16,bytes32"),
  [
    keccak256(stringToHex("TEEResultV2(address user,address vault,bytes32 intentCommitment,bytes32 capabilityProfile,bytes32 routerConfigHash,uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,uint256 minimumPostNAV,uint16 maximumRebalanceLossBps,uint16 maximumPreviewDeviationBps,uint16 allocationToleranceBps,bytes32 resultHash)")),
    message.user, message.vault, message.intentCommitment, message.capabilityProfile,
    message.routerConfigHash, message.upshiftBps, message.firelightBps, message.sparkdexBps,
    message.idleBps, message.nonce, message.deadline, message.ftsoPriceTimestamp, message.chainId,
    message.minimumPostNAV, message.maximumRebalanceLossBps, message.maximumPreviewDeviationBps,
    message.allocationToleranceBps, message.resultHash,
  ],
));

const domainSeparator = (chainId: bigint, verifier: Address): Hex => keccak256(encodeAbiParameters(
  parseAbiParameters("bytes32,bytes32,bytes32,uint256,address"),
  [
    keccak256(stringToHex("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")),
    keccak256(stringToHex("SignalVault")), keccak256(stringToHex("2")), chainId, verifier,
  ],
));

describe("V2 cross-language golden fixture", () => {
  it("recomputes every public hash and recovers the stored signer", async () => {
    expect(fixture.testOnly).toBe(true);
    expect(fixture.domains.eip712).toEqual({
      name: "SignalVault", version: "2", chainId: "31337",
      verifyingContract: fixture.input.intentVerifier,
    });
    expect(keccak256(stringToHex("SIGNALVAULT_TEE_RESULT_V2"))).toBe(fixture.domains.resultV2);
    expect(computeRiskConfigurationHashV2(riskConfiguration)).toBe(fixture.expected.riskConfigurationHash);
    expect(computeRouterConfigHashV2(routerConfiguration)).toBe(fixture.expected.routerConfigHash);
    const { resultHash: _, ...unsigned } = result;
    expect(computeResultHashV2(unsigned)).toBe(fixture.expected.resultHash);
    expect(result.resultHash).toBe(fixture.expected.resultHash);
    expect(COSTON2_CAPABILITY_PROFILE.toLowerCase()).toBe((fixture.result.capabilityProfile as string).toLowerCase());
    expect(structHash(result)).toBe(fixture.expected.structHash);
    expect(domainSeparator(result.chainId, fixture.input.intentVerifier)).toBe(fixture.expected.eip712DomainSeparator);
    expect(teeResultV2Digest(result, fixture.input.intentVerifier)).toBe(fixture.expected.typedDataDigest);
    expect(await recoverAddress({ hash: fixture.expected.typedDataDigest, signature: fixture.expected.signature })).toBe(fixture.expected.signer);
  });
});
