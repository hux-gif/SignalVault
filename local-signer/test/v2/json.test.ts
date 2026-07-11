import { describe, expect, it } from "vitest";
import type { Address, Hex } from "viem";
import {
  parseAllocateRequestV2,
  parseUint16,
  parseUint256,
  stringifyV2Response,
} from "../../src/v2/json.js";
import type { V2ValidationContext } from "../../src/v2/types.js";

const vault = "0x0000000000000000000000000000000000001002" as Address;
const intentVerifier = "0x0000000000000000000000000000000000001003" as Address;
const capabilityProfile = `0x${"30".repeat(32)}` as Hex;
const routerConfigHash = `0x${"40".repeat(32)}` as Hex;
const validationContext: V2ValidationContext = {
  chainId: 114n,
  vault,
  intentVerifier,
  capabilityProfile,
  routerConfigHash,
};
const request = {
  user: "0x0000000000000000000000000000000000001001",
  vault,
  intentVerifier,
  intentCommitment: `0x${"20".repeat(32)}`,
  capabilityProfile,
  routerConfigHash,
  upshiftBps: 5_000,
  firelightBps: 0,
  sparkdexBps: 0,
  idleBps: 5_000,
  nonce: "17",
  deadline: "1800000000",
  ftsoPriceTimestamp: "1799999900",
  chainId: "114",
  minimumPostNAV: "999999999999999999",
  maximumRebalanceLossBps: 100,
  maximumPreviewDeviationBps: 50,
  allocationToleranceBps: 25,
};

describe("V2 JSON codec", () => {
  it("enforces integer widths before BPS semantics", () => {
    expect(parseUint16("65535")).toBe(65_535);
    expect(() => parseUint16("65536")).toThrow(/uint16/);
    expect(parseUint256(((1n << 256n) - 1n).toString())).toBe((1n << 256n) - 1n);
    expect(() => parseUint256((1n << 256n).toString())).toThrow(/uint256/);
  });

  it.each(["nonce", "deadline", "ftsoPriceTimestamp", "chainId", "minimumPostNAV"])(
    "rejects JSON numbers for uint256 field %s",
    (field) => {
      expect(() => parseAllocateRequestV2({ ...request, [field]: Number.MAX_SAFE_INTEGER + 1 }, validationContext))
        .toThrow(/decimal string/);
    },
  );

  it("parses canonical decimal strings without precision loss", () => {
    expect(parseAllocateRequestV2(request, validationContext)).toEqual({
      ...request,
      nonce: 17n,
      deadline: 1_800_000_000n,
      ftsoPriceTimestamp: 1_799_999_900n,
      chainId: 114n,
      minimumPostNAV: 999_999_999_999_999_999n,
    });
  });

  it.each(["-1", "+1", "1e3", " 1", "01", "1.0", ""])(
    "rejects non-canonical uint256 string %s",
    (value) => expect(() => parseUint256(value)).toThrow(/decimal string/),
  );

  it("rejects malformed identities, hashes, excessive BPS, and context mismatches", () => {
    expect(() => parseAllocateRequestV2({ ...request, user: "bad" }, validationContext)).toThrow(/user/);
    expect(() => parseAllocateRequestV2({ ...request, user: "0x0000000000000000000000000000000000000000" }, validationContext)).toThrow(/user/);
    expect(() => parseAllocateRequestV2({ ...request, intentCommitment: "0x12" }, validationContext)).toThrow(/intentCommitment/);
    expect(() => parseAllocateRequestV2({ ...request, upshiftBps: 65_536 }, validationContext)).toThrow(/uint16/);
    expect(() => parseAllocateRequestV2({ ...request, upshiftBps: 10_001 }, validationContext)).toThrow(/10,000/);
    expect(() => parseAllocateRequestV2({ ...request, chainId: "115" }, validationContext)).toThrow(/chainId/);
    expect(() => parseAllocateRequestV2({ ...request, vault: request.user }, validationContext)).toThrow(/vault/);
    expect(() => parseAllocateRequestV2({ ...request, intentVerifier: request.user }, validationContext)).toThrow(/intentVerifier/);
    expect(() => parseAllocateRequestV2({ ...request, capabilityProfile: request.intentCommitment }, validationContext)).toThrow(/capabilityProfile/);
    expect(() => parseAllocateRequestV2({ ...request, routerConfigHash: request.intentCommitment }, validationContext)).toThrow(/routerConfigHash/);
  });

  it("serializes every integer response field as an exact decimal string", () => {
    const encoded = stringifyV2Response({
      result: parseAllocateRequestV2(request, validationContext),
      signature: `0x${"60".repeat(65)}`,
    });
    const decoded: unknown = JSON.parse(encoded);
    expect(decoded).toEqual({
      result: Object.fromEntries(Object.entries(request).map(([key, value]) =>
        [key, typeof value === "number" ? value.toString() : value])),
      signature: `0x${"60".repeat(65)}`,
    });
  });

  it("rejects unsafe response numbers before their precision can be misrepresented", () => {
    expect(() => stringifyV2Response({ nonce: Number.MAX_SAFE_INTEGER + 1 }))
      .toThrow(/safe integer/);
  });
});
