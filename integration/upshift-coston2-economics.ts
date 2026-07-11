import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  createPublicClient,
  createWalletClient,
  defineChain,
  getAddress,
  http,
  parseAbi,
  type Address,
  type Hash,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import {
  COSTON2_CHAIN_ID,
  DEFAULT_RPC_URL,
  OFFICIAL_FXRP,
  OFFICIAL_UPSHIFT_VAULT,
  assertAddressMatch,
  assertAllowancesZero,
  assertCoston2Chain,
  isAllowanceRelatedError,
  positiveDelta,
  stringifyReport,
} from "./upshift-coston2-smoke.js";

const PREVIEW_AMOUNTS = [10n, 100n, 1_000n, 10_000n, 100_000n, 1_000_000n] as const;
const LIVE_AMOUNTS = new Set([10_000n, 100_000n]);
const FEE_DENOMINATOR = 10_000n;
const IMPLEMENTATION = getAddress("0x94c1851b1631769147b62f8370e851682361cee2");
const EIP1967_IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc" as const;
const DENOMINATOR_OPCODE_OFFSETS = [0x169b, 0x16ac, 0x16b3, 0x16dc] as const;

const tokenAbi = parseAbi([
  "function allowance(address owner,address spender) view returns (uint256)",
  "function approve(address spender,uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
]);

const upshiftAbi = parseAbi([
  "function asset() view returns (address)",
  "function lpTokenAddress() view returns (address)",
  "function previewDeposit(address assetIn,uint256 amountIn) view returns (uint256 shares,uint256 amountInReferenceTokens)",
  "function deposit(address assetIn,uint256 amountIn,address receiverAddr) returns (uint256 shares)",
  "function previewRedemption(uint256 shares,bool isInstant) view returns (uint256 assetsAmount,uint256 assetsAfterFee)",
  "function instantRedeem(uint256 shares,address receiverAddr)",
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
    default: { name: "Coston2 Explorer", url: "https://coston2-explorer.flare.network" },
  },
  testnet: true,
});

export type PreviewEconomics = {
  inputAssets: bigint;
  previewedShares: bigint;
  previewedGrossAssets: bigint;
  previewedNetAssets: bigint;
  roundingLoss: bigint;
  explicitFeeAmount: bigint;
  totalLoss: bigint;
  totalLossBps: bigint;
  impliedRedemptionFeeBps: bigint;
  dominatedByOneUnitRounding: boolean;
};

export function analyzePreview(
  inputAssets: bigint,
  previewedShares: bigint,
  previewedGrossAssets: bigint,
  previewedNetAssets: bigint,
): PreviewEconomics {
  if (
    inputAssets <= 0n ||
    previewedShares <= 0n ||
    previewedGrossAssets <= 0n ||
    previewedNetAssets <= 0n
  ) {
    throw new Error("Input and all previews must be nonzero");
  }
  if (previewedNetAssets > previewedGrossAssets) {
    throw new Error("Net redemption preview exceeds gross preview");
  }
  const roundingLoss = inputAssets > previewedGrossAssets ? inputAssets - previewedGrossAssets : 0n;
  const explicitFeeAmount = previewedGrossAssets - previewedNetAssets;
  const totalLoss = inputAssets > previewedNetAssets ? inputAssets - previewedNetAssets : 0n;
  return {
    inputAssets,
    previewedShares,
    previewedGrossAssets,
    previewedNetAssets,
    roundingLoss,
    explicitFeeAmount,
    totalLoss,
    totalLossBps: (totalLoss * 10_000n) / inputAssets,
    impliedRedemptionFeeBps:
      (explicitFeeAmount * 10_000n) / previewedGrossAssets,
    dominatedByOneUnitRounding:
      roundingLoss === 1n && roundingLoss >= explicitFeeAmount,
  };
}

export function interpretFeeConfiguration(
  rawFee: bigint,
  denominator: bigint,
  samples: readonly { gross: bigint; net: bigint }[],
): { rawFee: bigint; denominator: bigint; interpretedFeeBps: bigint } {
  if (rawFee < 0n || denominator <= 0n || samples.length === 0) {
    throw new Error("Fee interpretation requires valid configuration and samples");
  }
  for (const sample of samples) {
    const expectedNet = sample.gross - (sample.gross * rawFee) / denominator;
    if (expectedNet !== sample.net) {
      throw new Error(
        `Fee denominator does not match preview: expected ${expectedNet}, received ${sample.net}`,
      );
    }
  }
  return {
    rawFee,
    denominator,
    interpretedFeeBps: (rawFee * 10_000n) / denominator,
  };
}

export function selectLiveCalibrationAmount(
  walletAssets: bigint,
  maxWithdrawalAmount: bigint,
  candidates: readonly PreviewEconomics[],
): PreviewEconomics {
  const walletLimit = walletAssets / 10n;
  const eligible = candidates
    .filter(
      (candidate) =>
        LIVE_AMOUNTS.has(candidate.inputAssets) &&
        candidate.inputAssets <= walletLimit &&
        candidate.previewedGrossAssets <= maxWithdrawalAmount,
    )
    .sort((left, right) =>
      left.inputAssets < right.inputAssets ? -1 : left.inputAssets > right.inputAssets ? 1 : 0,
    );
  const smaller = eligible.find((candidate) => candidate.inputAssets === 10_000n);
  if (smaller && !smaller.dominatedByOneUnitRounding && smaller.explicitFeeAmount > 0n) {
    return smaller;
  }
  const larger = eligible.find((candidate) => candidate.inputAssets === 100_000n);
  if (larger) return larger;
  throw new Error("No live amount satisfies the 10% wallet and withdrawal limits");
}

function parsePrivateKey(value: string | undefined): `0x${string}` {
  if (!value) throw new Error("COSTON2_PRIVATE_KEY is required");
  const key = value.startsWith("0x") ? value : `0x${value}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(key)) throw new Error("Invalid private key format");
  return key as `0x${string}`;
}

function requireCode(code: `0x${string}` | undefined, label: string): number {
  if (!code || code === "0x") throw new Error(`${label} has no bytecode`);
  return (code.length - 2) / 2;
}

async function writeReport(report: Record<string, unknown>): Promise<void> {
  const here = dirname(fileURLToPath(import.meta.url));
  const reportPath = resolve(here, "../reports/upshift-coston2-economics.json");
  await mkdir(dirname(reportPath), { recursive: true });
  await writeFile(reportPath, `${stringifyReport(report)}\n`, "utf8");
}

async function main(): Promise<void> {
  const rpcUrl = process.env.COSTON2_RPC_URL ?? DEFAULT_RPC_URL;
  const publicClient = createPublicClient({
    chain: coston2,
    transport: http(rpcUrl, { retryCount: 4, timeout: 20_000 }),
  });
  const report: Record<string, unknown> = {
    network: "coston2",
    chainId: null,
    status: "preflight_failed",
    verifiedAt: new Date().toISOString(),
  };
  let account: ReturnType<typeof privateKeyToAccount> | undefined;
  let lpToken: Address | undefined;
  let depositConfirmed = false;
  let redemptionConfirmed = false;
  let reconciled = false;
  let cleanupFailure: Error | undefined;
  try {
    const chainId = await publicClient.getChainId();
    assertCoston2Chain(chainId);
    report.chainId = chainId;
    const [fxrpCode, vaultCode, implementationCode, implementationStorage] = await Promise.all([
      publicClient.getBytecode({ address: OFFICIAL_FXRP }),
      publicClient.getBytecode({ address: OFFICIAL_UPSHIFT_VAULT }),
      publicClient.getBytecode({ address: IMPLEMENTATION }),
      publicClient.getStorageAt({ address: OFFICIAL_UPSHIFT_VAULT, slot: EIP1967_IMPLEMENTATION_SLOT }),
    ]);
    const fxrpCodeBytes = requireCode(fxrpCode, "FTestXRP");
    const vaultCodeBytes = requireCode(vaultCode, "Upshift vault");
    const implementationCodeBytes = requireCode(implementationCode, "Upshift implementation");
    const verifiedImplementationCode = implementationCode!;
    if (!implementationStorage) throw new Error("Proxy implementation slot is empty");
    const boundImplementation = getAddress(`0x${implementationStorage.slice(-40)}`);
    assertAddressMatch(boundImplementation, IMPLEMENTATION, "Proxy implementation");
    const denominatorOpcodes = DENOMINATOR_OPCODE_OFFSETS.map((offset) => {
      const start = 2 + offset * 2;
      const bytes = verifiedImplementationCode.slice(start, start + 6).toLowerCase();
      if (bytes !== "612710") {
        throw new Error(`Expected PUSH2 0x2710 at runtime bytecode offset 0x${offset.toString(16)}`);
      }
      return { offset: `0x${offset.toString(16)}`, opcodeBytes: `0x${bytes}` };
    });
    const [assetRaw, lpRaw, assetDecimals, paused, maxWithdrawalAmount, rawFee] =
      await Promise.all([
        publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "asset" }),
        publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "lpTokenAddress" }),
        publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "decimals" }),
        publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "withdrawalsPaused" }),
        publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "maxWithdrawalAmount" }),
        publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "instantRedemptionFee" }),
      ]);
    assertAddressMatch(assetRaw, OFFICIAL_FXRP, "Vault asset");
    if (assetDecimals !== 6) throw new Error(`Unexpected FTestXRP decimals ${assetDecimals}`);
    if (paused) throw new Error("Upshift withdrawals are paused");
    lpToken = getAddress(lpRaw);
    const lpCode = await publicClient.getBytecode({ address: lpToken });
    const lpCodeBytes = requireCode(lpCode, "Upshift LP token");

    const previewSweep: PreviewEconomics[] = [];
    for (const amount of PREVIEW_AMOUNTS) {
      const [shares] = await publicClient.readContract({
        address: OFFICIAL_UPSHIFT_VAULT,
        abi: upshiftAbi,
        functionName: "previewDeposit",
        args: [OFFICIAL_FXRP, amount],
      });
      const [gross, net] = await publicClient.readContract({
        address: OFFICIAL_UPSHIFT_VAULT,
        abi: upshiftAbi,
        functionName: "previewRedemption",
        args: [shares, true],
      });
      previewSweep.push(analyzePreview(amount, shares, gross, net));
    }
    const feeConfiguration = interpretFeeConfiguration(
      rawFee,
      FEE_DENOMINATOR,
      previewSweep.map((item) => ({ gross: item.previewedGrossAssets, net: item.previewedNetAssets })),
    );
    report.contracts = {
      fxrp: { address: OFFICIAL_FXRP, bytecodeBytes: fxrpCodeBytes },
      vault: { address: OFFICIAL_UPSHIFT_VAULT, bytecodeBytes: vaultCodeBytes },
      implementation: {
        address: IMPLEMENTATION,
        bytecodeBytes: implementationCodeBytes,
        proxySlot: EIP1967_IMPLEMENTATION_SLOT,
        bindingVerified: true,
      },
      lpToken: { address: lpToken, bytecodeBytes: lpCodeBytes },
    };
    report.feeConfiguration = {
      rawInstantRedemptionFee: feeConfiguration.rawFee,
      denominator: feeConfiguration.denominator,
      interpretedFeeBps: feeConfiguration.interpretedFeeBps,
      application: "feeAmount = floor(grossAssets * rawFee / 10000); netAssets = grossAssets - feeAmount",
      previewIncludesFee: true,
      source: {
        officialGuide: "https://dev.flare.network/fxrp/upshift/instant-redeem",
        implementation: IMPLEMENTATION,
        runtimeBytecodeEvidence: denominatorOpcodes,
        livePreviewConsistency: "Every six-amount preview sample is consistent with the application expression",
        evidenceBoundary: "Preview samples alone do not uniquely prove a denominator because integer flooring can make nearby denominators observationally equivalent; the denominator determination relies on the bound runtime bytecode opcode evidence.",
      },
    };
    report.previewSweep = previewSweep;
    report.status = "deposit_failed";

    account = privateKeyToAccount(parsePrivateKey(process.env.COSTON2_PRIVATE_KEY));
    const walletClient = createWalletClient({
      account,
      chain: coston2,
      transport: http(rpcUrl, { retryCount: 4, timeout: 20_000 }),
    });
    const [walletAssetsBefore, walletSharesBefore, nativeBalance] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
      publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
      publicClient.getBalance({ address: account.address }),
    ]);
    if (nativeBalance === 0n) throw new Error("Wallet has no C2FLR");
    const selected = selectLiveCalibrationAmount(walletAssetsBefore, maxWithdrawalAmount, previewSweep);
    const amount = selected.inputAssets;
    report.selection = {
      selectedAmount: amount,
      walletAssetsBefore,
      tenPercentWalletLimit: walletAssetsBefore / 10n,
      maxWithdrawalAmount,
      reason: amount === 10_000n
        ? "0.01 FTestXRP has a nonzero fee and is not dominated by one-unit rounding"
        : "0.01 remained rounding dominated; selected 0.1 FTestXRP",
    };
    report.balances = {
      before: { walletAssets: walletAssetsBefore, walletShares: walletSharesBefore },
    };

    const resetAllowance = async (token: Address, label: string) => {
      const allowance = await publicClient.readContract({ address: token, abi: tokenAbi, functionName: "allowance", args: [account!.address, OFFICIAL_UPSHIFT_VAULT] });
      if (allowance === 0n) return;
      const hash = await walletClient.writeContract({ address: token, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, 0n] });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error(`${label} allowance reset reverted`);
      const transactions = (report.cleanupTransactions ??= []) as Array<Record<string, unknown>>;
      transactions.push({ token: label, transactionHash: hash, blockNumber: receipt.blockNumber, confirmed: true });
    };
    await resetAllowance(OFFICIAL_FXRP, "FTestXRP");

    const approvalHash = await walletClient.writeContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, amount] });
    const approvalReceipt = await publicClient.waitForTransactionReceipt({ hash: approvalHash });
    if (approvalReceipt.status !== "success") throw new Error("Asset approval reverted");
    report.approval = { transactionHash: approvalHash, blockNumber: approvalReceipt.blockNumber, confirmed: true, amount };
    const approved = await publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "allowance", args: [account.address, OFFICIAL_UPSHIFT_VAULT] });
    if (approved !== amount) throw new Error("Exact asset allowance could not be verified");

    const depositHash = await walletClient.writeContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "deposit", args: [OFFICIAL_FXRP, amount, account.address] });
    const depositReceipt = await publicClient.waitForTransactionReceipt({ hash: depositHash });
    if (depositReceipt.status !== "success") throw new Error("Deposit reverted");
    depositConfirmed = true;
    report.status = "deposit_confirmed_redemption_failed";
    const liveRoundTrip: Record<string, unknown> = { depositAmount: amount, approvalTx: approvalHash, depositTx: depositHash, depositBlock: depositReceipt.blockNumber };
    report.liveRoundTrip = liveRoundTrip;
    const [assetsAfterDeposit, sharesAfterDeposit] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
      publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
    ]);
    (report.balances as Record<string, unknown>).afterDeposit = {
      walletAssets: assetsAfterDeposit,
      walletShares: sharesAfterDeposit,
    };
    const actualShares = positiveDelta(walletSharesBefore, sharesAfterDeposit, "actual shares");
    const assetsSpent = positiveDelta(assetsAfterDeposit, walletAssetsBefore, "assets spent");
    if (assetsSpent !== amount) throw new Error("Deposit asset delta does not equal selected amount");
    liveRoundTrip.previewedShares = selected.previewedShares;
    liveRoundTrip.actualShares = actualShares;
    liveRoundTrip.sharePreviewDeviation = actualShares - selected.previewedShares;

    const [pausedBeforeRedeem, maxBeforeRedeem, refreshedFee, redemptionPreview] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "withdrawalsPaused" }),
      publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "maxWithdrawalAmount" }),
      publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "instantRedemptionFee" }),
      publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "previewRedemption", args: [actualShares, true] }),
    ]);
    if (pausedBeforeRedeem) throw new Error("Withdrawals paused after deposit");
    if (refreshedFee !== rawFee) throw new Error("Instant redemption fee changed during run");
    const [gross, net] = redemptionPreview;
    if (net === 0n || gross > maxBeforeRedeem) throw new Error("Refreshed redemption preview is not executable");
    const livePreview = analyzePreview(amount, actualShares, gross, net);

    try {
      await publicClient.simulateContract({ account: account.address, address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "instantRedeem", args: [actualShares, account.address] });
      report.lpApproval = { required: false };
    } catch (error) {
      if (!isAllowanceRelatedError(error)) throw error;
      await resetAllowance(lpToken, "Upshift LP");
      const lpApprovalHash = await walletClient.writeContract({ address: lpToken, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, actualShares] });
      const lpApprovalReceipt = await publicClient.waitForTransactionReceipt({ hash: lpApprovalHash });
      if (lpApprovalReceipt.status !== "success") throw new Error("LP approval reverted");
      report.lpApproval = { required: true, transactionHash: lpApprovalHash, blockNumber: lpApprovalReceipt.blockNumber, confirmed: true };
    }

    const redemptionHash = await walletClient.writeContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "instantRedeem", args: [actualShares, account.address] });
    const redemptionReceipt = await publicClient.waitForTransactionReceipt({ hash: redemptionHash });
    if (redemptionReceipt.status !== "success") throw new Error("Instant redemption reverted");
    redemptionConfirmed = true;
    liveRoundTrip.redemptionTx = redemptionHash;
    liveRoundTrip.redemptionBlock = redemptionReceipt.blockNumber;
    const [assetsAfterRedemption, sharesAfterRedemption] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
      publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
    ]);
    (report.balances as Record<string, unknown>).afterRedemption = {
      walletAssets: assetsAfterRedemption,
      walletShares: sharesAfterRedemption,
    };
    const actualAssetsReturned = positiveDelta(assetsAfterDeposit, assetsAfterRedemption, "actual returned assets");
    if (sharesAfterRedemption !== walletSharesBefore) throw new Error("LP share balance did not reconcile");
    reconciled = true;
    const actualLoss = amount > actualAssetsReturned ? amount - actualAssetsReturned : 0n;
    Object.assign(liveRoundTrip, {
      previewedGrossAssets: gross,
      previewedNetAssets: net,
      actualAssetsReturned,
      roundingLoss: livePreview.roundingLoss,
      explicitFeeAmount: livePreview.explicitFeeAmount,
      previewDeviation: actualAssetsReturned - net,
      actualRoundTripLoss: actualLoss,
      actualRoundTripLossBps: (actualLoss * 10_000n) / amount,
      explorerUrls: {
        approval: `${coston2.blockExplorers.default.url}/tx/${approvalHash}`,
        deposit: `${coston2.blockExplorers.default.url}/tx/${depositHash}`,
        redemption: `${coston2.blockExplorers.default.url}/tx/${redemptionHash}`,
      },
    });
  } catch (error) {
    report.error = error instanceof Error ? error.message : "Unknown economics error";
    throw error;
  } finally {
    if (account && lpToken) {
      try {
        const walletClient = createWalletClient({ account, chain: coston2, transport: http(rpcUrl) });
        const cleanup = async (token: Address, label: string) => {
          const before = await publicClient.readContract({ address: token, abi: tokenAbi, functionName: "allowance", args: [account!.address, OFFICIAL_UPSHIFT_VAULT] });
          if (before !== 0n) {
            const hash: Hash = await walletClient.writeContract({ address: token, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, 0n] });
            const receipt = await publicClient.waitForTransactionReceipt({ hash });
            if (receipt.status !== "success") throw new Error(`${label} cleanup reverted`);
            const transactions = (report.cleanupTransactions ??= []) as Array<Record<string, unknown>>;
            transactions.push({ token: label, transactionHash: hash, blockNumber: receipt.blockNumber, confirmed: true });
          }
          return publicClient.readContract({ address: token, abi: tokenAbi, functionName: "allowance", args: [account!.address, OFFICIAL_UPSHIFT_VAULT] });
        };
        const fxrpAfter = await cleanup(OFFICIAL_FXRP, "FTestXRP");
        const lpAfter = await cleanup(lpToken, "Upshift LP");
        assertAllowancesZero(fxrpAfter, lpAfter);
        report.allowancesAfter = { fxrp: fxrpAfter, lpToken: lpAfter };
        if (depositConfirmed && redemptionConfirmed && reconciled) report.status = "success";
      } catch (error) {
        cleanupFailure = error instanceof Error ? error : new Error("Allowance cleanup failed");
        report.error = `${String(report.error ?? "Protocol flow completed")}; ${cleanupFailure.message}`;
      }
    }
    report.verifiedAt = new Date().toISOString();
    await writeReport(report);
    if (cleanupFailure) throw cleanupFailure;
  }
}

const invokedDirectly = process.argv[1]
  ? import.meta.url === pathToFileURL(resolve(process.argv[1])).href
  : false;
if (invokedDirectly) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : "Economics run failed");
    process.exitCode = 1;
  });
}
