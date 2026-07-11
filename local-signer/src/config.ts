import { getAddress, isAddress, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";

export interface SignerConfig {
  privateKey: Hex;
  signer: Address;
  chainId: bigint;
  vault: Address;
  verifier: Address;
  ftsoMaxAgeSeconds: bigint;
  resultTtlSeconds: bigint;
  logPlaintextIntent: boolean;
}

function required(env: Record<string, string | undefined>, key: string): string {
  const value = env[key];
  if (!value) throw new Error(`${key} is required`);
  return value;
}

function positiveInteger(value: string, key: string): bigint {
  if (!/^[1-9]\d*$/.test(value)) throw new Error(`${key} must be a positive integer`);
  return BigInt(value);
}

function address(value: string, key: string): Address {
  if (!isAddress(value)) throw new Error(`${key} must be a valid address`);
  return getAddress(value);
}

export function loadConfig(env: Record<string, string | undefined> = process.env): SignerConfig {
  const rawKey = required(env, "SIGNER_PRIVATE_KEY");
  if (!/^0x[0-9a-fA-F]{64}$/.test(rawKey) || /^0x0{64}$/.test(rawKey)) {
    throw new Error("SIGNER_PRIVATE_KEY must be a non-zero 32-byte hex private key");
  }
  const privateKey = rawKey as Hex;
  const maxAge = env.FTSO_MAX_AGE_SECONDS ?? "120";
  const ttl = env.RESULT_TTL_SECONDS ?? "300";
  const logPlaintextIntent = env.LOG_PLAINTEXT_INTENT === "true";
  if (logPlaintextIntent && env.NODE_ENV !== "development") {
    throw new Error("LOG_PLAINTEXT_INTENT may only be enabled in development");
  }
  return {
    privateKey,
    signer: privateKeyToAccount(privateKey).address,
    chainId: positiveInteger(required(env, "CHAIN_ID"), "CHAIN_ID"),
    vault: address(required(env, "VAULT_ADDRESS"), "VAULT_ADDRESS"),
    verifier: address(required(env, "INTENT_VERIFIER_ADDRESS"), "INTENT_VERIFIER_ADDRESS"),
    ftsoMaxAgeSeconds: positiveInteger(maxAge, "FTSO_MAX_AGE_SECONDS"),
    resultTtlSeconds: positiveInteger(ttl, "RESULT_TTL_SECONDS"),
    logPlaintextIntent,
  };
}
