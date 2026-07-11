import type { Address, Hex } from "viem";

export interface AllocationV2 {
  upshiftBps: number;
  firelightBps: number;
  sparkdexBps: number;
  idleBps: number;
}

export interface RebalanceLimitsV2 {
  minimumPostNAV: bigint;
  maximumRebalanceLossBps: number;
  maximumPreviewDeviationBps: number;
  allocationToleranceBps: number;
}

export interface RiskConfigurationV2 {
  minimumRebalanceInterval: bigint;
  minimumAllocationChangeBps: number;
  maximumRebalanceLossBps: number;
  maximumPreviewDeviationBps: number;
  allocationToleranceBps: number;
}

/** The exact flattened EIP-712 message signed by IntentVerifierV2. */
export interface TEEResultV2 extends AllocationV2, RebalanceLimitsV2 {
  user: Address;
  vault: Address;
  intentCommitment: Hex;
  capabilityProfile: Hex;
  routerConfigHash: Hex;
  nonce: bigint;
  deadline: bigint;
  ftsoPriceTimestamp: bigint;
  chainId: bigint;
  resultHash: Hex;
}

export interface AllocateRequestV2 extends Omit<TEEResultV2, "resultHash"> {
  intentVerifier: Address;
}

export interface V2ValidationContext {
  chainId: bigint;
  vault: Address;
  intentVerifier: Address;
  capabilityProfile: Hex;
  routerConfigHash: Hex;
}

export interface RouterConfigurationV2 {
  chainId: bigint;
  vault: Address;
  router: Address;
  asset: Address;
  upshiftAdapter: Address;
  idleAdapter: Address;
  capabilityProfile: Hex;
  riskConfigurationHash: Hex;
  version: bigint;
}
