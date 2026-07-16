import { createPublicClient, http, parseAbi } from "viem";
import { coston2 } from "./chains";

export const publicClient = createPublicClient({
  chain: coston2,
  transport: http(),
});

export const SIGNALVAULT_V2_ABI = parseAbi([
  "function totalAssets() view returns (uint256)",
  "function vaultOwner() view returns (address)",
  "function router() view returns (address)",
  "function asset() view returns (address)",
  "function userIntentNonce() view returns (uint256)",
  "function latestIntentCommitment() view returns (bytes32)",
  "function deposit(uint256 assets) returns (uint256 shares)",
  "function withdraw(uint256 shares) returns (uint256 assets)",
  "function submitPrivateIntent(bytes32 intentCommitment, uint256 nonce)",
  "function executeAuthenticatedRebalance((address user,address vault,bytes32 intentCommitment,bytes32 capabilityProfile,bytes32 routerConfigHash,(uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps) allocation,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,(uint256 minimumPostNAV,uint16 maximumRebalanceLossBps,uint16 maximumPreviewDeviationBps,uint16 allocationToleranceBps) limits,bytes32 resultHash) result, bytes signature)",
  "function closeVault() returns (uint256 assetsDelivered)",
  "event Deposited(address indexed user, uint256 assets, uint256 shares)",
  "event Withdrawn(address indexed user, uint256 assets, uint256 shares)",
  "event AuthenticatedRebalanceExecuted(address indexed user, bytes32 indexed resultHash, uint256 totalAssetsAfter)",
]);

export const STRATEGY_ROUTER_V2_ABI = parseAbi([
  "function totalAssets() view returns (uint256)",
  "function grossAssets() view returns (uint256)",
  "function availableLiquidity() view returns (uint256)",
  "function allocation() view returns ((uint256 totalNetAssets, uint256 totalGrossAssets, uint256 routerDirectAssets, uint256 idleAssets, uint256 upshiftDirectAssets, uint256 upshiftPositionNetAssets, uint256 upshiftPositionGrossAssets, uint256 upshiftPositionShares, uint16 idleBps, uint16 upshiftBps))",
  "function strategyState() view returns (uint8)",
  "function executionPaused() view returns (bool)",
  "function upshiftRecovered() view returns (bool)",
  "function routerConfigHash() view returns (bytes32)",
  "function riskConfigurationHash() view returns (bytes32)",
  "event AllocationExecuted(bytes32 indexed executionId, uint16 idleBps, uint16 upshiftBps, uint256 totalAssetsBefore, uint256 totalAssetsAfter, uint256 lossAssets)",
  "event AllocationSkipped(bytes32 indexed executionId, uint16 idleBps, uint16 upshiftBps, uint256 totalAssets)",
]);
