import { encodeAbiParameters, keccak256, parseAbiParameters, toHex, type Hex } from "viem";
import type { RiskConfigurationV2, RouterConfigurationV2 } from "./types.js";

const RISK_CONFIG_V1_DOMAIN = keccak256(toHex("SIGNALVAULT_ROUTER_RISK_CONFIG_V1"));
const ROUTER_CONFIG_V1_DOMAIN = keccak256(toHex("SIGNALVAULT_ROUTER_CONFIG_V1"));

export function computeRiskConfigurationHashV2(configuration: RiskConfigurationV2): Hex {
  return keccak256(encodeAbiParameters(
    parseAbiParameters("bytes32,uint64,uint16,uint16,uint16,uint16"),
    [
      RISK_CONFIG_V1_DOMAIN,
      configuration.minimumRebalanceInterval,
      configuration.minimumAllocationChangeBps,
      configuration.maximumRebalanceLossBps,
      configuration.maximumPreviewDeviationBps,
      configuration.allocationToleranceBps,
    ],
  ));
}

export function computeRouterConfigHashV2(configuration: RouterConfigurationV2): Hex {
  return keccak256(encodeAbiParameters(
    parseAbiParameters("bytes32,uint256,address,address,address,address,address,bytes32,bytes32,uint256"),
    [
      ROUTER_CONFIG_V1_DOMAIN,
      configuration.chainId,
      configuration.vault,
      configuration.router,
      configuration.asset,
      configuration.upshiftAdapter,
      configuration.idleAdapter,
      configuration.capabilityProfile,
      configuration.riskConfigurationHash,
      configuration.version,
    ],
  ));
}
