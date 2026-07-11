import type { Address, Hex } from "viem";

export type RiskLevel = 0 | 1 | 2;

export interface PlainIntent {
  riskLevel: RiskLevel;
  targetAprBps: number;
  maxDrawdownBps: number;
  rebalanceWindow: number;
  salt: Hex;
}

export interface FtsoValue {
  price: bigint;
  timestamp: bigint;
}

export interface Allocation {
  upshiftBps: number;
  firelightBps: number;
  sparkdexBps: number;
  idleBps: number;
}

export interface AllocateInput {
  user: Address;
  vault: Address;
  intentVerifier: Address;
  chainId: bigint;
  nonce: bigint;
  intentCommitment: Hex;
  plainIntent: PlainIntent;
  ftso: FtsoValue;
}

export interface TEEResult extends Allocation {
  user: Address;
  vault: Address;
  intentCommitment: Hex;
  nonce: bigint;
  deadline: bigint;
  ftsoPriceTimestamp: bigint;
  chainId: bigint;
  resultHash: Hex;
}

export interface AllocateResponse {
  result: TEEResult;
  signature: Hex;
}
