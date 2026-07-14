// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2
} from "../types/SignalVaultTypesV2.sol";

enum RouterStateV2 {
    Operational,
    UpshiftUnavailable,
    UpshiftRecovered
}

enum RebalanceBlockerV2 {
    None,
    ConfigurationNotFrozen,
    ExecutionPaused,
    InvalidAllocation,
    InvalidSignedLimits,
    ChangeBelowMinimum,
    CooldownActive,
    UpshiftUnavailable,
    InsufficientLiquidity,
    ZeroPreview,
    SolverDidNotConverge,
    PreviewOutsideTolerance,
    RecoveredTargetForbidden
}

struct AllocationSnapshotV2 {
    uint256 totalNetAssets;
    uint256 totalGrossAssets;
    uint256 routerDirectAssets;
    uint256 idleAssets;
    uint256 upshiftDirectAssets;
    uint256 upshiftPositionNetAssets;
    uint256 upshiftPositionGrossAssets;
    uint256 upshiftPositionShares;
    uint16 idleBps;
    uint16 upshiftBps;
}

struct RebalancePlanV2 {
    uint256 totalAssetsBefore;
    uint256 projectedTotalAssetsAfter;
    uint256 routerAssetsBefore;
    uint256 idleAssetsBefore;
    uint256 upshiftDirectAssetsBefore;
    uint256 upshiftPositionAssetsBefore;
    uint256 targetIdleAssets;
    uint256 targetUpshiftAssets;
    uint256 idleWithdrawAssets;
    uint256 upshiftLiquidWithdrawAssets;
    uint256 upshiftSharesToRedeem;
    uint256 previewedUpshiftAssetsOut;
    uint256 upshiftMinAssetsOut;
    uint256 idleDepositAssets;
    uint256 upshiftDepositAssets;
    uint256 previewedUpshiftSharesOut;
    uint256 previewedUpshiftNetAdded;
    uint256 requiredProtocolLiquidity;
    bool feasible;
    RebalanceBlockerV2 blocker;
}

/// @notice Frozen runtime ABI for the one-Vault, one-asset V2 strategy Router.
interface IStrategyRouterV2 {
    error ZeroAddress();
    error UnauthorizedConfigurator();
    error OnlyVault();
    error ConfigurationAlreadySet();
    error ConfigurationIncomplete();
    error ConfigurationFrozen();
    error AdapterAssetMismatch();
    error AdapterRouterMismatch();
    error DuplicateAdapter();
    error VaultOwnerMismatch();
    error InvalidBps();
    error InvalidRiskConfiguration();
    error InvalidAllocation();
    error InvalidSignedLimits();
    error ExecutionPaused();
    error CooldownActive(uint256 earliestTimestamp);
    error RebalanceInfeasible(RebalanceBlockerV2 blocker);
    error FundingMismatch(uint256 declaredFunding, uint256 availableFunding);
    error PreviewDeviationExceeded();
    error AllocationToleranceExceeded();
    error MinimumPostNAVNotMet(uint256 minimum, uint256 actual);
    error RebalanceLossExceeded(uint256 maximumLoss, uint256 actualLoss);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error AssetDeltaMismatch();
    error AdapterDeltaMismatch();
    error AllowanceNotCleared();
    error RecoveryRequiresPause();
    error PositionAlreadyRecovered();
    error RecoveredTargetForbidden();
    error ResidualAssets();
    error ResidualPosition();

    event AllocationExecuted(
        bytes32 indexed executionId,
        uint16 idleBps,
        uint16 upshiftBps,
        uint256 totalAssetsBefore,
        uint256 totalAssetsAfter,
        uint256 lossAssets
    );
    event AllocationSkipped(
        bytes32 indexed executionId, uint16 idleBps, uint16 upshiftBps, uint256 totalAssets
    );
    event AssetsWithdrawnToVault(
        uint256 requestedAssets,
        uint256 deliveredAssets,
        uint256 routerDirectUsed,
        uint256 idleAssetsUsed,
        uint256 upshiftDirectUsed,
        uint256 upshiftSharesRedeemed,
        uint256 upshiftAssetsReceived
    );
    event AdapterPositionRecovered(
        address indexed positionToken, uint256 sharesRecovered, address indexed receiver
    );
    event ExecutionPauseUpdated(bool paused);

    function asset() external view returns (address);
    function vaultOwner() external view returns (address);
    function vault() external view returns (address);
    function idleAdapter() external view returns (address);
    function upshiftAdapter() external view returns (address);

    function capabilityProfile() external pure returns (bytes32);
    function routerConfigVersion() external pure returns (uint256);
    function riskConfiguration() external view returns (RiskConfigurationV2 memory);
    function riskConfigurationHash() external view returns (bytes32);
    function routerConfigHash() external view returns (bytes32);
    function configurationFrozen() external view returns (bool);

    function executionPaused() external view returns (bool);
    function upshiftRecovered() external view returns (bool);
    function strategyState() external view returns (RouterStateV2);
    function lastRebalanceTimestamp() external view returns (uint256);

    function totalAssets() external view returns (uint256 netAssets);
    function grossAssets() external view returns (uint256 grossAssets_);
    function availableLiquidity() external view returns (uint256 liquidAssets);
    function allocation() external view returns (AllocationSnapshotV2 memory snapshot);

    function previewRebalance(AllocationV2 calldata target, RebalanceLimitsV2 calldata limits)
        external
        view
        returns (RebalancePlanV2 memory plan);

    function rebalance(
        bytes32 executionId,
        AllocationV2 calldata target,
        RebalanceLimitsV2 calldata limits,
        uint256 fundingAssets
    ) external returns (uint256 totalAssetsAfter);

    function withdrawToVault(uint256 assets) external returns (uint256 assetsDelivered);
    function withdrawAllToVault() external returns (uint256 assetsDelivered);
    function recoverAdapterPosition() external returns (uint256 sharesRecovered);
    function setExecutionPaused(bool paused) external;
}
