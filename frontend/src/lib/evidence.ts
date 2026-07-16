import { coston2 } from "./chains";

export const EXPLORER_BASE_URL = coston2.blockExplorers.default.url;
export const GITHUB_URL = "https://github.com/hux-gif/SignalVault";

export const contracts = [
  { name: "IntentVerifierV2", address: "0x2C7b2a5620fbf25a65c81257F16b8437f5Af492a", detail: "EIP-712 + policy binding" },
  { name: "SignalVaultV2", address: "0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898", detail: "Personal FXRP vault" },
  { name: "StrategyRouterV2", address: "0x1d64CE2a9293F248a7298135932bE9674d39a764", detail: "Fee-aware differential execution" },
  { name: "IdleAdapterV2", address: "0xD0Ee1664e21aE9529f6cCCf94A70C29C7396fFD8", detail: "Liquid FXRP allocation" },
  { name: "UpshiftAdapterV2", address: "0x6bF0f5f7e9595171246C888F9AC10c830e1D81Db", detail: "Real Upshift LP position" },
] as const;

export const evidence = {
  chainId: 114,
  commitment: "0x47e61755b5d332dafc542b52dce6705bd1ae079953b9121efe8563e6e2205e84",
  deadline: 1_784_184_425,
  executionId: "0x68f2749b7b7979f0d4edcbca1e5d2d3dcf397848cec326531c4e6e0ca1468110",
  ftsoTimestamp: 1_784_184_124,
  ftsoValue: 660_964,
  idleBps: 5_000,
  nonce: 1,
  resultHash: "0x68f2749b7b7979f0d4edcbca1e5d2d3dcf397848cec326531c4e6e0ca1468110",
  routerConfigHash: "0x202497cf161eef43d5bc473c227f33ecea8c74868f1cfab4ea71f1f555ccb00c",
  trustedSigner: "0x9cf07d4810D8245Ac30677cCe5BE1Da7d2D43684",
  upshiftBps: 5_000,
} as const;

export const recordedSnapshot = {
  availableLiquidity: 3_990_000n,
  grossAssets: 4_002_499n,
  idleBps: evidence.idleBps,
  netAssets: 3_990_000n,
  upshiftBps: evidence.upshiftBps,
} as const;

export const transactions = [
  {
    block: 32_912_473,
    receiptRows: [
      ["Amount", "5.000000 FXRP"],
      ["Destination", "SignalVaultV2"],
    ],
    index: "01",
    label: "Deposit",
    detail: "5.000000 FXRP entered SignalVaultV2",
    hash: "0x245f207e77f19c3246e84c1df7f1e33794af124263ceffe07850832008376d79",
  },
  {
    block: 32_912_587,
    receiptRows: [
      ["Published", "Salted commitment"],
      ["Withheld", "Original strategy"],
    ],
    index: "02",
    label: "Private commitment",
    detail: "A salted commitment was published. The original strategy remained offchain.",
    hash: "0x8424df2d4833dd07521c529654b3df54a77291fbcd8141cf77fc31d253dcdd27",
  },
  {
    block: 32_912_595,
    receiptRows: [
      ["Allocation", "50% Idle / 50% Upshift"],
      ["Result hash", "0x68f2749b…a1468110"],
    ],
    index: "03",
    label: "Execution",
    detail: "Signed Mode B result authenticated onchain. Idle / Upshift allocation: 50 / 50.",
    hash: "0xe38ed07e2f77a03b29cc6ba57bc09cfbc2e18f8eda43a7819510f2b019ec2d23",
  },
  {
    block: 32_912_651,
    receiptRows: [
      ["Shares redeemed", "1,000,000"],
      ["FXRP returned", "997,500 base units"],
    ],
    index: "04",
    label: "Withdrawal",
    detail: "1,000,000 shares redeemed. 997,500 FXRP base units returned.",
    hash: "0xe550cd5bde1ae67f15e1ae29f16eaeefe08a1410d18dde9a889a7872d790d1ba",
  },
] as const;

export type EvidenceTransaction = (typeof transactions)[number];

export type RpcState = "degraded" | "live" | "loading";

export interface LiveSnapshot {
  availableLiquidity: bigint;
  grossAssets: bigint;
  idleBps: number;
  netAssets: bigint;
  upshiftBps: number;
}

export function formatAddress(value: string, lead = 6, tail = 4) {
  return `${value.slice(0, lead)}…${value.slice(-tail)}`;
}

export function formatFxrp(value: bigint) {
  const whole = value / 1_000_000n;
  const fraction = (value % 1_000_000n).toString().padStart(6, "0");
  return `${whole.toLocaleString()}.${fraction}`;
}

export function formatTimestamp(value: number) {
  return new Intl.DateTimeFormat("en", {
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    month: "short",
    timeZone: "UTC",
    timeZoneName: "short",
  }).format(new Date(value * 1_000));
}

export function formatAge(value: number) {
  const seconds = Math.max(0, Math.floor(Date.now() / 1_000) - value);
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3_600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3_600)}h`;
  return `${Math.floor(seconds / 86_400)}d`;
}
