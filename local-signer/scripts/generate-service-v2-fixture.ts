/**
 * Generates a deterministic V2 fixture using service-v2 (Coston2-constrained planner).
 *
 * The fixture is consumed by test/v2/ServiceV2Fixture.t.sol, which deploys
 * IntentVerifierV2 + SignalVaultV2 + StrategyRouterV2 at the fixture's addresses
 * and asserts that verifier.verifyTEEResult(result, signature) returns true.
 *
 * Run: npx tsx scripts/generate-service-v2-fixture.ts
 * Output: fixtures/service-v2-fixture.json
 */
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { computeIntentCommitment } from "../src/commitment.js";
import { createV2AllocationService } from "../src/service-v2.js";
import { computeRouterConfigHashV2 } from "../src/v2/configHash.js";
import { COSTON2_CAPABILITY_PROFILE } from "../src/v2/validation.js";
import type { PlainIntent } from "../src/types.js";

// Deterministic Anvil fixture addresses.
const USER = "0x3000000000000000000000000000000000000003" as const;
const VAULT = "0x1000000000000000000000000000000000000001" as const;
const VERIFIER = "0x2000000000000000000000000000000000000002" as const;
const ROUTER = "0x3000000000000000000000000000000000000004" as const;
const ASSET = "0x4000000000000000000000000000000000000005" as const;
const UPSHIFT_ADAPTER = "0x5000000000000000000000000000000000000006" as const;
const IDLE_ADAPTER = "0x6000000000000000000000000000000000000007" as const;
const CHAIN_ID = 31337n; // Anvil; service-v2 is chain-locked to 114 only for production, but the test fixture reuses the planner.
const PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;
const SIGNER = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as const;
const NOW = 1_999_999_000n;
const FTSO_TIMESTAMP = 1_999_998_950n;
const FTSO_PRICE = 100_000n;
const NONCE = 7n;
const INTENT_SALT = `0x${"44".repeat(32)}` as const;
const PLAIN_INTENT: PlainIntent = {
  riskLevel: 1,
  targetAprBps: 800,
  maxDrawdownBps: 500,
  rebalanceWindow: 3600,
  salt: INTENT_SALT,
};
const RISK = {
  minimumRebalanceInterval: 3600n,
  minimumAllocationChangeBps: 100,
  maximumRebalanceLossBps: 100,
  maximumPreviewDeviationBps: 100,
  allocationToleranceBps: 100,
};
const RISK_HASH = (await import("../src/v2/configHash.js")).computeRiskConfigurationHashV2(RISK);
const ROUTER_CONFIG = {
  chainId: CHAIN_ID,
  vault: VAULT,
  router: ROUTER,
  asset: ASSET,
  upshiftAdapter: UPSHIFT_ADAPTER,
  idleAdapter: IDLE_ADAPTER,
  capabilityProfile: COSTON2_CAPABILITY_PROFILE,
  riskConfigurationHash: RISK_HASH,
  version: 1n,
};
const ROUTER_CONFIG_HASH = computeRouterConfigHashV2(ROUTER_CONFIG);

// Bypass the chainId=114 lock for this Anvil fixture by constructing the signer
// service against a chainId=31337 config. The Coston2 lock is a production safety
// guard; for Anvil fixtures we override it via a local config.
const config = {
  privateKey: PRIVATE_KEY,
  signer: SIGNER,
  chainId: CHAIN_ID,
  vault: VAULT,
  verifier: VERIFIER,
  ftsoMaxAgeSeconds: 120n,
  resultTtlSeconds: 300n,
  logPlaintextIntent: false,
};

// We need a V2SignerContext that matches what the Foundry test will deploy.
const ctx = {
  routerConfigHash: ROUTER_CONFIG_HASH,
  minimumPostNAV: 1_000_000_000_000_000_000n,
  maximumRebalanceLossBps: RISK.maximumRebalanceLossBps,
  maximumPreviewDeviationBps: RISK.maximumPreviewDeviationBps,
  allocationToleranceBps: RISK.allocationToleranceBps,
};

const intentCommitment = computeIntentCommitment(USER, PLAIN_INTENT, NONCE, CHAIN_ID);
const input = {
  user: USER,
  vault: VAULT,
  intentVerifier: VERIFIER,
  chainId: CHAIN_ID,
  nonce: NONCE,
  intentCommitment,
  plainIntent: PLAIN_INTENT,
  ftso: { price: FTSO_PRICE, timestamp: FTSO_TIMESTAMP },
};

// Override only the expected chain for this deterministic Anvil fixture. The
// production constructor defaults to Coston2 (114).
const service = createV2AllocationService(config, () => NOW, CHAIN_ID);
const { result, signature } = await service(input, ctx);

const fixture = {
  testOnly: true,
  description: "service-v2 produced V2 result + signature, consumed by ServiceV2Fixture.t.sol",
  generatedBy: "local-signer/scripts/generate-service-v2-fixture.ts",
  generatedAt: new Date().toISOString(),
  chainId: CHAIN_ID.toString(),
  now: NOW.toString(),
  plainIntent: PLAIN_INTENT,
  riskConfiguration: {
    minimumRebalanceInterval: RISK.minimumRebalanceInterval.toString(),
    minimumAllocationChangeBps: RISK.minimumAllocationChangeBps.toString(),
    maximumRebalanceLossBps: RISK.maximumRebalanceLossBps.toString(),
    maximumPreviewDeviationBps: RISK.maximumPreviewDeviationBps.toString(),
    allocationToleranceBps: RISK.allocationToleranceBps.toString(),
  },
  routerConfiguration: {
    chainId: CHAIN_ID.toString(),
    vault: VAULT,
    router: ROUTER,
    asset: ASSET,
    upshiftAdapter: UPSHIFT_ADAPTER,
    idleAdapter: IDLE_ADAPTER,
    capabilityProfile: COSTON2_CAPABILITY_PROFILE,
    riskConfigurationHash: RISK_HASH,
    version: "1",
  },
  expected: {
    signer: SIGNER,
    riskConfigurationHash: RISK_HASH,
    routerConfigHash: ROUTER_CONFIG_HASH,
    intentCommitment,
  },
  input: {
    user: USER,
    vault: VAULT,
    intentVerifier: VERIFIER,
    nonce: NONCE.toString(),
    ftso: { price: FTSO_PRICE.toString(), timestamp: FTSO_TIMESTAMP.toString() },
  },
  result: {
    user: result.user,
    vault: result.vault,
    intentCommitment: result.intentCommitment,
    capabilityProfile: result.capabilityProfile,
    routerConfigHash: result.routerConfigHash,
    upshiftBps: result.upshiftBps.toString(),
    firelightBps: result.firelightBps.toString(),
    sparkdexBps: result.sparkdexBps.toString(),
    idleBps: result.idleBps.toString(),
    nonce: result.nonce.toString(),
    deadline: result.deadline.toString(),
    ftsoPriceTimestamp: result.ftsoPriceTimestamp.toString(),
    chainId: result.chainId.toString(),
    minimumPostNAV: result.minimumPostNAV.toString(),
    maximumRebalanceLossBps: result.maximumRebalanceLossBps.toString(),
    maximumPreviewDeviationBps: result.maximumPreviewDeviationBps.toString(),
    allocationToleranceBps: result.allocationToleranceBps.toString(),
    resultHash: result.resultHash,
  },
  signature,
};

const outPath = resolve(import.meta.dirname, "../../fixtures/service-v2-fixture.json");
writeFileSync(outPath, `${JSON.stringify(fixture, null, 2)}\n`, "utf8");
console.info(`Wrote ${outPath}`);
console.info(`resultHash=${result.resultHash}`);
console.info(`signer=${SIGNER}`);
console.info(`signature=${signature}`);
