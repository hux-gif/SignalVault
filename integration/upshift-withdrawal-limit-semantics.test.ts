import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  decodeFunctionData,
  encodeFunctionResult,
  getAddress,
  parseAbi,
  toHex,
  type Hex,
} from "viem";
import * as evidenceModule from "./upshift-withdrawal-limit-semantics.js";

import {
  assertAddressBinding,
  assertConsistentBlock,
  assertReadOnlyCommand,
  createReadOnlyRpcGateway,
  decodeStrictBool,
  decodeStrictUint256,
  evidenceTimestampUtc,
  isConservativelyWithinLimit,
  requireContractCode,
  requireEvidenceBlock,
  requireExpectedChain,
  READ_ONLY_RPC_METHODS,
  resolveEvidenceBlock,
  runEvidenceCommand,
  selectRedemptionProbes,
  serializeEvidence,
  validateDepositPreview,
  validateRedemptionPreview,
  withRpcBoundary,
  type RpcRequester,
} from "./upshift-withdrawal-limit-semantics.js";

const FIXTURE_BLOCK = 32_788_892n;
const FIXTURE_TIMESTAMP = 1_783_908_571n;
const FIXTURE_BLOCK_HASH = `0x${"ab".repeat(32)}`;
const FIXTURE_IMPLEMENTATION = getAddress(
  "0x94c1851B1631769147B62f8370E851682361CEe2",
);
const ZERO_HASH = `0x${"00".repeat(32)}`;
const ZERO_BLOOM = `0x${"00".repeat(256)}`;

const fixtureTokenAbi = parseAbi([
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function totalSupply() view returns (uint256)",
]);

const fixtureUpshiftAbi = parseAbi([
  "function asset() view returns (address)",
  "function lpTokenAddress() view returns (address)",
  "function previewDeposit(address assetIn,uint256 amountIn) view returns (uint256 shares,uint256 amountInReferenceTokens)",
  "function previewRedemption(uint256 shares,bool isInstant) view returns (uint256 assetsAmount,uint256 assetsAfterFee)",
  "function withdrawalsPaused() view returns (bool)",
  "function maxWithdrawalAmount() view returns (uint256)",
  "function instantRedemptionFee() view returns (uint256)",
]);

function requireFixtureHex(value: unknown, label: string): Hex {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]*$/.test(value)) {
    throw new Error(`${label} is not hex`);
  }
  return value as Hex;
}

function expectPinnedBlockParameter(value: unknown, label: string): void {
  if (value !== toHex(FIXTURE_BLOCK)) {
    throw new Error(`${label} did not use the pinned block`);
  }
}

function createFixtureRpc(recordedMethods: string[] = []): RpcRequester {
  return {
    async request({ method, params = [] }): Promise<unknown> {
      recordedMethods.push(method);
      if (method === "eth_chainId") return toHex(114);
      if (method === "eth_getBlockByNumber") {
        expectPinnedBlockParameter(params[0], method);
        return {
          number: toHex(FIXTURE_BLOCK),
          hash: FIXTURE_BLOCK_HASH,
          parentHash: ZERO_HASH,
          nonce: "0x0000000000000000",
          sha3Uncles: ZERO_HASH,
          logsBloom: ZERO_BLOOM,
          transactionsRoot: ZERO_HASH,
          stateRoot: ZERO_HASH,
          receiptsRoot: ZERO_HASH,
          miner: "0x0000000000000000000000000000000000000000",
          difficulty: "0x0",
          totalDifficulty: "0x0",
          extraData: "0x",
          size: "0x1",
          gasLimit: "0x1c9c380",
          gasUsed: "0x0",
          timestamp: toHex(FIXTURE_TIMESTAMP),
          transactions: [],
          uncles: [],
          baseFeePerGas: "0x0",
          mixHash: ZERO_HASH,
        };
      }
      if (method === "eth_getCode") {
        expectPinnedBlockParameter(params[1], method);
        return "0x6000";
      }
      if (method === "eth_getStorageAt") {
        expectPinnedBlockParameter(params[2], method);
        return `0x${"00".repeat(12)}${FIXTURE_IMPLEMENTATION.slice(2).toLowerCase()}`;
      }
      if (method !== "eth_call") {
        throw new Error(`Fixture received unexpected RPC method ${method}`);
      }

      expectPinnedBlockParameter(params[1], method);
      const rawCall = params[0];
      if (typeof rawCall !== "object" || rawCall === null) {
        throw new Error("eth_call request is malformed");
      }
      const call = rawCall as { data?: unknown; to?: unknown };
      const data = requireFixtureHex(call.data, "eth_call data");
      if (typeof call.to !== "string") throw new Error("eth_call target is missing");
      const target = getAddress(call.to);

      if (target === evidenceModule.OFFICIAL_UPSHIFT_VAULT) {
        const decoded = decodeFunctionData({ abi: fixtureUpshiftAbi, data });
        switch (decoded.functionName) {
          case "asset":
            return encodeFunctionResult({
              abi: fixtureUpshiftAbi,
              functionName: "asset",
              result: evidenceModule.OFFICIAL_FXRP,
            });
          case "lpTokenAddress":
            return encodeFunctionResult({
              abi: fixtureUpshiftAbi,
              functionName: "lpTokenAddress",
              result: evidenceModule.OFFICIAL_UPSHIFT_LP,
            });
          case "withdrawalsPaused":
            return encodeFunctionResult({
              abi: fixtureUpshiftAbi,
              functionName: "withdrawalsPaused",
              result: false,
            });
          case "maxWithdrawalAmount":
            return encodeFunctionResult({
              abi: fixtureUpshiftAbi,
              functionName: "maxWithdrawalAmount",
              result: 10_000_000_000n,
            });
          case "instantRedemptionFee":
            return encodeFunctionResult({
              abi: fixtureUpshiftAbi,
              functionName: "instantRedemptionFee",
              result: 50n,
            });
          case "previewDeposit": {
            const assets = decoded.args[1];
            return encodeFunctionResult({
              abi: fixtureUpshiftAbi,
              functionName: "previewDeposit",
              result: [assets, assets],
            });
          }
          case "previewRedemption": {
            const shares = decoded.args[0];
            return encodeFunctionResult({
              abi: fixtureUpshiftAbi,
              functionName: "previewRedemption",
              result: [shares, shares - (shares * 50n) / 10_000n],
            });
          }
        }
      }

      const decoded = decodeFunctionData({ abi: fixtureTokenAbi, data });
      const isLp = target === evidenceModule.OFFICIAL_UPSHIFT_LP;
      switch (decoded.functionName) {
        case "decimals":
          return encodeFunctionResult({
            abi: fixtureTokenAbi,
            functionName: "decimals",
            result: 6,
          });
        case "name":
          return encodeFunctionResult({
            abi: fixtureTokenAbi,
            functionName: "name",
            result: isLp ? "Vault LP FXRP" : "FXRP",
          });
        case "symbol":
          return encodeFunctionResult({
            abi: fixtureTokenAbi,
            functionName: "symbol",
            result: isLp ? "vFXRP" : "FTestXRP",
          });
        case "totalSupply":
          return encodeFunctionResult({
            abi: fixtureTokenAbi,
            functionName: "totalSupply",
            result: 24_920_176n,
          });
        case "balanceOf":
          return encodeFunctionResult({
            abi: fixtureTokenAbi,
            functionName: "balanceOf",
            result: 25_007_563n,
          });
      }
    },
  };
}

async function runFixtureEvidence(recordedMethods: string[] = []) {
  return runEvidenceCommand({
    args: ["--block", FIXTURE_BLOCK.toString()],
    env: {},
    rpc: createFixtureRpc(recordedMethods),
    rpcEndpointLabel: "canonical fixture RPC",
  });
}

describe("Upshift withdrawal-limit evidence validation", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("exports the production generator and read-only RPC gateway", () => {
    expect("runEvidenceCommand" in evidenceModule).toBe(true);
    expect("createReadOnlyRpcGateway" in evidenceModule).toBe(true);
  });

  it("runs the actual generator independently of wall-clock time", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2030-01-01T00:00:00Z"));
    const first = await runFixtureEvidence();
    vi.setSystemTime(new Date("2099-12-31T23:59:59Z"));
    const second = await runFixtureEvidence();

    expect(second.serializedReport).toBe(first.serializedReport);
    expect(first.report.evidenceGeneratedAtUtc).toBe("2026-07-13T02:09:31.000Z");
    expect((first.report.block as Record<string, unknown>).timestampUtc).toBe(
      "2026-07-13T02:09:31.000Z",
    );
  });

  it("routes the actual generator only through the read-only RPC allowlist", async () => {
    const recordedMethods: string[] = [];
    const result = await runFixtureEvidence(recordedMethods);
    const uniqueMethods = new Set(recordedMethods);

    expect(uniqueMethods).toEqual(READ_ONLY_RPC_METHODS);
    expect(result.observedRpcMethods).toEqual(recordedMethods);
    expect(recordedMethods.filter((method) => /send|wallet|personal|sign/i.test(method))).toHaveLength(0);
  });

  it("denies unknown and write RPC methods before invoking the upstream requester", async () => {
    let upstreamCalls = 0;
    const gateway = createReadOnlyRpcGateway({
      async request(): Promise<unknown> {
        upstreamCalls += 1;
        return "0x";
      },
    });

    await expect(
      gateway.request({ method: "eth_sendRawTransaction", params: ["0xdead"] }),
    ).rejects.toThrow(/forbids RPC method/i);
    await expect(
      gateway.request({ method: "debug_traceCall", params: [] }),
    ).rejects.toThrow(/forbids RPC method/i);
    expect(upstreamCalls).toBe(0);
  });

  it("matches the canonical mock-fixture report golden SHA", async () => {
    const result = await runFixtureEvidence();
    expect(result.report.status).toBe("unverified_conservative");
    expect((result.report.block as Record<string, unknown>).hash).toBe(
      FIXTURE_BLOCK_HASH,
    );
    expect(result.report.writeTransactionsBroadcast).toBe(false);
    expect(result.report.privateKeyLoaded).toBe(false);
    expect(result.report.walletClientCreated).toBe(false);
    const digest = createHash("sha256").update(result.serializedReport).digest("hex").toUpperCase();
    expect(digest).toBe(
      "E9BD824F3F9C72630015FB9EFA963A92D048C42C5083755FCBFE5A8F6161D97F",
    );
  });

  it("keeps the committed live pinned report at its reviewed SHA", () => {
    const reportBytes = readFileSync(
      resolve("../reports/upshift-withdrawal-limit-semantics.json"),
    );
    expect(createHash("sha256").update(reportBytes).digest("hex").toUpperCase()).toBe(
      "7E72A91F7F9C8B1BFC13D4F3B47B39F726880C3F5A213E547BEE3EC7A1CF6C3A",
    );
  });

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
