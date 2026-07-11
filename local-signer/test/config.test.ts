import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";

const valid = {
  SIGNER_PRIVATE_KEY: `0x${"11".repeat(32)}`,
  CHAIN_ID: "31337",
  VAULT_ADDRESS: "0x1000000000000000000000000000000000000001",
  INTENT_VERIFIER_ADDRESS: "0x2000000000000000000000000000000000000002",
};
const UINT256_MAX = (1n << 256n) - 1n;

describe("environment validation", () => {
  it.each(["SIGNER_PRIVATE_KEY", "CHAIN_ID", "VAULT_ADDRESS", "INTENT_VERIFIER_ADDRESS"])("requires %s", (key) => {
    const env = { ...valid } as Record<string, string | undefined>;
    delete env[key];
    expect(() => loadConfig(env)).toThrow(key);
  });

  it("rejects malformed required values and unsafe optional values", () => {
    expect(() => loadConfig({ ...valid, SIGNER_PRIVATE_KEY: "secret" })).toThrow("SIGNER_PRIVATE_KEY");
    expect(() => loadConfig({ ...valid, CHAIN_ID: "0" })).toThrow("CHAIN_ID");
    expect(() => loadConfig({ ...valid, VAULT_ADDRESS: "vault" })).toThrow("VAULT_ADDRESS");
    expect(() => loadConfig({ ...valid, VAULT_ADDRESS: "0x0000000000000000000000000000000000000000" })).toThrow("VAULT_ADDRESS");
    expect(() => loadConfig({ ...valid, INTENT_VERIFIER_ADDRESS: "0x0000000000000000000000000000000000000000" })).toThrow("INTENT_VERIFIER_ADDRESS");
    expect(() => loadConfig({ ...valid, FTSO_MAX_AGE_SECONDS: "-1" })).toThrow("FTSO_MAX_AGE_SECONDS");
    expect(() => loadConfig({ ...valid, CHAIN_ID: (UINT256_MAX + 1n).toString() })).toThrow("CHAIN_ID");
    expect(() => loadConfig({ ...valid, RESULT_TTL_SECONDS: (UINT256_MAX + 1n).toString() })).toThrow("RESULT_TTL_SECONDS");
    expect(() => loadConfig({ ...valid, LOG_PLAINTEXT_INTENT: "true", NODE_ENV: "production" })).toThrow("LOG_PLAINTEXT_INTENT");
    expect(() => loadConfig({ ...valid, LOG_PLAINTEXT_INTENT: "yes" })).toThrow("LOG_PLAINTEXT_INTENT");
  });

  it("applies strict defaults", () => {
    expect(loadConfig(valid)).toMatchObject({ chainId: 31337n, ftsoMaxAgeSeconds: 120n, resultTtlSeconds: 300n, logPlaintextIntent: false });
  });
});
