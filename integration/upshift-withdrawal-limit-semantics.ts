import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  createPublicClient,
  decodeFunctionResult,
  defineChain,
  encodeFunctionData,
  getAddress,
  http,
  isAddress,
  isAddressEqual,
  keccak256,
  parseAbi,
  zeroAddress,
  type Address,
  type Hex,
  type PublicClient,
} from "viem";

export const COSTON2_CHAIN_ID = 114;
export const DEFAULT_RPC_URL = "https://coston2-api.flare.network/ext/C/rpc";
export const OFFICIAL_FXRP = getAddress(
  "0x0b6A3645c240605887a5532109323A3E12273dc7",
);
export const OFFICIAL_UPSHIFT_VAULT = getAddress(
  "0x24c1a47cD5e8473b64EAB2a94515a196E10C7C81",
);
export const OFFICIAL_UPSHIFT_LP = getAddress(
  "0xe084F7328DDaB082a139b880782dCC424d20a1DB",
);

const EIP1967_IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc" as const;
const BPS_DENOMINATOR = 10_000n;
const OFFICIAL_SOURCES = {
  instantRedeemGuide: "https://dev.flare.network/fxrp/upshift/instant-redeem",
  requestRedeemGuide: "https://dev.flare.network/fxrp/upshift/request-redeem",
  interfaceAtReviewedCommit:
    "https://github.com/flare-foundation/flare-hardhat-starter/blob/1ce4e8cafb9159a8944a2c85dc2bd3614e4ab7bb/contracts/upshift/ITokenizedVault.sol",
} as const;

const tokenAbi = parseAbi([
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function totalSupply() view returns (uint256)",
]);

const upshiftAbi = parseAbi([
  "function asset() view returns (address)",
  "function lpTokenAddress() view returns (address)",
  "function previewDeposit(address assetIn,uint256 amountIn) view returns (uint256 shares,uint256 amountInReferenceTokens)",
  "function previewRedemption(uint256 shares,bool isInstant) view returns (uint256 assetsAmount,uint256 assetsAfterFee)",
  "function withdrawalsPaused() view returns (bool)",
  "function maxWithdrawalAmount() view returns (uint256)",
  "function instantRedemptionFee() view returns (uint256)",
]);

const coston2 = defineChain({
  id: COSTON2_CHAIN_ID,
  name: "Coston2",
  nativeCurrency: { name: "Coston2 Flare", symbol: "C2FLR", decimals: 18 },
  rpcUrls: { default: { http: [DEFAULT_RPC_URL] } },
  blockExplorers: {
    default: {
      name: "Coston2 Explorer",
      url: "https://coston2-explorer.flare.network",
    },
  },
  testnet: true,
});

export type EvidenceBlock = {
  number: bigint;
  hash: Hex | null;
  timestamp: bigint;
};

export type RedemptionPreview = {
  shares: bigint;
  gross: bigint;
  net: bigint;
};

export type DepositPreview = {
  assets: bigint;
  expectedShares: bigint;
  referenceAmount: bigint;
};

type RecordedCall = {
  classification: "OBSERVED";
  rpcMethod: "eth_call";
  target: Address;
  blockNumber: string;
  functionSignature: string;
  calldata: Hex;
  rawReturndata: Hex;
  decoded: unknown;
};

export function requireExpectedChain(chainId: number): void {
  if (chainId !== COSTON2_CHAIN_ID) {
    throw new Error(`Expected Coston2 chain ID 114, received ${chainId}`);
  }
}

export function requireContractCode(
  code: Hex | undefined,
  label: string,
): number {
  return (requireCodeHex(code, label).length - 2) / 2;
}

function requireCodeHex(code: Hex | undefined, label: string): Hex {
  if (!code || code === "0x") throw new Error(`${label} has no bytecode`);
  return code;
}

export function assertAddressBinding(
  actual: string,
  expected: string,
  label: string,
): void {
  if (!isAddress(actual) || !isAddress(expected)) {
    throw new Error(`${label} binding contains an invalid address`);
  }
  if (!isAddressEqual(actual, expected)) {
    throw new Error(`${label} binding mismatch: ${actual} != ${expected}`);
  }
}

function requireWord(data: Hex, label: string): void {
  if (!/^0x[0-9a-fA-F]{64}$/.test(data)) {
    throw new Error(`${label} must be exactly one 32-byte ABI word`);
  }
}

export function decodeStrictBool(data: Hex, label: string): boolean {
  requireWord(data, label);
  const value = BigInt(data);
  if (value !== 0n && value !== 1n) {
    throw new Error(`${label} is not a canonical ABI boolean`);
  }
  return value === 1n;
}

export function decodeStrictUint256(data: Hex, label: string): bigint {
  requireWord(data, label);
  return BigInt(data);
}

export function validateRedemptionPreview(
  preview: RedemptionPreview,
): void {
  if (preview.shares <= 0n) throw new Error("Preview shares must be positive");
  if (preview.gross <= 0n) throw new Error("Preview gross must be positive");
  if (preview.net > preview.gross) {
    throw new Error("Preview net exceeds gross");
  }
}

export function validateDepositPreview(preview: DepositPreview): void {
  if (preview.assets <= 0n) throw new Error("Deposit assets must be positive");
  if (preview.expectedShares <= 0n) {
    throw new Error("Deposit preview shares must be positive");
  }
  if (preview.referenceAmount <= 0n) {
    throw new Error("Deposit reference amount must be positive");
  }
}

export function isConservativelyWithinLimit(
  gross: bigint,
  net: bigint,
  limit: bigint,
): boolean {
  return gross <= limit && net <= limit;
}

export function serializeEvidence(value: unknown, space = 0): string {
  return JSON.stringify(
    value,
    (_key, item: unknown) =>
      typeof item === "bigint" ? item.toString() : item,
    space,
  );
}

export function requireEvidenceBlock(block: EvidenceBlock): asserts block is {
  number: bigint;
  hash: Hex;
  timestamp: bigint;
} {
  if (block.number < 0n) throw new Error("Evidence block number is invalid");
  if (!block.hash) throw new Error("Evidence block hash is missing");
  if (block.timestamp <= 0n) throw new Error("Evidence block timestamp is invalid");
}

export function assertConsistentBlock(
  expected: bigint,
  actual: bigint,
  label: string,
): void {
  if (actual !== expected) {
    throw new Error(
      `${label} uses inconsistent block ${actual}; expected ${expected}`,
    );
  }
}

export async function withRpcBoundary<T>(
  label: string,
  operation: () => Promise<T>,
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`${label} RPC failure: ${message}`);
  }
}

export function assertReadOnlyCommand(command: string): void {
  const forbidden = [
    /\bcast\s+send\b/i,
    /--broadcast\b/i,
    /eth_send(?:Raw)?Transaction/i,
    /\bwriteContract\b/i,
    /\bsendTransaction\b/i,
    /privateKeyToAccount/i,
    /createWalletClient/i,
  ];
  if (forbidden.some((pattern) => pattern.test(command))) {
    throw new Error(`Read-only evidence forbids command: ${command}`);
  }
}

function decodeImplementation(storage: Hex | undefined): Address {
  if (!storage || !/^0x[0-9a-fA-F]{64}$/.test(storage)) {
    throw new Error("EIP-1967 implementation slot is malformed");
  }
  const implementation = getAddress(`0x${storage.slice(-40)}`);
  if (implementation === zeroAddress) {
    throw new Error("EIP-1967 implementation address is zero");
  }
  return implementation;
}

export function selectRedemptionProbes(totalSupply: bigint): bigint[] {
  if (totalSupply < 3n) throw new Error("LP total supply is too small for probes");
  const candidates = [1_000n, totalSupply / 1_000n, totalSupply];
  const unique = [...new Set(candidates.filter((value) => value > 0n && value <= totalSupply))];
  if (unique.length < 3) throw new Error("Could not select three distinct LP probes");
  return unique.slice(0, 3);
}

async function executeRawCall(
  client: PublicClient,
  target: Address,
  calldata: Hex,
  blockNumber: bigint,
  label: string,
): Promise<Hex> {
  const result = await withRpcBoundary(label, () =>
    client.call({ to: target, data: calldata, blockNumber }),
  );
  if (!result.data || result.data === "0x") {
    throw new Error(`${label} returned empty data`);
  }
  return result.data;
}

function recordCall(
  calls: RecordedCall[],
  target: Address,
  blockNumber: bigint,
  functionSignature: string,
  calldata: Hex,
  rawReturndata: Hex,
  decoded: unknown,
): void {
  calls.push({
    classification: "OBSERVED",
    rpcMethod: "eth_call",
    target,
    blockNumber: blockNumber.toString(),
    functionSignature,
    calldata,
    rawReturndata,
    decoded,
  });
}

async function collectEvidence(): Promise<Record<string, unknown>> {
  const rpcUrl = process.env.COSTON2_RPC_URL ?? DEFAULT_RPC_URL;
  const client = createPublicClient({
    chain: coston2,
    transport: http(rpcUrl, { retryCount: 4, timeout: 20_000 }),
  });
  const chainId = await withRpcBoundary("chain ID", () => client.getChainId());
  requireExpectedChain(chainId);

  const latest = await withRpcBoundary("latest block", () =>
    client.getBlock({ blockTag: "latest" }),
  );
  const requestedBlock = process.env.UPSHIFT_EVIDENCE_BLOCK
    ? BigInt(process.env.UPSHIFT_EVIDENCE_BLOCK)
    : latest.number;
  const block = await withRpcBoundary("evidence block", () =>
    client.getBlock({ blockNumber: requestedBlock }),
  );
  requireEvidenceBlock(block);
  assertConsistentBlock(requestedBlock, block.number, "evidence block");
  const evidenceBlock = block.number;

  const [fxrpCode, vaultCode, lpCode, implementationStorage] = await Promise.all([
    withRpcBoundary("FXRP code", () =>
      client.getBytecode({ address: OFFICIAL_FXRP, blockNumber: evidenceBlock }),
    ),
    withRpcBoundary("vault code", () =>
      client.getBytecode({ address: OFFICIAL_UPSHIFT_VAULT, blockNumber: evidenceBlock }),
    ),
    withRpcBoundary("LP code", () =>
      client.getBytecode({ address: OFFICIAL_UPSHIFT_LP, blockNumber: evidenceBlock }),
    ),
    withRpcBoundary("implementation slot", () =>
      client.getStorageAt({
        address: OFFICIAL_UPSHIFT_VAULT,
        slot: EIP1967_IMPLEMENTATION_SLOT,
        blockNumber: evidenceBlock,
      }),
    ),
  ]);
  const implementation = decodeImplementation(implementationStorage);
  const implementationCode = await withRpcBoundary("implementation code", () =>
    client.getBytecode({ address: implementation, blockNumber: evidenceBlock }),
  );
  const fxrpRuntime = requireCodeHex(fxrpCode, "FXRP");
  const vaultRuntime = requireCodeHex(vaultCode, "Upshift vault");
  const lpRuntime = requireCodeHex(lpCode, "Upshift LP token");
  const implementationRuntime = requireCodeHex(
    implementationCode,
    "Upshift implementation",
  );
  const codeEvidence = {
    fxrp: {
      address: OFFICIAL_FXRP,
      bytes: requireContractCode(fxrpRuntime, "FXRP"),
      runtimeHash: keccak256(fxrpRuntime),
    },
    vault: {
      address: OFFICIAL_UPSHIFT_VAULT,
      bytes: requireContractCode(vaultRuntime, "Upshift vault"),
      runtimeHash: keccak256(vaultRuntime),
    },
    lpToken: {
      address: OFFICIAL_UPSHIFT_LP,
      bytes: requireContractCode(lpRuntime, "Upshift LP token"),
      runtimeHash: keccak256(lpRuntime),
    },
    implementation: {
      address: implementation,
      slot: EIP1967_IMPLEMENTATION_SLOT,
      rawSlotValue: implementationStorage,
      bytes: requireContractCode(implementationRuntime, "Upshift implementation"),
      runtimeHash: keccak256(implementationRuntime),
    },
  };

  const calls: RecordedCall[] = [];
  const callVault = async (
    functionName:
      | "asset"
      | "lpTokenAddress"
      | "withdrawalsPaused"
      | "maxWithdrawalAmount"
      | "instantRedemptionFee",
    signature: string,
  ): Promise<Hex> => {
    const calldata = encodeFunctionData({ abi: upshiftAbi, functionName });
    const raw = await executeRawCall(
      client,
      OFFICIAL_UPSHIFT_VAULT,
      calldata,
      evidenceBlock,
      signature,
    );
    return raw;
  };

  const assetCallData = encodeFunctionData({ abi: upshiftAbi, functionName: "asset" });
  const assetRaw = await executeRawCall(client, OFFICIAL_UPSHIFT_VAULT, assetCallData, evidenceBlock, "asset()");
  const reportedAsset = getAddress(
    decodeFunctionResult({ abi: upshiftAbi, functionName: "asset", data: assetRaw }),
  );
  recordCall(calls, OFFICIAL_UPSHIFT_VAULT, evidenceBlock, "asset()", assetCallData, assetRaw, reportedAsset);

  const lpCallData = encodeFunctionData({ abi: upshiftAbi, functionName: "lpTokenAddress" });
  const lpRaw = await executeRawCall(client, OFFICIAL_UPSHIFT_VAULT, lpCallData, evidenceBlock, "lpTokenAddress()");
  const reportedLp = getAddress(
    decodeFunctionResult({ abi: upshiftAbi, functionName: "lpTokenAddress", data: lpRaw }),
  );
  recordCall(calls, OFFICIAL_UPSHIFT_VAULT, evidenceBlock, "lpTokenAddress()", lpCallData, lpRaw, reportedLp);
  assertAddressBinding(reportedAsset, OFFICIAL_FXRP, "asset");
  assertAddressBinding(reportedLp, OFFICIAL_UPSHIFT_LP, "LP token");

  const pausedCallData = encodeFunctionData({ abi: upshiftAbi, functionName: "withdrawalsPaused" });
  const pausedRaw = await callVault("withdrawalsPaused", "withdrawalsPaused()");
  const withdrawalsPaused = decodeStrictBool(pausedRaw, "withdrawalsPaused");
  recordCall(calls, OFFICIAL_UPSHIFT_VAULT, evidenceBlock, "withdrawalsPaused()", pausedCallData, pausedRaw, withdrawalsPaused);

  const limitCallData = encodeFunctionData({ abi: upshiftAbi, functionName: "maxWithdrawalAmount" });
  const limitRaw = await callVault("maxWithdrawalAmount", "maxWithdrawalAmount()");
  const maxWithdrawalAmount = decodeStrictUint256(limitRaw, "maxWithdrawalAmount");
  recordCall(calls, OFFICIAL_UPSHIFT_VAULT, evidenceBlock, "maxWithdrawalAmount()", limitCallData, limitRaw, maxWithdrawalAmount.toString());

  const feeCallData = encodeFunctionData({ abi: upshiftAbi, functionName: "instantRedemptionFee" });
  const feeRaw = await callVault("instantRedemptionFee", "instantRedemptionFee()");
  const rawFee = decodeStrictUint256(feeRaw, "instantRedemptionFee");
  recordCall(calls, OFFICIAL_UPSHIFT_VAULT, evidenceBlock, "instantRedemptionFee()", feeCallData, feeRaw, rawFee.toString());

  const readToken = async (
    address: Address,
    functionName: "decimals" | "name" | "symbol" | "totalSupply",
    signature: string,
  ): Promise<unknown> => {
    let calldata: Hex;
    switch (functionName) {
      case "decimals":
        calldata = encodeFunctionData({ abi: tokenAbi, functionName: "decimals" });
        break;
      case "name":
        calldata = encodeFunctionData({ abi: tokenAbi, functionName: "name" });
        break;
      case "symbol":
        calldata = encodeFunctionData({ abi: tokenAbi, functionName: "symbol" });
        break;
      case "totalSupply":
        calldata = encodeFunctionData({ abi: tokenAbi, functionName: "totalSupply" });
        break;
    }
    const raw = await executeRawCall(client, address, calldata, evidenceBlock, `${address} ${signature}`);
    let decoded: bigint | number | string;
    switch (functionName) {
      case "decimals":
        decoded = decodeFunctionResult({ abi: tokenAbi, functionName: "decimals", data: raw });
        break;
      case "name":
        decoded = decodeFunctionResult({ abi: tokenAbi, functionName: "name", data: raw });
        break;
      case "symbol":
        decoded = decodeFunctionResult({ abi: tokenAbi, functionName: "symbol", data: raw });
        break;
      case "totalSupply":
        decoded = decodeFunctionResult({ abi: tokenAbi, functionName: "totalSupply", data: raw });
        break;
    }
    recordCall(calls, address, evidenceBlock, signature, calldata, raw, typeof decoded === "bigint" ? decoded.toString() : decoded);
    return decoded;
  };
  const fxrpDecimals = await readToken(OFFICIAL_FXRP, "decimals", "decimals()");
  const fxrpName = await readToken(OFFICIAL_FXRP, "name", "name()");
  const fxrpSymbol = await readToken(OFFICIAL_FXRP, "symbol", "symbol()");
  const lpDecimals = await readToken(OFFICIAL_UPSHIFT_LP, "decimals", "decimals()");
  const lpName = await readToken(OFFICIAL_UPSHIFT_LP, "name", "name()");
  const lpSymbol = await readToken(OFFICIAL_UPSHIFT_LP, "symbol", "symbol()");
  const lpSupply = await readToken(OFFICIAL_UPSHIFT_LP, "totalSupply", "totalSupply()");
  if (typeof lpSupply !== "bigint") {
    throw new Error("LP totalSupply did not decode as uint256");
  }
  const lpTotalSupply = lpSupply;

  const vaultBalanceData = encodeFunctionData({
    abi: tokenAbi,
    functionName: "balanceOf",
    args: [OFFICIAL_UPSHIFT_VAULT],
  });
  const vaultBalanceRaw = await executeRawCall(client, OFFICIAL_FXRP, vaultBalanceData, evidenceBlock, "FXRP balanceOf(vault)");
  const vaultFxrpBalance = decodeFunctionResult({ abi: tokenAbi, functionName: "balanceOf", data: vaultBalanceRaw });
  recordCall(calls, OFFICIAL_FXRP, evidenceBlock, "balanceOf(address)", vaultBalanceData, vaultBalanceRaw, vaultFxrpBalance.toString());

  const redemptionPreviews = [];
  for (const shares of selectRedemptionProbes(lpTotalSupply)) {
    const calldata = encodeFunctionData({
      abi: upshiftAbi,
      functionName: "previewRedemption",
      args: [shares, true],
    });
    const raw = await executeRawCall(client, OFFICIAL_UPSHIFT_VAULT, calldata, evidenceBlock, `previewRedemption(${shares},true)`);
    const [gross, net] = decodeFunctionResult({ abi: upshiftAbi, functionName: "previewRedemption", data: raw });
    validateRedemptionPreview({ shares, gross, net });
    const effectiveFeeBps = ((gross - net) * BPS_DENOMINATOR) / gross;
    const sample = {
      classification: "DERIVED",
      shares,
      gross,
      net,
      feeAmount: gross - net,
      effectiveFeeBps,
      withinConservativeLimit: isConservativelyWithinLimit(gross, net, maxWithdrawalAmount),
    };
    redemptionPreviews.push(sample);
    recordCall(calls, OFFICIAL_UPSHIFT_VAULT, evidenceBlock, "previewRedemption(uint256,bool)", calldata, raw, [gross.toString(), net.toString()]);
  }

  const depositPreviews = [];
  for (const assets of [1_000n, 100_000n, 1_000_000n]) {
    const depositCalldata = encodeFunctionData({
      abi: upshiftAbi,
      functionName: "previewDeposit",
      args: [OFFICIAL_FXRP, assets],
    });
    const depositRaw = await executeRawCall(client, OFFICIAL_UPSHIFT_VAULT, depositCalldata, evidenceBlock, `previewDeposit(${assets})`);
    const [expectedShares, referenceAmount] = decodeFunctionResult({ abi: upshiftAbi, functionName: "previewDeposit", data: depositRaw });
    validateDepositPreview({ assets, expectedShares, referenceAmount });
    recordCall(calls, OFFICIAL_UPSHIFT_VAULT, evidenceBlock, "previewDeposit(address,uint256)", depositCalldata, depositRaw, [expectedShares.toString(), referenceAmount.toString()]);

    const redemptionCalldata = encodeFunctionData({
      abi: upshiftAbi,
      functionName: "previewRedemption",
      args: [expectedShares, true],
    });
    const redemptionRaw = await executeRawCall(client, OFFICIAL_UPSHIFT_VAULT, redemptionCalldata, evidenceBlock, `previewRedemption(${expectedShares},true)`);
    const [immediateGross, immediateNet] = decodeFunctionResult({ abi: upshiftAbi, functionName: "previewRedemption", data: redemptionRaw });
    validateRedemptionPreview({ shares: expectedShares, gross: immediateGross, net: immediateNet });
    recordCall(calls, OFFICIAL_UPSHIFT_VAULT, evidenceBlock, "previewRedemption(uint256,bool)", redemptionCalldata, redemptionRaw, [immediateGross.toString(), immediateNet.toString()]);
    depositPreviews.push({
      classification: "DERIVED",
      assets,
      expectedShares,
      referenceAmount,
      immediateGross,
      immediateNet,
      referenceEqualsImmediateNet: referenceAmount === immediateNet,
      sharesEqualAssets: expectedShares === assets,
    });
  }

  const allWithinLimit = redemptionPreviews.every((sample) => sample.withinConservativeLimit);
  const feeSamplesSupportRawBps = redemptionPreviews.every(
    (sample) => sample.effectiveFeeBps <= rawFee && rawFee - sample.effectiveFeeBps <= 1n,
  );

  return {
    status: "unverified_conservative",
    network: {
      classification: "OBSERVED",
      name: "coston2",
      chainId,
      rpcEndpointLabel: rpcUrl === DEFAULT_RPC_URL ? "Flare public Coston2 RPC" : "custom RPC (redacted)",
    },
    block: {
      classification: "OBSERVED",
      number: evidenceBlock,
      hash: block.hash,
      timestamp: block.timestamp,
      timestampUtc: new Date(Number(block.timestamp) * 1_000).toISOString(),
    },
    contracts: codeEvidence,
    bindings: {
      classification: "OBSERVED",
      reportedAsset,
      expectedAsset: OFFICIAL_FXRP,
      reportedLpToken: reportedLp,
      expectedLpToken: OFFICIAL_UPSHIFT_LP,
      vaultDefinesAssetAndLpRelationship: true,
    },
    tokens: {
      fxrp: { name: fxrpName, symbol: fxrpSymbol, decimals: fxrpDecimals },
      lpToken: { name: lpName, symbol: lpSymbol, decimals: lpDecimals, totalSupply: lpTotalSupply },
      vaultFxrpBalanceContextOnly: vaultFxrpBalance,
      vaultBalanceIsNotNav: true,
    },
    statusAtBlock: {
      classification: "OBSERVED",
      withdrawalsPaused,
      maxWithdrawalAmount,
      rawInstantRedemptionFee: rawFee,
    },
    fee: {
      classification: "INFERRED",
      raw: rawFee,
      denominatorUsedForComparisonOnly: BPS_DENOMINATOR,
      previewSamplesWithinOneBpsOfRaw: feeSamplesSupportRawBps,
      statement: feeSamplesSupportRawBps
        ? "All probes support the live raw fee within integer-flooring tolerance."
        : "The probes do not support equating effective fee BPS with the raw fee.",
    },
    depositPreviews,
    redemptionPreviews,
    withdrawalLimit: {
      observedLimit: maxWithdrawalAmount,
      candidateSemantics: "UNRESOLVED",
      evidenceTier: "TIER_1_GETTER_AND_PREVIEW_PLUS_PROXY_BINDING",
      conclusion: "UNRESOLVED",
      confidence: "LOW",
      sourceOrBytecodeComparisonProven: false,
      executionSimulationPerformed: false,
      tierOneSamplesAllWithinDualLimit: allWithinLimit,
      unresolvedQuestions: [
        "The deployed implementation comparison variable has not been proven from matched verified source or bytecode control flow.",
        "No non-broadcast execution simulation with a real eligible LP holder was performed.",
        "The live limit is above the previewed value of the sampled real LP supply, so gross/net boundary cases were not constructible from these probes.",
      ],
    },
    sourceInspection: {
      classification: "OBSERVED_OFFCHAIN",
      sources: OFFICIAL_SOURCES,
      instantRedeemGuideObservation:
        "The official instant-redeem example previews gross/net output and measures balances, but does not read or define maxWithdrawalAmount execution semantics.",
      requestRedeemGuideObservation:
        "The delayed request-redeem example compares sharesToRedeem with maxWithdrawalAmount; this different path does not prove the instantRedeem comparison variable.",
      deployedBytecodeMatchedToPublishedSource: false,
      semanticProofObtained: false,
    },
    adapterAssessment: {
      classification: "INSUFFICIENT_EVIDENCE",
      currentRule: "previewGross <= limit AND previewNet <= limit",
      mayOverestimate: "UNRESOLVED when the protocol uses an unknown internal reference value",
      knownEffect: "The dual check does not relax liquidity and may underestimate it under gross-only or net-only semantics.",
      recommendation: "Keep the conservative dual check unchanged until higher-tier evidence is reviewed.",
    },
    calls,
    writeTransactionsBroadcast: false,
    privateKeyLoaded: false,
    walletClientCreated: false,
    evidenceGeneratedAtUtc: new Date().toISOString(),
  };
}

async function writeEvidence(report: Record<string, unknown>): Promise<void> {
  const here = dirname(fileURLToPath(import.meta.url));
  const reportPath = resolve(here, "../reports/upshift-withdrawal-limit-semantics.json");
  await mkdir(dirname(reportPath), { recursive: true });
  await writeFile(reportPath, `${serializeEvidence(report, 2)}\n`, "utf8");
}

async function main(): Promise<void> {
  const report = await collectEvidence();
  await writeEvidence(report);
  process.stdout.write(
    `${serializeEvidence({
      status: report.status,
      evidenceBlock: (report.block as Record<string, unknown>).number,
      conclusion: (report.withdrawalLimit as Record<string, unknown>).conclusion,
      writeTransactionsBroadcast: report.writeTransactionsBroadcast,
    })}\n`,
  );
}

const invokedDirectly = process.argv[1]
  ? import.meta.url === pathToFileURL(resolve(process.argv[1])).href
  : false;
if (invokedDirectly) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : "Read-only evidence failed");
    process.exitCode = 1;
  });
}
