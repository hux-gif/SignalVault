import { randomBytes } from "node:crypto";
import { writeFileSync } from "node:fs";
import { privateKeyToAccount } from "viem/accounts";
import { computeIntentCommitment } from "../src/commitment.js";
import { createV2AllocationService } from "../src/service-v2.js";
import type { PlainIntent } from "../src/types.js";

const [output, priceArg, timestampArg] = process.argv.slice(2);
if (!output || !priceArg || !timestampArg) {
  throw new Error("usage: generate-live-coston2-result.ts OUTPUT PRICE TIMESTAMP");
}
const required = (name: string): string => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};
const signerKey = required("SIGNER_PRIVATE_KEY") as `0x${string}`;
const vault = "0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898" as const;
const verifier = "0x2C7b2a5620fbf25a65c81257F16b8437f5Af492a" as const;
const user = "0x7D0658b3722ca36580eCF10CCe0cB135B99939d4" as const;
const intent: PlainIntent = {
  riskLevel: 1,
  targetAprBps: 500,
  maxDrawdownBps: 500,
  rebalanceWindow: 3600,
  salt: `0x${randomBytes(32).toString("hex")}`,
};
const nonce = 1n;
const chainId = 114n;
const timestamp = BigInt(timestampArg);
const config = {
  privateKey: signerKey,
  signer: privateKeyToAccount(signerKey).address,
  chainId,
  vault,
  verifier,
  ftsoMaxAgeSeconds: 120n,
  resultTtlSeconds: 300n,
  logPlaintextIntent: false,
};
const intentCommitment = computeIntentCommitment(user, intent, nonce, chainId);
const service = createV2AllocationService(config, () => timestamp + 1n);
const signed = await service(
  {
    user,
    vault,
    intentVerifier: verifier,
    chainId,
    nonce,
    intentCommitment,
    plainIntent: intent,
    ftso: { price: BigInt(priceArg), timestamp },
  },
  {
    routerConfigHash: "0x202497cf161eef43d5bc473c227f33ecea8c74868f1cfab4ea71f1f555ccb00c",
    minimumPostNAV: 4_900_000n,
    maximumRebalanceLossBps: 100,
    maximumPreviewDeviationBps: 100,
    allocationToleranceBps: 100,
  },
);
writeFileSync(
  output,
  JSON.stringify({ intentCommitment, ftso: { price: priceArg, timestamp: timestampArg }, ...signed }, (_, value) =>
    typeof value === "bigint" ? value.toString() : value, 2),
  "utf8",
);
console.info(`wrote ${output}`);
