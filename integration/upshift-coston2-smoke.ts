import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  createPublicClient,
  createWalletClient,
  defineChain,
  getAddress,
  http,
  isAddress,
  isAddressEqual,
  parseAbi,
  parseUnits,
  zeroAddress,
  type Address,
  type Hash,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

export const COSTON2_CHAIN_ID = 114;
export const DEFAULT_RPC_URL = "https://coston2-api.flare.network/ext/C/rpc";
export const OFFICIAL_FXRP = getAddress(
  "0x0b6A3645c240605887a5532109323A3E12273dc7",
);
export const OFFICIAL_UPSHIFT_VAULT = getAddress(
  "0x24c1a47cD5e8473b64EAB2a94515a196E10C7C81",
);

const OFFICIAL_SOURCES = {
  fxrp: "https://dev.flare.network/fassets/reference",
  upshiftDeposit: "https://dev.flare.network/fxrp/upshift/deposit",
  upshiftInstantRedeem:
    "https://dev.flare.network/fxrp/upshift/instant-redeem",
  abi: "https://github.com/flare-foundation/flare-hardhat-starter/blob/1ce4e8cafb9159a8944a2c85dc2bd3614e4ab7bb/contracts/upshift/ITokenizedVault.sol",
} as const;

const tokenAbi = parseAbi([
  "function allowance(address owner,address spender) view returns (uint256)",
  "function approve(address spender,uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function totalSupply() view returns (uint256)",
]);

// Exact callable surface from Flare's ITokenizedVault, not a standard ERC-4626 ABI.
const upshiftAbi = parseAbi([
  "function asset() view returns (address)",
  "function lpTokenAddress() view returns (address)",
  "function deposit(address assetIn,uint256 amountIn,address receiverAddr) returns (uint256 shares)",
  "function previewDeposit(address assetIn,uint256 amountIn) view returns (uint256 shares,uint256 amountInReferenceTokens)",
  "function previewRedemption(uint256 shares,bool isInstant) view returns (uint256 assetsAmount,uint256 assetsAfterFee)",
  "function instantRedeem(uint256 shares,address receiverAddr)",
  "function instantRedemptionFee() view returns (uint256)",
  "function withdrawalsPaused() view returns (bool)",
  "function maxWithdrawalAmount() view returns (uint256)",
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

export function calculateFeeBps(gross: bigint, net: bigint): bigint {
  if (gross <= 0n) throw new Error("Gross amount must be positive");
  if (net < 0n || net > gross) throw new Error("Net amount exceeds gross amount");
  return ((gross - net) * 10_000n) / gross;
}

export function positiveDelta(
  before: bigint,
  after: bigint,
  label: string,
): bigint {
  const delta = after - before;
  if (delta <= 0n) throw new Error(`${label} delta must be positive`);
  return delta;
}

export function assertAddressMatch(
  actual: string,
  expected: string,
  label: string,
): void {
  if (!isAddress(actual) || !isAddress(expected)) {
    throw new Error(`${label} contains an invalid address`);
  }
  if (!isAddressEqual(actual, expected)) {
    throw new Error(`${label} address mismatch: ${actual} != ${expected}`);
  }
}

export function assertAssetMatch(actual: string, expected: string): void {
  try {
    assertAddressMatch(actual, expected, "Vault asset");
  } catch (error) {
    throw new Error(
      `Vault asset mismatch: ${error instanceof Error ? error.message : "unknown"}`,
    );
  }
}

export function assertCoston2Chain(chainId: number): void {
  if (chainId !== COSTON2_CHAIN_ID) {
    throw new Error(`Expected Coston2 chain ID 114, received ${chainId}`);
  }
}

export function stringifyReport(value: unknown): string {
  return JSON.stringify(
    value,
    (_key, item: unknown) => (typeof item === "bigint" ? item.toString() : item),
    2,
  );
}

export function assertWithinTolerance(
  expected: bigint,
  actual: bigint,
  tolerance: bigint,
  label: string,
): void {
  if (tolerance < 0n) throw new Error("Tolerance cannot be negative");
  const difference = expected >= actual ? expected - actual : actual - expected;
  if (difference > tolerance) {
    throw new Error(
      `${label} deviation ${difference} exceeds tolerance ${tolerance}`,
    );
  }
}

export type AmountCandidate = {
  amount: bigint;
  previewShares: bigint;
  redemptionGross: bigint;
  redemptionNet: bigint;
};

export function selectSmallestPracticalAmount(
  candidates: readonly AmountCandidate[],
  maxWithdrawalAmount: bigint,
): AmountCandidate {
  const selected = [...candidates]
    .sort((left, right) => (left.amount < right.amount ? -1 : left.amount > right.amount ? 1 : 0))
    .find(
      (candidate) =>
        candidate.amount > 0n &&
        candidate.previewShares > 0n &&
        candidate.redemptionGross > 0n &&
        candidate.redemptionNet > 0n &&
        candidate.redemptionGross <= maxWithdrawalAmount,
    );
  if (!selected) throw new Error("No practical amount passed both previews and the withdrawal limit");
  return selected;
}

export type ReportStatus =
  | "preflight_failed"
  | "deposit_failed"
  | "deposit_confirmed_redemption_failed"
  | "success";

export function deriveReportStatus(state: {
  preflightPassed: boolean;
  depositConfirmed?: boolean;
  redemptionConfirmed?: boolean;
  reconciled?: boolean;
  cleanupVerified?: boolean;
}): ReportStatus {
  if (!state.preflightPassed) return "preflight_failed";
  if (!state.depositConfirmed) return "deposit_failed";
  if (!state.redemptionConfirmed || !state.reconciled || !state.cleanupVerified) {
    return "deposit_confirmed_redemption_failed";
  }
  return "success";
}

export function calculateRoundTrip(
  deposited: bigint,
  returned: bigint,
): { absoluteLoss: bigint; roundTripLossBps: bigint } {
  if (deposited <= 0n) throw new Error("Deposited amount must be positive");
  const absoluteLoss = deposited > returned ? deposited - returned : 0n;
  return {
    absoluteLoss,
    roundTripLossBps: (absoluteLoss * 10_000n) / deposited,
  };
}

export function isAllowanceRelatedError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /(?:insufficient|exceeds?)\s+allowance|allowance.*(?:insufficient|exceeded)|transferFrom/i.test(
    message,
  );
}

export function assertAllowancesZero(fxrpAllowance: bigint, lpAllowance: bigint): void {
  if (fxrpAllowance !== 0n) throw new Error("Final FXRP allowance is not zero");
  if (lpAllowance !== 0n) throw new Error("Final LP allowance is not zero");
}

function requireContractCode(code: `0x${string}` | undefined, label: string): number {
  if (!code || code === "0x") throw new Error(`${label} has no contract bytecode`);
  return (code.length - 2) / 2;
}

function parsePrivateKey(value: string | undefined): `0x${string}` {
  if (!value) throw new Error("COSTON2_PRIVATE_KEY is required");
  const key = value.startsWith("0x") ? value : `0x${value}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(key)) {
    throw new Error("COSTON2_PRIVATE_KEY must be a 32-byte hex key");
  }
  return key as `0x${string}`;
}

async function writeReport(report: Record<string, unknown>): Promise<void> {
  const here = dirname(fileURLToPath(import.meta.url));
  const reportPath = resolve(here, "../reports/upshift-coston2-smoke.json");
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
    status: "preflight_failed",
    network: "coston2",
    chainId: null,
    rpc: rpcUrl === DEFAULT_RPC_URL ? DEFAULT_RPC_URL : "custom RPC redacted",
    officialSources: OFFICIAL_SOURCES,
    verifiedAt: new Date().toISOString(),
  };

  let account: ReturnType<typeof privateKeyToAccount> | undefined;
  let lpToken: Address | undefined;
  let preflightPassed = false;
  let depositConfirmed = false;
  let redemptionConfirmed = false;
  let reconciled = false;
  let cleanupVerified = false;
  let cleanupFailure: Error | undefined;
  let assetApprovalTouched = false;
  let lpApprovalTouched = false;
  try {
    const chainId = await publicClient.getChainId();
    assertCoston2Chain(chainId);
    report.chainId = chainId;

    if (OFFICIAL_FXRP === zeroAddress || OFFICIAL_UPSHIFT_VAULT === zeroAddress) {
      throw new Error("Official address resolved to the zero address");
    }
    const [fxrpCode, vaultCode] = await Promise.all([
      publicClient.getBytecode({ address: OFFICIAL_FXRP }),
      publicClient.getBytecode({ address: OFFICIAL_UPSHIFT_VAULT }),
    ]);
    const fxrpCodeBytes = requireContractCode(fxrpCode, "FXRP");
    const vaultCodeBytes = requireContractCode(vaultCode, "Upshift vault");

    const [vaultAssetRaw, lpTokenRaw, assetDecimals, assetSymbol] =
      await Promise.all([
        publicClient.readContract({
          address: OFFICIAL_UPSHIFT_VAULT,
          abi: upshiftAbi,
          functionName: "asset",
        }),
        publicClient.readContract({
          address: OFFICIAL_UPSHIFT_VAULT,
          abi: upshiftAbi,
          functionName: "lpTokenAddress",
        }),
        publicClient.readContract({
          address: OFFICIAL_FXRP,
          abi: tokenAbi,
          functionName: "decimals",
        }),
        publicClient.readContract({
          address: OFFICIAL_FXRP,
          abi: tokenAbi,
          functionName: "symbol",
        }),
      ]);
    const vaultAsset = getAddress(vaultAssetRaw);
    lpToken = getAddress(lpTokenRaw);
    assertAssetMatch(vaultAsset, OFFICIAL_FXRP);
    const lpCode = await publicClient.getBytecode({ address: lpToken });
    const lpCodeBytes = requireContractCode(lpCode, "Upshift LP token");

    const [
      shareDecimals,
      lpTotalSupply,
      vaultAssetBalance,
      withdrawalsPaused,
      maxWithdrawalAmount,
      reportedInstantRedemptionFee,
    ] =
      await Promise.all([
        publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "decimals" }),
        publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "totalSupply" }),
        publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "balanceOf", args: [OFFICIAL_UPSHIFT_VAULT] }),
        publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "withdrawalsPaused" }),
        publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "maxWithdrawalAmount" }),
        publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "instantRedemptionFee" }),
      ]);
    if (withdrawalsPaused) throw new Error("Upshift withdrawals are paused");

    report.fxrp = {
      address: OFFICIAL_FXRP,
      symbol: assetSymbol,
      decimals: assetDecimals,
      bytecodeBytes: fxrpCodeBytes,
    };
    report.upshiftVault = {
      address: OFFICIAL_UPSHIFT_VAULT,
      asset: vaultAsset,
      lpToken,
      shareDecimals,
      bytecodeBytes: vaultCodeBytes,
      lpTokenBytecodeBytes: lpCodeBytes,
      interfaceStyle: "ERC-4626 style; protocol-native ITokenizedVault",
      standardVaultAccountingRequired: false,
      directReferenceAssetBalanceNotNav: vaultAssetBalance,
      lpTokenTotalSupply: lpTotalSupply,
      withdrawalsPaused,
      maxWithdrawalAmount,
      reportedInstantRedemptionFee,
      instantRedeemSignature: "instantRedeem(uint256 shares,address receiverAddr)",
      semantics: "Burns LP shares and transfers net reference assets immediately; previewRedemption(shares,true) returns gross and after-fee assets.",
    };

    const configuredMaximum = parseUnits(
      process.env.UPSHIFT_SMOKE_MAX_AMOUNT ?? process.env.UPSHIFT_SMOKE_AMOUNT ?? "0.01",
      assetDecimals,
    );
    if (configuredMaximum <= 0n) throw new Error("UPSHIFT_SMOKE_MAX_AMOUNT must be positive");
    const candidates: AmountCandidate[] = [];
    for (let amount = 1n; amount <= configuredMaximum; amount *= 10n) {
      try {
        const [previewShares] = await publicClient.readContract({
          address: OFFICIAL_UPSHIFT_VAULT,
          abi: upshiftAbi,
          functionName: "previewDeposit",
          args: [OFFICIAL_FXRP, amount],
        });
        if (previewShares === 0n) {
          candidates.push({ amount, previewShares, redemptionGross: 0n, redemptionNet: 0n });
          continue;
        }
        const [redemptionGross, redemptionNet] = await publicClient.readContract({
          address: OFFICIAL_UPSHIFT_VAULT,
          abi: upshiftAbi,
          functionName: "previewRedemption",
          args: [previewShares, true],
        });
        candidates.push({ amount, previewShares, redemptionGross, redemptionNet });
      } catch {
        candidates.push({ amount, previewShares: 0n, redemptionGross: 0n, redemptionNet: 0n });
      }
      if (amount > configuredMaximum / 10n) break;
    }
    const selected = selectSmallestPracticalAmount(candidates, maxWithdrawalAmount);
    report.amountSelection = {
      reason: "Smallest base-unit candidate with nonzero deposit and instant-redemption previews below maxWithdrawalAmount",
      configuredMaximum,
      candidates,
      selected,
    };
    preflightPassed = true;
    report.status = "deposit_failed";

    account = privateKeyToAccount(parsePrivateKey(process.env.COSTON2_PRIVATE_KEY));
    const walletClient = createWalletClient({
      account,
      chain: coston2,
      transport: http(rpcUrl, { retryCount: 4, timeout: 20_000 }),
    });
    const amount = selected.amount;

    const [walletAssetsBefore, walletSharesBefore, nativeBalance] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
      publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
      publicClient.getBalance({ address: account.address }),
    ]);
    if (walletAssetsBefore < amount) throw new Error("Wallet FXRP balance is insufficient");
    if (nativeBalance === 0n) throw new Error("Wallet has no C2FLR for transaction fees");

    const [previewShares, previewReferenceAmount] = await publicClient.readContract({
      address: OFFICIAL_UPSHIFT_VAULT,
      abi: upshiftAbi,
      functionName: "previewDeposit",
      args: [OFFICIAL_FXRP, amount],
    });
    if (previewShares <= 0n) throw new Error("Deposit preview returned zero shares");
    const [withdrawalsPausedAfterKey, maxWithdrawalAfterKey, preflightRedemption] =
      await Promise.all([
        publicClient.readContract({
          address: OFFICIAL_UPSHIFT_VAULT,
          abi: upshiftAbi,
          functionName: "withdrawalsPaused",
        }),
        publicClient.readContract({
          address: OFFICIAL_UPSHIFT_VAULT,
          abi: upshiftAbi,
          functionName: "maxWithdrawalAmount",
        }),
        publicClient.readContract({
          address: OFFICIAL_UPSHIFT_VAULT,
          abi: upshiftAbi,
          functionName: "previewRedemption",
          args: [previewShares, true],
        }),
      ]);
    if (withdrawalsPausedAfterKey) throw new Error("Upshift withdrawals are paused");
    if (preflightRedemption[1] <= 0n) {
      throw new Error("Instant redemption preflight returned zero assets");
    }
    if (preflightRedemption[0] > maxWithdrawalAfterKey) {
      throw new Error("Instant redemption preview exceeds maxWithdrawalAmount");
    }
    report.before = { walletAssets: walletAssetsBefore, walletShares: walletSharesBefore };
    report.depositPreview = {
      shares: previewShares,
      amountInReferenceTokens: previewReferenceAmount,
    };
    report.redemptionPreflight = {
      withdrawalsPaused: withdrawalsPausedAfterKey,
      maxWithdrawalAmount: maxWithdrawalAfterKey,
      grossAssets: preflightRedemption[0],
      netAssets: preflightRedemption[1],
    };

    const [currentAssetAllowance, currentLpAllowance] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "allowance", args: [account.address, OFFICIAL_UPSHIFT_VAULT] }),
      publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "allowance", args: [account.address, OFFICIAL_UPSHIFT_VAULT] }),
    ]);
    report.allowancesBefore = { fxrp: currentAssetAllowance, lpToken: currentLpAllowance };
    if (currentAssetAllowance !== 0n) {
      const resetHash = await walletClient.writeContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, 0n] });
      const resetReceipt = await publicClient.waitForTransactionReceipt({ hash: resetHash });
      if (resetReceipt.status !== "success") throw new Error("Pre-test allowance reset failed");
      report.preflightAssetAllowanceReset = { transactionHash: resetHash, blockNumber: resetReceipt.blockNumber, confirmed: true };
    }
    const approvalHash = await walletClient.writeContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, amount] });
    assetApprovalTouched = true;
    const approvalReceipt = await publicClient.waitForTransactionReceipt({ hash: approvalHash });
    if (approvalReceipt.status !== "success") throw new Error("Exact-amount approval failed");
    const approvalReport: Record<string, unknown> = {
      amount,
      transactionHash: approvalHash,
      blockNumber: approvalReceipt.blockNumber,
      confirmed: true,
    };
    report.approval = approvalReport;
    const exactAllowance = await publicClient.readContract({
      address: OFFICIAL_FXRP,
      abi: tokenAbi,
      functionName: "allowance",
      args: [account.address, OFFICIAL_UPSHIFT_VAULT],
    });
    if (exactAllowance !== amount) {
      throw new Error(`Exact approval mismatch: allowance ${exactAllowance}, expected ${amount}`);
    }
    approvalReport.verifiedAllowance = exactAllowance;

    const depositHash = await walletClient.writeContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "deposit", args: [OFFICIAL_FXRP, amount, account.address] });
    const depositReceipt = await publicClient.waitForTransactionReceipt({ hash: depositHash });
    if (depositReceipt.status !== "success") throw new Error("Upshift deposit transaction reverted");
    depositConfirmed = true;
    report.status = "deposit_confirmed_redemption_failed";
    const depositReport: Record<string, unknown> = {
      amount,
      transactionHash: depositHash,
      blockNumber: depositReceipt.blockNumber,
      confirmed: true,
    };
    report.deposit = depositReport;
    const [walletAssetsAfterDeposit, walletSharesAfterDeposit] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
      publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
    ]);
    const sharesReceived = positiveDelta(walletSharesBefore, walletSharesAfterDeposit, "shares received");
    const assetsSpent = positiveDelta(walletAssetsAfterDeposit, walletAssetsBefore, "assets spent");
    if (assetsSpent !== amount) throw new Error(`Deposit balance mismatch: spent ${assetsSpent}, expected ${amount}`);
    depositReport.sharesReceived = sharesReceived;
    depositReport.walletAssetsAfter = walletAssetsAfterDeposit;
    depositReport.walletSharesAfter = walletSharesAfterDeposit;
    depositReport.sharePreviewDeviation = sharesReceived - previewShares;

    const [withdrawalsPausedBeforeRedeem, maxWithdrawalBeforeRedeem, configuredFee, redemptionPreview] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "withdrawalsPaused" }),
      publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "maxWithdrawalAmount" }),
      publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "instantRedemptionFee" }),
      publicClient.readContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "previewRedemption", args: [sharesReceived, true] }),
    ]);
    if (withdrawalsPausedBeforeRedeem) throw new Error("Upshift withdrawals paused after deposit");
    const [grossExpectedAssets, assetsAfterFee] = redemptionPreview;
    if (assetsAfterFee <= 0n) throw new Error("Redemption preview returned zero net assets");
    if (grossExpectedAssets > maxWithdrawalBeforeRedeem) throw new Error("Redemption preview exceeds refreshed maxWithdrawalAmount");
    let lpApprovalRequired = false;
    try {
      await publicClient.simulateContract({ account: account.address, address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "instantRedeem", args: [sharesReceived, account.address] });
    } catch (error) {
      if (!isAllowanceRelatedError(error)) throw error;
      lpApprovalRequired = true;
      if (currentLpAllowance !== 0n) {
        const lpResetHash = await walletClient.writeContract({ address: lpToken, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, 0n] });
        const lpResetReceipt = await publicClient.waitForTransactionReceipt({ hash: lpResetHash });
        if (lpResetReceipt.status !== "success") throw new Error("Pre-redemption LP allowance reset failed");
        report.preRedemptionLpAllowanceReset = { transactionHash: lpResetHash, blockNumber: lpResetReceipt.blockNumber, confirmed: true };
      }
      const lpApprovalHash = await walletClient.writeContract({ address: lpToken, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, sharesReceived] });
      lpApprovalTouched = true;
      const lpApprovalReceipt = await publicClient.waitForTransactionReceipt({ hash: lpApprovalHash });
      if (lpApprovalReceipt.status !== "success") throw new Error("LP approval failed");
      const lpApprovalReport: Record<string, unknown> = { required: true, amount: sharesReceived, transactionHash: lpApprovalHash, blockNumber: lpApprovalReceipt.blockNumber, confirmed: true };
      report.lpApproval = lpApprovalReport;
      const lpAllowance = await publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "allowance", args: [account.address, OFFICIAL_UPSHIFT_VAULT] });
      if (lpAllowance !== sharesReceived) throw new Error("Exact LP approval could not be verified");
      lpApprovalReport.verifiedAllowance = lpAllowance;
    }
    if (!lpApprovalRequired) report.lpApproval = { required: false, reason: "instantRedeem simulation succeeded with current LP allowance" };
    const redemptionHash = await walletClient.writeContract({ address: OFFICIAL_UPSHIFT_VAULT, abi: upshiftAbi, functionName: "instantRedeem", args: [sharesReceived, account.address] });
    const redemptionReceipt = await publicClient.waitForTransactionReceipt({ hash: redemptionHash });
    if (redemptionReceipt.status !== "success") throw new Error("Upshift instant redemption reverted");
    redemptionConfirmed = true;
    const redemptionReport: Record<string, unknown> = { method: "instantRedeem(uint256,address)", sharesRedeemed: sharesReceived, grossPreviewedAssets: grossExpectedAssets, netPreviewedAssets: assetsAfterFee, configuredFee, transactionHash: redemptionHash, blockNumber: redemptionReceipt.blockNumber, confirmed: true };
    report.redemption = redemptionReport;
    const [walletAssetsAfterRedemption, walletSharesAfterRedemption] = await Promise.all([
      publicClient.readContract({ address: OFFICIAL_FXRP, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
      publicClient.readContract({ address: lpToken, abi: tokenAbi, functionName: "balanceOf", args: [account.address] }),
    ]);
    const actualAssetsReturned = positiveDelta(walletAssetsAfterDeposit, walletAssetsAfterRedemption, "assets returned");
    if (walletSharesAfterRedemption !== walletSharesBefore) throw new Error("Share balances did not reconcile after redemption");
    reconciled = true;
    redemptionReport.actualAssetsReturned = actualAssetsReturned;
    redemptionReport.walletAssetsAfter = walletAssetsAfterRedemption;
    redemptionReport.walletSharesAfter = walletSharesAfterRedemption;
    redemptionReport.redemptionPreviewDeviation = actualAssetsReturned - assetsAfterFee;
    const roundTrip = calculateRoundTrip(amount, actualAssetsReturned);
    report.economics = {
      depositAmount: amount,
      previewedShares: previewShares,
      actualSharesReceived: sharesReceived,
      sharePreviewDeviation: sharesReceived - previewShares,
      previewAssetsBeforeFee: grossExpectedAssets,
      previewAssetsAfterFee: assetsAfterFee,
      actualAssetsReturned,
      redemptionPreviewDeviation: actualAssetsReturned - assetsAfterFee,
      depositToRedeemAbsoluteLoss: roundTrip.absoluteLoss,
      roundTripLossBps: roundTrip.roundTripLossBps,
      reportedInstantRedemptionFee: configuredFee,
      note: "Round-trip loss is not labeled as the instant redemption fee; it may include deposit pricing, explicit fee, and rounding.",
    };
    report.explorerUrls = { deposit: `${coston2.blockExplorers.default.url}/tx/${depositHash}`, redemption: `${coston2.blockExplorers.default.url}/tx/${redemptionHash}` };
  } catch (error) {
    report.error = error instanceof Error ? error.message : "Unknown smoke-test error";
    throw error;
  } finally {
    if (account && lpToken) {
      try {
        const cleanupAccount = account;
        const cleanupLpToken = lpToken;
        const walletClient = createWalletClient({ account: cleanupAccount, chain: coston2, transport: http(rpcUrl) });
        const cleanupTransactions: Array<Record<string, unknown>> = [];
        report.cleanupTransactions = cleanupTransactions;
        const cleanupToken = async (token: Address, label: string, touched: boolean) => {
          const before = await publicClient.readContract({ address: token, abi: tokenAbi, functionName: "allowance", args: [cleanupAccount.address, OFFICIAL_UPSHIFT_VAULT] });
          let transactionHash: Hash | undefined;
          let blockNumber: bigint | undefined;
          if (before !== 0n) {
            transactionHash = await walletClient.writeContract({ address: token, abi: tokenAbi, functionName: "approve", args: [OFFICIAL_UPSHIFT_VAULT, 0n] });
            const receipt = await publicClient.waitForTransactionReceipt({ hash: transactionHash });
            if (receipt.status !== "success") throw new Error("Allowance reset transaction reverted");
            blockNumber = receipt.blockNumber;
            cleanupTransactions.push({ token: label, transactionHash, blockNumber, confirmed: true });
          }
          const after = await publicClient.readContract({ address: token, abi: tokenAbi, functionName: "allowance", args: [cleanupAccount.address, OFFICIAL_UPSHIFT_VAULT] });
          return { touched, before, after, ...(transactionHash ? { transactionHash } : {}), ...(blockNumber ? { blockNumber } : {}) };
        };
        // Keep cleanup transactions sequential so one account never reuses a nonce.
        const fxrpCleanup = await cleanupToken(OFFICIAL_FXRP, "FTestXRP", assetApprovalTouched);
        const lpCleanup = await cleanupToken(cleanupLpToken, "Upshift LP", lpApprovalTouched);
        assertAllowancesZero(fxrpCleanup.after, lpCleanup.after);
        cleanupVerified = true;
        report.allowanceCleanup = { confirmed: cleanupVerified, fxrp: fxrpCleanup, lpToken: lpCleanup };
      } catch (cleanupError) {
        cleanupVerified = false;
        cleanupFailure = cleanupError instanceof Error ? cleanupError : new Error("Allowance cleanup failed");
        report.allowanceCleanup = { confirmed: false, error: cleanupFailure.message };
        report.error = `${String(report.error ?? "Protocol flow completed")}; allowance cleanup could not be verified`;
      }
    }
    report.status = deriveReportStatus({ preflightPassed, depositConfirmed, redemptionConfirmed, reconciled, cleanupVerified });
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
    console.error(error instanceof Error ? error.message : "Smoke test failed");
    process.exitCode = 1;
  });
}
