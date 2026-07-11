import { encodeAbiParameters, keccak256, parseAbiParameters, toHex, type Hex } from "viem";
import type { TEEResultV2 } from "./types.js";

const RESULT_V2_DOMAIN = keccak256(toHex("SIGNALVAULT_TEE_RESULT_V2"));

export type ResultHashInputV2 = Omit<TEEResultV2, "resultHash">;

export function computeResultHashV2(result: ResultHashInputV2): Hex {
  return keccak256(encodeAbiParameters(
    parseAbiParameters(
      "bytes32,address,address,bytes32,bytes32,bytes32,uint16,uint16,uint16,uint16,uint256,uint256,uint256,uint256,uint256,uint16,uint16,uint16",
    ),
    [
      RESULT_V2_DOMAIN,
      result.user,
      result.vault,
      result.intentCommitment,
      result.capabilityProfile,
      result.routerConfigHash,
      result.upshiftBps,
      result.firelightBps,
      result.sparkdexBps,
      result.idleBps,
      result.nonce,
      result.deadline,
      result.ftsoPriceTimestamp,
      result.chainId,
      result.minimumPostNAV,
      result.maximumRebalanceLossBps,
      result.maximumPreviewDeviationBps,
      result.allocationToleranceBps,
    ],
  ));
}
