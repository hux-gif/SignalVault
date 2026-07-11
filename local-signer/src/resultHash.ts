import { encodeAbiParameters, keccak256, parseAbiParameters, type Hex } from "viem";
import type { TEEResult } from "./types.js";

type HashInput = Omit<TEEResult, "resultHash">;

export function computeResultHash(result: HashInput): Hex {
  return keccak256(encodeAbiParameters(
    parseAbiParameters("address,address,bytes32,uint16,uint16,uint16,uint16,uint256,uint256,uint256,uint256"),
    [result.user, result.vault, result.intentCommitment, result.upshiftBps, result.firelightBps,
      result.sparkdexBps, result.idleBps, result.nonce, result.deadline,
      result.ftsoPriceTimestamp, result.chainId],
  ));
}
