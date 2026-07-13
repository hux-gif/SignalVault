import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import {
  assertAddressBinding,
  assertConsistentBlock,
  assertReadOnlyCommand,
  decodeStrictBool,
  decodeStrictUint256,
  evidenceTimestampUtc,
  isConservativelyWithinLimit,
  requireContractCode,
  requireEvidenceBlock,
  requireExpectedChain,
  resolveEvidenceBlock,
  selectRedemptionProbes,
  serializeEvidence,
  validateDepositPreview,
  validateRedemptionPreview,
  withRpcBoundary,
} from "./upshift-withdrawal-limit-semantics.js";

describe("Upshift withdrawal-limit evidence validation", () => {
  it.each([
    [["--block", "32788892"], 32788892n],
    [["--block=32788892"], 32788892n],
  ])("parses a pinned CLI block", (args, expected) => {
    expect(resolveEvidenceBlock(args, {})).toBe(expected);
  });

  it("supports the existing environment block and matching CLI value", () => {
    expect(resolveEvidenceBlock([], { UPSHIFT_EVIDENCE_BLOCK: "32788892" })).toBe(32788892n);
    expect(
      resolveEvidenceBlock(["--block", "32788892"], {
        UPSHIFT_EVIDENCE_BLOCK: "32788892",
      }),
    ).toBe(32788892n);
  });

  it("returns undefined only for an explicit latest exploration", () => {
    expect(resolveEvidenceBlock([], {})).toBeUndefined();
  });

  it("rejects conflicting CLI and environment blocks", () => {
    expect(() =>
      resolveEvidenceBlock(["--block", "32788892"], {
        UPSHIFT_EVIDENCE_BLOCK: "32788893",
      }),
    ).toThrow(/conflict/i);
  });

  it.each([
    "0",
    "-1",
    "1.5",
    "1e3",
    "not-a-block",
    (2n ** 256n).toString(),
  ])("rejects invalid evidence block %s", (value) => {
    expect(() => resolveEvidenceBlock(["--block", value], {})).toThrow(/block/i);
  });

  it("rejects a missing or duplicated CLI block", () => {
    expect(() => resolveEvidenceBlock(["--block"], {})).toThrow(/block/i);
    expect(() =>
      resolveEvidenceBlock(["--block=1", "--block=1"], {}),
    ).toThrow(/block/i);
  });

  it("publishes a cross-platform fixed-block package command", () => {
    const rootPackage = JSON.parse(readFileSync(resolve("../package.json"), "utf8"));
    const integrationPackage = JSON.parse(readFileSync(resolve("package.json"), "utf8"));
    expect(rootPackage.scripts["verify:upshift-limit:coston2:pinned"]).toContain(
      "verify:upshift-limit:coston2:pinned",
    );
    expect(integrationPackage.scripts["verify:upshift-limit:coston2:pinned"]).toMatch(
      /--block 32788892$/,
    );
  });

  it("documents the pinned command and records it in the evidence report", () => {
    const readme = readFileSync(resolve("../README.md"), "utf8");
    const report = JSON.parse(
      readFileSync(resolve("../reports/upshift-withdrawal-limit-semantics.json"), "utf8"),
    );
    expect(readme).toContain("npm run verify:upshift-limit:coston2:pinned");
    expect(report.commands.pinned).toBe("npm run verify:upshift-limit:coston2:pinned");
    expect(report.commands.evidenceBlock).toBe("32788892");
    expect(report.writeTransactionsBroadcast).toBe(false);
    expect(report.privateKeyLoaded).toBe(false);
  });
  it.each([
    [100n, 99n, 100n, true],
    [101n, 99n, 100n, false],
    [100n, 101n, 100n, false],
  ])(
    "applies conservative gross/net bounds",
    (gross, net, limit, expected) => {
      expect(isConservativelyWithinLimit(gross, net, limit)).toBe(expected);
    },
  );

  it("rejects a non-Coston2 chain", () => {
    expect(() => requireExpectedChain(14)).toThrow(/chain ID 114/i);
  });

  it("rejects an address without runtime bytecode", () => {
    expect(() => requireContractCode("0x", "vault")).toThrow(/no bytecode/i);
    expect(() => requireContractCode(undefined, "vault")).toThrow(/no bytecode/i);
  });

  it("rejects mismatched asset and LP bindings", () => {
    expect(() =>
      assertAddressBinding(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        "asset",
      ),
    ).toThrow(/asset.*mismatch/i);
  });

  it("strictly decodes boolean words", () => {
    expect(
      decodeStrictBool(
        "0x0000000000000000000000000000000000000000000000000000000000000001",
        "paused",
      ),
    ).toBe(true);
    expect(() => decodeStrictBool("0x02", "paused")).toThrow(/32-byte/i);
    expect(() =>
      decodeStrictBool(
        "0x0000000000000000000000000000000000000000000000000000000000000002",
        "paused",
      ),
    ).toThrow(/boolean/i);
  });

  it("strictly decodes uint256 words", () => {
    expect(
      decodeStrictUint256(
        "0x000000000000000000000000000000000000000000000000000000000000002a",
        "limit",
      ),
    ).toBe(42n);
    expect(() => decodeStrictUint256("0x2a", "limit")).toThrow(/32-byte/i);
  });

  it("rejects invalid redemption previews", () => {
    expect(() =>
      validateRedemptionPreview({ shares: 1n, gross: 0n, net: 0n }),
    ).toThrow(/gross/i);
    expect(() =>
      validateRedemptionPreview({ shares: 1n, gross: 10n, net: 11n }),
    ).toThrow(/net.*gross/i);
  });

  it("rejects a zero-share deposit preview", () => {
    expect(() =>
      validateDepositPreview({
        assets: 1n,
        expectedShares: 0n,
        referenceAmount: 1n,
      }),
    ).toThrow(/shares/i);
  });

  it("uses the complete live LP supply as the large redemption probe", () => {
    expect(selectRedemptionProbes(24_920_176n)).toEqual([
      1_000n,
      24_920n,
      24_920_176n,
    ]);
  });

  it("serializes every bigint as a decimal string", () => {
    expect(serializeEvidence({ value: 2n ** 255n, nested: [10_000n] })).toBe(
      `{"value":"${2n ** 255n}","nested":["10000"]}`,
    );
  });

  it("rejects a block without a hash", () => {
    expect(() =>
      requireEvidenceBlock({ number: 1n, hash: null, timestamp: 2n }),
    ).toThrow(/block hash/i);
  });

  it("derives the evidence timestamp from the pinned block", () => {
    expect(evidenceTimestampUtc(1_783_908_571n)).toBe(
      "2026-07-13T02:09:31.000Z",
    );
  });

  it("rejects evidence assembled from inconsistent blocks", () => {
    expect(() => assertConsistentBlock(100n, 101n, "fee")).toThrow(
      /inconsistent block/i,
    );
  });

  it("labels RPC failures instead of treating them as evidence", async () => {
    await expect(
      withRpcBoundary("asset", async () => {
        throw new Error("connection reset");
      }),
    ).rejects.toThrow(/asset RPC failure.*connection reset/i);
  });

  it.each([
    "cast send 0x1234 foo()",
    "forge script Script --broadcast",
    "eth_sendRawTransaction",
    "walletClient.writeContract",
    "privateKeyToAccount(secret)",
  ])("rejects accidental write or credential commands: %s", (command) => {
    expect(() => assertReadOnlyCommand(command)).toThrow(/read-only/i);
  });

  it.each([
    "cast call 0x1234 foo()",
    "eth_call",
    "publicClient.call",
    "publicClient.getBytecode",
  ])("accepts read-only commands: %s", (command) => {
    expect(() => assertReadOnlyCommand(command)).not.toThrow();
  });
});
