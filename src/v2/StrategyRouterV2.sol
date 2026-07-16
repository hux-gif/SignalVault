// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyAdapterV2} from "./interfaces/IStrategyAdapterV2.sol";
import {IStrategyRecoveryV2} from "./interfaces/IStrategyRecoveryV2.sol";
import {
    AllocationSnapshotV2,
    RebalanceBlockerV2,
    RebalancePlanV2,
    RouterStateV2
} from "./interfaces/IStrategyRouterV2.sol";
import {AllocationV2, RebalanceLimitsV2, RiskConfigurationV2} from "./types/SignalVaultTypesV2.sol";
import {SignalVaultHashesV2} from "./libraries/SignalVaultHashesV2.sol";

interface IRouterBoundAdapterV2 {
    function router() external view returns (address);
}

interface IRouterBoundVaultV2 {
    function vaultOwner() external view returns (address);
}

/// @notice One-asset V2 strategy Router. Task 1 freezes deployment identities and configuration;
/// runtime accounting and execution are introduced by later independently reviewed tasks.
contract StrategyRouterV2 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 private constant _BPS_DENOMINATOR = 10_000;

    struct IncreaseContextV2 {
        AllocationSnapshotV2 snapshot;
        uint256 directBuffer;
        uint16 targetIdleBps;
        uint16 toleranceBps;
    }

    struct DecreaseContextV2 {
        AllocationSnapshotV2 snapshot;
        uint256 directBuffer;
        uint256 positionLiquidity;
        uint256 achievedNetReduction;
        uint16 targetIdleBps;
        uint16 toleranceBps;
        uint16 previewDeviationBps;
    }

    struct WithdrawalReceiptV2 {
        uint256 routerDirectUsed;
        uint256 idleAssetsUsed;
        uint256 upshiftDirectUsed;
        uint256 upshiftSharesRedeemed;
        uint256 upshiftAssetsReceived;
    }

    IERC20 public immutable asset;
    address public immutable vaultOwner;

    address public vault;
    address public idleAdapter;
    address public upshiftAdapter;

    bytes32 public riskConfigurationHash;
    bytes32 public routerConfigHash;
    bool public configurationFrozen;
    bool public executionPaused;
    bool public upshiftRecovered;

    bool private _adaptersConfigured;
    bool private _riskConfigured;
    RiskConfigurationV2 private _riskConfiguration;
    uint256 public lastRebalanceTimestamp;

    error ZeroAddress();
    error UnauthorizedConfigurator();
    error ConfigurationAlreadySet();
    error AdapterAssetMismatch();
    error AdapterRouterMismatch();
    error DuplicateAdapter();
    error InvalidBps();
    error InvalidRiskConfiguration();
    error ConfigurationIncomplete();
    error ConfigurationFrozen();
    error VaultOwnerMismatch();
    error OnlyVault();
    error RebalanceInfeasible(RebalanceBlockerV2 blocker);
    error FundingMismatch(uint256 declaredFunding, uint256 availableFunding);
    error AssetDeltaMismatch();
    error AdapterDeltaMismatch();
    error AllowanceNotCleared();
    error PreviewDeviationExceeded();
    error AllocationToleranceExceeded();
    error MinimumPostNAVNotMet(uint256 minimum, uint256 actual);
    error RebalanceLossExceeded(uint256 maximumLoss, uint256 actualLoss);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error ResidualAssets();
    error ResidualPosition();
    error RecoveryRequiresPause();
    error PositionAlreadyRecovered();
    error RecoveredTargetForbidden();

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

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(IERC20 asset_, address vaultOwner_) {
        if (address(asset_) == address(0) || vaultOwner_ == address(0)) revert ZeroAddress();
        asset = asset_;
        vaultOwner = vaultOwner_;
    }

    function configureAdapters(address upshiftAdapter_, address idleAdapter_) external {
        _requireConfigurator();
        _requireMutable();
        if (_adaptersConfigured) revert ConfigurationAlreadySet();
        if (upshiftAdapter_ == address(0) || idleAdapter_ == address(0)) revert ZeroAddress();
        if (upshiftAdapter_ == idleAdapter_) revert DuplicateAdapter();

        if (
            IStrategyAdapterV2(upshiftAdapter_).asset() != address(asset)
                || IStrategyAdapterV2(idleAdapter_).asset() != address(asset)
                || IStrategyAdapterV2(idleAdapter_).positionToken() != address(asset)
        ) revert AdapterAssetMismatch();
        if (
            IRouterBoundAdapterV2(upshiftAdapter_).router() != address(this)
                || IRouterBoundAdapterV2(idleAdapter_).router() != address(this)
        ) revert AdapterRouterMismatch();

        upshiftAdapter = upshiftAdapter_;
        idleAdapter = idleAdapter_;
        _adaptersConfigured = true;
    }

    function configureRisk(RiskConfigurationV2 calldata riskConfiguration_) external {
        _requireConfigurator();
        _requireMutable();
        if (_riskConfigured) revert ConfigurationAlreadySet();
        if (
            riskConfiguration_.minimumAllocationChangeBps > _BPS_DENOMINATOR
                || riskConfiguration_.maximumRebalanceLossBps > _BPS_DENOMINATOR
                || riskConfiguration_.maximumPreviewDeviationBps > _BPS_DENOMINATOR
                || riskConfiguration_.allocationToleranceBps > _BPS_DENOMINATOR
        ) revert InvalidBps();
        if (
            riskConfiguration_.allocationToleranceBps
                > riskConfiguration_.minimumAllocationChangeBps
        ) revert InvalidRiskConfiguration();

        _riskConfiguration = riskConfiguration_;
        _riskConfigured = true;
    }

    function riskConfiguration() external view returns (RiskConfigurationV2 memory) {
        return _riskConfiguration;
    }

    function capabilityProfile() external pure returns (bytes32) {
        return keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1");
    }

    function routerConfigVersion() external pure returns (uint256) {
        return 1;
    }

    function bindVault(address vault_) external {
        _requireConfigurator();
        _requireMutable();
        if (!_adaptersConfigured || !_riskConfigured) revert ConfigurationIncomplete();
        if (vault_ == address(0)) revert ZeroAddress();
        if (IRouterBoundVaultV2(vault_).vaultOwner() != vaultOwner) revert VaultOwnerMismatch();

        vault = vault_;
        riskConfigurationHash = SignalVaultHashesV2.computeRiskConfigurationHash(_riskConfiguration);
        routerConfigHash = SignalVaultHashesV2.computeRouterConfigHash(
            block.chainid,
            vault_,
            address(this),
            address(asset),
            upshiftAdapter,
            idleAdapter,
            keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1"),
            riskConfigurationHash,
            1
        );
        configurationFrozen = true;
    }

    function totalAssets() external view returns (uint256 netAssets) {
        if (!_adaptersConfigured) revert ConfigurationIncomplete();

        uint256 routerDirect = asset.balanceOf(address(this));
        uint256 idleDirect = asset.balanceOf(idleAdapter);
        uint256 idleNet = IStrategyAdapterV2(idleAdapter).totalAssets();
        uint256 upshiftDirect = asset.balanceOf(upshiftAdapter);
        uint256 upshiftNet =
            upshiftRecovered ? upshiftDirect : IStrategyAdapterV2(upshiftAdapter).totalAssets();
        if (idleNet < idleDirect || upshiftNet < upshiftDirect) revert AdapterDeltaMismatch();

        return routerDirect + idleNet + upshiftNet;
    }

    function grossAssets() external view returns (uint256 grossAssets_) {
        if (!_adaptersConfigured) revert ConfigurationIncomplete();

        uint256 routerDirect = asset.balanceOf(address(this));
        uint256 idleDirect = asset.balanceOf(idleAdapter);
        uint256 idleGross = IStrategyAdapterV2(idleAdapter).grossAssets();
        uint256 upshiftDirect = asset.balanceOf(upshiftAdapter);
        uint256 upshiftGross =
            upshiftRecovered ? upshiftDirect : IStrategyAdapterV2(upshiftAdapter).grossAssets();
        if (idleGross < idleDirect || upshiftGross < upshiftDirect) {
            revert AdapterDeltaMismatch();
        }

        return routerDirect + idleGross + upshiftGross;
    }

    function availableLiquidity() external view returns (uint256 liquidAssets) {
        if (!_adaptersConfigured) revert ConfigurationIncomplete();

        uint256 routerDirect = asset.balanceOf(address(this));
        uint256 idleDirect = asset.balanceOf(idleAdapter);
        uint256 idleLiquidity = IStrategyAdapterV2(idleAdapter).availableLiquidity();
        uint256 upshiftDirect = asset.balanceOf(upshiftAdapter);
        RouterStateV2 state = strategyState();
        uint256 upshiftLiquidity;
        if (state == RouterStateV2.Operational) {
            upshiftLiquidity = IStrategyAdapterV2(upshiftAdapter).availableLiquidity();
            if (upshiftLiquidity < upshiftDirect) revert AdapterDeltaMismatch();
        } else if (state == RouterStateV2.UpshiftRecovered) {
            upshiftLiquidity = upshiftDirect;
        }
        if (idleLiquidity < idleDirect) revert AdapterDeltaMismatch();

        return routerDirect + idleLiquidity + upshiftLiquidity;
    }

    function allocation() external view returns (AllocationSnapshotV2 memory snapshot) {
        if (!_adaptersConfigured) revert ConfigurationIncomplete();

        snapshot.routerDirectAssets = asset.balanceOf(address(this));
        uint256 idleDirect = asset.balanceOf(idleAdapter);
        snapshot.idleAssets = IStrategyAdapterV2(idleAdapter).totalAssets();
        snapshot.upshiftDirectAssets = asset.balanceOf(upshiftAdapter);
        uint256 idleGross = IStrategyAdapterV2(idleAdapter).grossAssets();
        uint256 upshiftNet;
        uint256 upshiftGross;
        if (upshiftRecovered) {
            upshiftNet = snapshot.upshiftDirectAssets;
            upshiftGross = snapshot.upshiftDirectAssets;
        } else {
            upshiftNet = IStrategyAdapterV2(upshiftAdapter).totalAssets();
            upshiftGross = IStrategyAdapterV2(upshiftAdapter).grossAssets();
            snapshot.upshiftPositionShares = IStrategyAdapterV2(upshiftAdapter).positionShares();
        }
        if (
            snapshot.idleAssets < idleDirect || idleGross < idleDirect
                || upshiftNet < snapshot.upshiftDirectAssets
                || upshiftGross < snapshot.upshiftDirectAssets
        ) revert AdapterDeltaMismatch();

        snapshot.upshiftPositionNetAssets = upshiftNet - snapshot.upshiftDirectAssets;
        snapshot.upshiftPositionGrossAssets = upshiftGross - snapshot.upshiftDirectAssets;
        snapshot.totalNetAssets = snapshot.routerDirectAssets + snapshot.idleAssets + upshiftNet;
        snapshot.totalGrossAssets = snapshot.routerDirectAssets + idleGross + upshiftGross;

        if (snapshot.totalNetAssets != 0) {
            snapshot.idleBps =
                uint16(Math.mulDiv(snapshot.idleAssets, _BPS_DENOMINATOR, snapshot.totalNetAssets));
            snapshot.upshiftBps = uint16(
                Math.mulDiv(
                    snapshot.upshiftPositionNetAssets, _BPS_DENOMINATOR, snapshot.totalNetAssets
                )
            );
        }
    }

    function previewRebalance(AllocationV2 calldata target, RebalanceLimitsV2 calldata limits)
        external
        view
        returns (RebalancePlanV2 memory plan)
    {
        return _computeRebalancePlan(target, limits);
    }

    /// @dev Executes the recomputed differential plan and enforces the frozen economic limits.
    /// Withdrawal and recovery behavior is added only by their later review-gated tasks.
    function rebalance(
        bytes32 executionId,
        AllocationV2 calldata target,
        RebalanceLimitsV2 calldata limits,
        uint256 fundingAssets
    ) external onlyVault nonReentrant returns (uint256 totalAssetsAfter) {
        if (upshiftRecovered) revert RecoveredTargetForbidden();
        uint256 entryBalance = asset.balanceOf(address(this));
        if (fundingAssets > entryBalance) revert FundingMismatch(fundingAssets, entryBalance);

        RebalancePlanV2 memory plan = _computeRebalancePlan(target, limits);
        if (!plan.feasible) revert RebalanceInfeasible(plan.blocker);
        uint256 positionSharesBefore = IStrategyAdapterV2(upshiftAdapter).positionShares();

        if (plan.upshiftLiquidWithdrawAssets != 0) {
            _withdrawLiquid(upshiftAdapter, plan.upshiftLiquidWithdrawAssets);
        }

        if (plan.upshiftDepositAssets != 0) {
            if (plan.idleWithdrawAssets != 0) {
                _withdrawLiquid(idleAdapter, plan.idleWithdrawAssets);
            }
            _depositUpshift(
                plan.upshiftDepositAssets,
                plan.previewedUpshiftSharesOut,
                plan.previewedUpshiftNetAdded,
                limits.maximumPreviewDeviationBps
            );
            if (plan.idleDepositAssets != 0) _depositIdle(plan.idleDepositAssets);
        } else if (plan.upshiftSharesToRedeem != 0) {
            _redeemUpshift(
                plan.upshiftSharesToRedeem,
                plan.previewedUpshiftAssetsOut,
                plan.upshiftMinAssetsOut,
                limits.maximumPreviewDeviationBps
            );
            if (plan.idleDepositAssets != 0) _depositIdle(plan.idleDepositAssets);
        } else {
            if (plan.idleWithdrawAssets != 0) {
                _withdrawLiquid(idleAdapter, plan.idleWithdrawAssets);
            }
            if (plan.idleDepositAssets != 0) _depositIdle(plan.idleDepositAssets);
        }

        uint256 finalShares = IStrategyAdapterV2(upshiftAdapter).positionShares();
        uint256 upshiftDirect = asset.balanceOf(upshiftAdapter);
        uint256 finalNetAssets = IStrategyAdapterV2(upshiftAdapter).totalAssets();
        if (finalNetAssets < upshiftDirect) revert AdapterDeltaMismatch();
        if (plan.upshiftSharesToRedeem != 0) {
            if (
                finalShares > positionSharesBefore
                    || positionSharesBefore - finalShares != plan.upshiftSharesToRedeem
            ) revert AdapterDeltaMismatch();
        } else if (plan.upshiftDepositAssets != 0) {
            if (finalShares <= positionSharesBefore) revert AdapterDeltaMismatch();
        } else if (finalShares != positionSharesBefore) {
            revert AdapterDeltaMismatch();
        }

        totalAssetsAfter = this.totalAssets();
        if (totalAssetsAfter < limits.minimumPostNAV) {
            revert MinimumPostNAVNotMet(limits.minimumPostNAV, totalAssetsAfter);
        }
        if (totalAssetsAfter < plan.totalAssetsBefore) {
            uint256 actualLoss = plan.totalAssetsBefore - totalAssetsAfter;
            uint256 maximumLoss = Math.mulDiv(
                plan.totalAssetsBefore, limits.maximumRebalanceLossBps, _BPS_DENOMINATOR
            );
            if (actualLoss > maximumLoss) {
                revert RebalanceLossExceeded(maximumLoss, actualLoss);
            }
        }
        _enforcePostAllocation(target, limits.allocationToleranceBps, totalAssetsAfter);

        if (_hasMovement(plan)) {
            // forge-lint: disable-next-line(block-timestamp)
            lastRebalanceTimestamp = block.timestamp;
            emit AllocationExecuted(
                executionId,
                target.idleBps,
                target.upshiftBps,
                plan.totalAssetsBefore,
                totalAssetsAfter,
                plan.totalAssetsBefore > totalAssetsAfter
                    ? plan.totalAssetsBefore - totalAssetsAfter
                    : 0
            );
        } else {
            emit AllocationSkipped(executionId, target.idleBps, target.upshiftBps, totalAssetsAfter);
        }
    }

    function withdrawToVault(uint256 assets_)
        external
        onlyVault
        nonReentrant
        returns (uint256 assetsDelivered)
    {
        uint256 aggregateLiquidity = this.availableLiquidity();
        if (assets_ > aggregateLiquidity) {
            _insufficient(assets_, aggregateLiquidity);
        }

        WithdrawalReceiptV2 memory receipt;
        uint256 remaining = assets_;
        uint256 routerDirect = asset.balanceOf(address(this));
        receipt.routerDirectUsed = Math.min(routerDirect, remaining);
        remaining -= receipt.routerDirectUsed;

        if (remaining != 0) {
            uint256 idleLiquidity = IStrategyAdapterV2(idleAdapter).availableLiquidity();
            receipt.idleAssetsUsed = Math.min(idleLiquidity, remaining);
            if (receipt.idleAssetsUsed != 0) {
                _withdrawLiquid(idleAdapter, receipt.idleAssetsUsed);
                remaining -= receipt.idleAssetsUsed;
            }
        }

        RouterStateV2 state = strategyState();
        if (remaining != 0 && state != RouterStateV2.UpshiftUnavailable) {
            uint256 upshiftDirect = asset.balanceOf(upshiftAdapter);
            receipt.upshiftDirectUsed = Math.min(upshiftDirect, remaining);
            if (receipt.upshiftDirectUsed != 0) {
                _withdrawLiquid(upshiftAdapter, receipt.upshiftDirectUsed);
                remaining -= receipt.upshiftDirectUsed;
            }
        }

        if (remaining != 0) {
            if (state != RouterStateV2.Operational) {
                _insufficient(assets_, assets_ - remaining);
            }
            (receipt.upshiftSharesRedeemed, receipt.upshiftAssetsReceived) =
                _withdrawUpshiftPosition(remaining);
            remaining = 0;
        }

        assetsDelivered = _transferToVaultExact(assets_);
        emit AssetsWithdrawnToVault(
            assets_,
            assetsDelivered,
            receipt.routerDirectUsed,
            receipt.idleAssetsUsed,
            receipt.upshiftDirectUsed,
            receipt.upshiftSharesRedeemed,
            receipt.upshiftAssetsReceived
        );
    }

    function withdrawAllToVault()
        external
        onlyVault
        nonReentrant
        returns (uint256 assetsDelivered)
    {
        uint256 routerDirect = asset.balanceOf(address(this));
        uint256 idleUnderlying = asset.balanceOf(idleAdapter);
        uint256 idleAssetsReceived;
        if (idleUnderlying != 0) {
            idleAssetsReceived = _redeemAllAdapter(idleAdapter, 0);
        }

        uint256 upshiftShares = IStrategyAdapterV2(upshiftAdapter).positionShares();
        uint256 upshiftDirect = asset.balanceOf(upshiftAdapter);
        uint256 sharesRedeemed;
        uint256 upshiftPositionReceived;
        if (upshiftShares != 0) {
            if (strategyState() != RouterStateV2.Operational) {
                _insufficient(upshiftShares, 0);
            }
            uint256 netAssets = _previewRedeemNet(upshiftShares, 0);
            uint256 minAssetsOut = _previewMinimum(netAssets);
            uint256 upshiftTotalReceived = _redeemAllAdapter(upshiftAdapter, minAssetsOut);
            upshiftPositionReceived = upshiftTotalReceived - upshiftDirect;
            sharesRedeemed = upshiftShares;
        } else if (upshiftDirect != 0) {
            _withdrawLiquid(upshiftAdapter, upshiftDirect);
        }

        if (asset.balanceOf(idleAdapter) != 0 || asset.balanceOf(upshiftAdapter) != 0) {
            revert ResidualAssets();
        }
        if (
            IStrategyAdapterV2(idleAdapter).positionShares() != 0
                || IStrategyAdapterV2(upshiftAdapter).positionShares() != 0
        ) revert ResidualPosition();

        uint256 totalAssetsRecovered = asset.balanceOf(address(this));
        assetsDelivered = _transferToVaultExact(totalAssetsRecovered);
        emit AssetsWithdrawnToVault(
            totalAssetsRecovered,
            assetsDelivered,
            routerDirect,
            idleAssetsReceived,
            upshiftDirect,
            sharesRedeemed,
            upshiftPositionReceived
        );
    }

    function setExecutionPaused(bool paused) external onlyVault nonReentrant {
        executionPaused = paused;
        emit ExecutionPauseUpdated(paused);
    }

    function recoverAdapterPosition()
        external
        onlyVault
        nonReentrant
        returns (uint256 sharesRecovered)
    {
        if (!executionPaused) revert RecoveryRequiresPause();
        if (upshiftRecovered) revert PositionAlreadyRecovered();

        address positionToken = IStrategyAdapterV2(upshiftAdapter).positionToken();
        uint256 adapterBefore = IERC20(positionToken).balanceOf(upshiftAdapter);
        if (adapterBefore == 0) revert ResidualPosition();
        uint256 vaultBefore = IERC20(positionToken).balanceOf(vault);

        sharesRecovered = IStrategyRecoveryV2(upshiftAdapter).recoverPosition(vault);

        uint256 adapterAfter = IERC20(positionToken).balanceOf(upshiftAdapter);
        uint256 vaultAfter = IERC20(positionToken).balanceOf(vault);
        if (adapterAfter > adapterBefore) revert AdapterDeltaMismatch();
        uint256 adapterDecrease = adapterBefore - adapterAfter;
        if (vaultAfter < vaultBefore) revert AdapterDeltaMismatch();
        uint256 vaultIncrease = vaultAfter - vaultBefore;
        if (adapterDecrease != sharesRecovered || vaultIncrease != sharesRecovered) {
            revert AdapterDeltaMismatch();
        }

        upshiftRecovered = true;
        emit AdapterPositionRecovered(positionToken, sharesRecovered, vault);
    }

    function _withdrawUpshiftPosition(uint256 deficit)
        private
        returns (uint256 sharesRedeemed, uint256 assetsReceived)
    {
        uint256 heldShares = IStrategyAdapterV2(upshiftAdapter).positionShares();
        uint256 directAssets = asset.balanceOf(upshiftAdapter);
        uint256 totalNet = IStrategyAdapterV2(upshiftAdapter).totalAssets();
        if (heldShares == 0 || totalNet <= directAssets) _insufficient(deficit, 0);

        uint256 available = IStrategyAdapterV2(upshiftAdapter).availableLiquidity();
        if (available < directAssets) revert AdapterDeltaMismatch();
        uint256 previewedNet;
        (sharesRedeemed, previewedNet) = _selectWithdrawalCandidate(
            heldShares, deficit, totalNet - directAssets, available - directAssets
        );

        uint256 minAssetsOut = _previewMinimum(previewedNet);
        uint256 routerBefore = asset.balanceOf(address(this));
        _redeemUpshift(
            sharesRedeemed,
            previewedNet,
            minAssetsOut,
            _riskConfiguration.maximumPreviewDeviationBps
        );
        assetsReceived = asset.balanceOf(address(this)) - routerBefore;
    }

    function _selectWithdrawalCandidate(
        uint256 heldShares,
        uint256 deficit,
        uint256 positionNet,
        uint256 positionLiquidity
    ) private view returns (uint256 candidateShares, uint256 previewedNet) {
        candidateShares = Math.mulDiv(heldShares, deficit, positionNet, Math.Rounding.Ceil);
        for (uint256 evaluation; evaluation < 2; ++evaluation) {
            if (candidateShares == 0 || candidateShares > heldShares) {
                _insufficient(deficit, positionLiquidity);
            }
            previewedNet = _previewRedeemNet(candidateShares, positionLiquidity);
            if (previewedNet > positionLiquidity) {
                _insufficient(previewedNet, positionLiquidity);
            }
            if (previewedNet >= deficit) return (candidateShares, previewedNet);
            if (evaluation == 1) _insufficient(deficit, previewedNet);
            uint256 refinedShares =
                Math.mulDiv(candidateShares, deficit, previewedNet, Math.Rounding.Ceil);
            if (refinedShares == candidateShares) _insufficient(deficit, previewedNet);
            candidateShares = refinedShares;
        }
        _insufficient(deficit, previewedNet);
    }

    function _redeemAllAdapter(address adapter, uint256 minAssetsOut)
        private
        returns (uint256 assetsReceived)
    {
        uint256 routerBefore = asset.balanceOf(address(this));
        uint256 reportedAssets = IStrategyAdapterV2(adapter).redeemAll(minAssetsOut);
        return _reconcileRouterCredit(routerBefore, reportedAssets);
    }

    function _previewRedeemNet(uint256 shares, uint256 available)
        private
        view
        returns (uint256 netAssets)
    {
        (uint256 grossAssets_, uint256 netAssets_) =
            IStrategyAdapterV2(upshiftAdapter).previewRedeem(shares);
        if (grossAssets_ == 0 || netAssets_ == 0 || netAssets_ > grossAssets_) {
            _insufficient(shares, available);
        }
        return netAssets_;
    }

    function _previewMinimum(uint256 previewedNet) private view returns (uint256 minimum) {
        minimum = Math.mulDiv(
            previewedNet,
            _BPS_DENOMINATOR - _riskConfiguration.maximumPreviewDeviationBps,
            _BPS_DENOMINATOR
        );
        if (minimum == 0) _insufficient(previewedNet, 0);
    }

    function _insufficient(uint256 requested, uint256 available) private pure {
        revert InsufficientLiquidity(requested, available);
    }

    function _transferToVaultExact(uint256 assets_) private returns (uint256 assetsDelivered) {
        uint256 routerBefore = asset.balanceOf(address(this));
        uint256 vaultBefore = asset.balanceOf(vault);
        asset.safeTransfer(vault, assets_);
        uint256 routerAfter = asset.balanceOf(address(this));
        uint256 vaultAfter = asset.balanceOf(vault);
        if (
            routerAfter > routerBefore || routerBefore - routerAfter != assets_
                || vaultAfter < vaultBefore || vaultAfter - vaultBefore != assets_
        ) revert AssetDeltaMismatch();
        return assets_;
    }

    function _withdrawLiquid(address adapter, uint256 assets) private {
        uint256 routerBefore = asset.balanceOf(address(this));
        uint256 adapterBefore = asset.balanceOf(adapter);

        uint256 reportedAssets = IStrategyAdapterV2(adapter).withdrawLiquid(assets);

        uint256 routerAfter = asset.balanceOf(address(this));
        uint256 adapterAfter = asset.balanceOf(adapter);
        if (routerAfter < routerBefore || routerAfter - routerBefore != assets) {
            revert AssetDeltaMismatch();
        }
        if (adapterAfter > adapterBefore || adapterBefore - adapterAfter != assets) {
            revert AdapterDeltaMismatch();
        }
        if (reportedAssets != assets) revert AdapterDeltaMismatch();
    }

    function _reconcileRouterCredit(uint256 beforeAssets, uint256 reportedAssets)
        private
        view
        returns (uint256 receivedAssets)
    {
        uint256 afterAssets = asset.balanceOf(address(this));
        if (afterAssets < beforeAssets) revert AssetDeltaMismatch();
        receivedAssets = afterAssets - beforeAssets;
        if (reportedAssets != receivedAssets) revert AdapterDeltaMismatch();
    }

    function _depositUpshift(
        uint256 assets,
        uint256 previewedShares,
        uint256 previewedNetAdded,
        uint16 deviationBps
    ) private {
        uint256 minSharesOut = Math.mulDiv(
            previewedShares, _BPS_DENOMINATOR - deviationBps, _BPS_DENOMINATOR
        );
        uint256 routerBefore = asset.balanceOf(address(this));
        uint256 sharesBefore = IStrategyAdapterV2(upshiftAdapter).positionShares();
        uint256 positionNetBefore = _upshiftPositionNet();

        asset.forceApprove(upshiftAdapter, assets);
        uint256 reportedShares = IStrategyAdapterV2(upshiftAdapter).deposit(assets, minSharesOut);
        asset.forceApprove(upshiftAdapter, 0);
        if (asset.allowance(address(this), upshiftAdapter) != 0) revert AllowanceNotCleared();

        uint256 routerAfter = asset.balanceOf(address(this));
        uint256 sharesAfter = IStrategyAdapterV2(upshiftAdapter).positionShares();
        uint256 positionNetAfter = _upshiftPositionNet();
        if (routerAfter > routerBefore || routerBefore - routerAfter != assets) {
            revert AssetDeltaMismatch();
        }
        if (sharesAfter < sharesBefore) revert AdapterDeltaMismatch();
        uint256 actualShares = sharesAfter - sharesBefore;
        if (actualShares == 0 || actualShares < minSharesOut || reportedShares != actualShares) {
            revert AdapterDeltaMismatch();
        }
        uint256 actualNetAdded =
            positionNetAfter > positionNetBefore ? positionNetAfter - positionNetBefore : 0;
        _enforcePreviewDeviation(previewedNetAdded, actualNetAdded, deviationBps);
    }

    function _upshiftPositionNet() private view returns (uint256 positionNet) {
        uint256 directAssets = asset.balanceOf(upshiftAdapter);
        uint256 netAssets = IStrategyAdapterV2(upshiftAdapter).totalAssets();
        if (netAssets < directAssets) revert AdapterDeltaMismatch();
        return netAssets - directAssets;
    }

    function _redeemUpshift(
        uint256 shares,
        uint256 previewedAssets,
        uint256 minAssetsOut,
        uint16 deviationBps
    ) private {
        uint256 routerBefore = asset.balanceOf(address(this));
        uint256 sharesBefore = IStrategyAdapterV2(upshiftAdapter).positionShares();

        uint256 reportedAssets = IStrategyAdapterV2(upshiftAdapter).redeem(shares, minAssetsOut);

        uint256 sharesAfter = IStrategyAdapterV2(upshiftAdapter).positionShares();
        uint256 actualAssets = _reconcileRouterCredit(routerBefore, reportedAssets);
        if (sharesAfter > sharesBefore || sharesBefore - sharesAfter != shares) {
            revert AdapterDeltaMismatch();
        }
        _enforcePreviewDeviation(previewedAssets, actualAssets, deviationBps);
        if (actualAssets < minAssetsOut) revert AdapterDeltaMismatch();
    }

    function _depositIdle(uint256 assets) private {
        uint256 routerBefore = asset.balanceOf(address(this));
        uint256 adapterBefore = asset.balanceOf(idleAdapter);

        asset.forceApprove(idleAdapter, assets);
        uint256 reportedShares = IStrategyAdapterV2(idleAdapter).deposit(assets, assets);
        asset.forceApprove(idleAdapter, 0);
        if (asset.allowance(address(this), idleAdapter) != 0) revert AllowanceNotCleared();

        uint256 routerAfter = asset.balanceOf(address(this));
        uint256 adapterAfter = asset.balanceOf(idleAdapter);
        if (routerAfter > routerBefore || routerBefore - routerAfter != assets) {
            revert AssetDeltaMismatch();
        }
        if (adapterAfter < adapterBefore || adapterAfter - adapterBefore != assets) {
            revert AdapterDeltaMismatch();
        }
        if (reportedShares != adapterAfter - adapterBefore) revert AdapterDeltaMismatch();
    }

    function _computeRebalancePlan(AllocationV2 memory target, RebalanceLimitsV2 memory limits)
        internal
        view
        returns (RebalancePlanV2 memory plan)
    {
        if (!configurationFrozen) {
            return _blocked(plan, RebalanceBlockerV2.ConfigurationNotFrozen);
        }
        if (!_validAllocation(target)) {
            return _blocked(plan, RebalanceBlockerV2.InvalidAllocation);
        }
        if (!_validSignedLimits(limits)) {
            return _blocked(plan, RebalanceBlockerV2.InvalidSignedLimits);
        }
        if (upshiftRecovered) {
            return _blocked(plan, RebalanceBlockerV2.RecoveredTargetForbidden);
        }
        if (executionPaused) {
            return _blocked(plan, RebalanceBlockerV2.ExecutionPaused);
        }
        if (strategyState() != RouterStateV2.Operational) {
            return _blocked(plan, RebalanceBlockerV2.UpshiftUnavailable);
        }

        AllocationSnapshotV2 memory snapshot = this.allocation();
        _recordSnapshot(plan, snapshot);
        _setTargets(plan, snapshot.totalNetAssets, target.idleBps);

        if (
            snapshot.idleAssets == plan.targetIdleAssets
                && snapshot.upshiftPositionNetAssets == plan.targetUpshiftAssets
        ) {
            plan.feasible = true;
            return plan;
        }

        uint256 directBuffer = snapshot.routerDirectAssets + snapshot.upshiftDirectAssets;
        uint256 directBufferBps =
            Math.mulDiv(directBuffer, _BPS_DENOMINATOR, snapshot.totalNetAssets);
        uint256 turnoverBps =
            (_absoluteDifference(snapshot.idleBps, target.idleBps)
                    + _absoluteDifference(snapshot.upshiftBps, target.upshiftBps)
                    + directBufferBps) / 2;
        if (turnoverBps < _riskConfiguration.minimumAllocationChangeBps) {
            return _blocked(plan, RebalanceBlockerV2.ChangeBelowMinimum);
        }
        if (_cooldownActive()) {
            return _blocked(plan, RebalanceBlockerV2.CooldownActive);
        }

        plan.upshiftLiquidWithdrawAssets = snapshot.upshiftDirectAssets;

        if (snapshot.upshiftPositionNetAssets < plan.targetUpshiftAssets) {
            IncreaseContextV2 memory context = IncreaseContextV2({
                snapshot: snapshot,
                directBuffer: directBuffer,
                targetIdleBps: target.idleBps,
                toleranceBps: limits.allocationToleranceBps
            });
            return _planUpshiftIncrease(plan, context);
        }
        if (snapshot.upshiftPositionNetAssets > plan.targetUpshiftAssets) {
            DecreaseContextV2 memory context = DecreaseContextV2({
                snapshot: snapshot,
                directBuffer: directBuffer,
                positionLiquidity: 0,
                achievedNetReduction: 0,
                targetIdleBps: target.idleBps,
                toleranceBps: limits.allocationToleranceBps,
                previewDeviationBps: limits.maximumPreviewDeviationBps
            });
            return _planUpshiftDecrease(plan, context);
        }

        plan.idleDepositAssets = plan.targetIdleAssets - snapshot.idleAssets;
        if (plan.idleDepositAssets > directBuffer) {
            return _blocked(plan, RebalanceBlockerV2.InsufficientLiquidity);
        }
        if (!_positionsWithinTolerance(
                plan,
                snapshot.idleAssets + plan.idleDepositAssets,
                snapshot.upshiftPositionNetAssets,
                limits.allocationToleranceBps
            )) {
            return _blocked(plan, RebalanceBlockerV2.SolverDidNotConverge);
        }
        plan.feasible = true;
    }

    function _planUpshiftIncrease(RebalancePlanV2 memory plan, IncreaseContextV2 memory context)
        private
        view
        returns (RebalancePlanV2 memory)
    {
        uint256 idleLiquidity = IStrategyAdapterV2(idleAdapter).availableLiquidity();
        uint256 candidateAssets =
            plan.targetUpshiftAssets - context.snapshot.upshiftPositionNetAssets;
        uint256 maximumFunding = context.directBuffer + idleLiquidity;

        for (uint256 evaluation; evaluation < 2; ++evaluation) {
            if (candidateAssets == 0) return _blocked(plan, RebalanceBlockerV2.ZeroPreview);
            if (candidateAssets > maximumFunding) {
                return _blocked(plan, RebalanceBlockerV2.InsufficientLiquidity);
            }

            (bool converged, RebalanceBlockerV2 blocker) =
                _evaluateUpshiftIncrease(plan, context, candidateAssets, idleLiquidity);
            if (blocker != RebalanceBlockerV2.None) return _blocked(plan, blocker);
            if (converged) {
                plan.feasible = true;
                return plan;
            }

            if (
                evaluation == 1
                    || plan.targetUpshiftAssets <= context.snapshot.upshiftPositionNetAssets
            ) {
                return _blocked(plan, RebalanceBlockerV2.SolverDidNotConverge);
            }
            uint256 requiredNetAdded =
                plan.targetUpshiftAssets - context.snapshot.upshiftPositionNetAssets;
            uint256 refinedCandidate = Math.mulDiv(
                candidateAssets, requiredNetAdded, plan.previewedUpshiftNetAdded, Math.Rounding.Ceil
            );
            if (refinedCandidate == candidateAssets) {
                return _blocked(plan, RebalanceBlockerV2.SolverDidNotConverge);
            }
            candidateAssets = refinedCandidate;
        }

        return _blocked(plan, RebalanceBlockerV2.SolverDidNotConverge);
    }

    function _evaluateUpshiftIncrease(
        RebalancePlanV2 memory plan,
        IncreaseContextV2 memory context,
        uint256 candidateAssets,
        uint256 idleLiquidity
    ) private view returns (bool converged, RebalanceBlockerV2 blocker) {
        (uint256 expectedShares, uint256 immediateNetAdded) =
            IStrategyAdapterV2(upshiftAdapter).previewDeposit(candidateAssets);
        if (expectedShares == 0 || immediateNetAdded == 0) {
            return (false, RebalanceBlockerV2.ZeroPreview);
        }

        uint256 projectedUp = context.snapshot.upshiftPositionNetAssets + immediateNetAdded;
        uint256 projectedTotal =
            context.snapshot.totalNetAssets - candidateAssets + immediateNetAdded;
        _setTargets(plan, projectedTotal, context.targetIdleBps);
        (uint256 idleWithdraw, uint256 idleDeposit) =
            _idleMovement(context.snapshot.idleAssets, plan.targetIdleAssets);
        if (
            idleWithdraw > idleLiquidity
                || idleDeposit + candidateAssets > context.directBuffer + idleWithdraw
        ) return (false, RebalanceBlockerV2.InsufficientLiquidity);

        plan.idleWithdrawAssets = idleWithdraw;
        plan.idleDepositAssets = idleDeposit;
        plan.upshiftDepositAssets = candidateAssets;
        plan.previewedUpshiftSharesOut = expectedShares;
        plan.previewedUpshiftNetAdded = immediateNetAdded;
        uint256 projectedIdle = context.snapshot.idleAssets - idleWithdraw + idleDeposit;
        converged =
            _positionsWithinTolerance(plan, projectedIdle, projectedUp, context.toleranceBps);
    }

    function _planUpshiftDecrease(RebalancePlanV2 memory plan, DecreaseContextV2 memory context)
        private
        view
        returns (RebalancePlanV2 memory)
    {
        uint256 heldShares = context.snapshot.upshiftPositionShares;
        uint256 currentPositionNet = context.snapshot.upshiftPositionNetAssets;
        if (heldShares == 0 || currentPositionNet == 0) {
            return _blocked(plan, RebalanceBlockerV2.ZeroPreview);
        }

        uint256 requiredNetReduction = currentPositionNet - plan.targetUpshiftAssets;
        uint256 candidateShares =
            Math.mulDiv(heldShares, requiredNetReduction, currentPositionNet, Math.Rounding.Ceil);
        uint256 available = IStrategyAdapterV2(upshiftAdapter).availableLiquidity();
        if (available < context.snapshot.upshiftDirectAssets) {
            return _blocked(plan, RebalanceBlockerV2.InsufficientLiquidity);
        }
        context.positionLiquidity = available - context.snapshot.upshiftDirectAssets;

        for (uint256 evaluation; evaluation < 2; ++evaluation) {
            if (candidateShares == 0 || candidateShares > heldShares) {
                return _blocked(plan, RebalanceBlockerV2.SolverDidNotConverge);
            }

            (bool converged, RebalanceBlockerV2 blocker) =
                _evaluateUpshiftDecrease(plan, context, candidateShares);
            if (blocker != RebalanceBlockerV2.None) return _blocked(plan, blocker);
            if (converged) {
                plan.feasible = true;
                return plan;
            }

            if (evaluation == 1 || plan.targetUpshiftAssets >= currentPositionNet) {
                return _blocked(plan, RebalanceBlockerV2.SolverDidNotConverge);
            }
            requiredNetReduction = currentPositionNet - plan.targetUpshiftAssets;
            uint256 refinedCandidate = Math.mulDiv(
                candidateShares,
                requiredNetReduction,
                context.achievedNetReduction,
                Math.Rounding.Ceil
            );
            if (refinedCandidate == candidateShares) {
                return _blocked(plan, RebalanceBlockerV2.SolverDidNotConverge);
            }
            candidateShares = refinedCandidate;
        }

        return _blocked(plan, RebalanceBlockerV2.SolverDidNotConverge);
    }

    function _evaluateUpshiftDecrease(
        RebalancePlanV2 memory plan,
        DecreaseContextV2 memory context,
        uint256 candidateShares
    ) private view returns (bool converged, RebalanceBlockerV2 blocker) {
        (uint256 grossOut, uint256 netOut) =
            IStrategyAdapterV2(upshiftAdapter).previewRedeem(candidateShares);
        if (grossOut == 0 || netOut == 0 || netOut > grossOut) {
            return (false, RebalanceBlockerV2.ZeroPreview);
        }

        uint256 remainingShares = context.snapshot.upshiftPositionShares - candidateShares;
        uint256 remainingNet;
        if (remainingShares != 0) {
            (uint256 remainingGross, uint256 previewedRemainingNet) =
                IStrategyAdapterV2(upshiftAdapter).previewRedeem(remainingShares);
            if (
                remainingGross == 0 || previewedRemainingNet == 0
                    || previewedRemainingNet > remainingGross
            ) return (false, RebalanceBlockerV2.ZeroPreview);
            remainingNet = previewedRemainingNet;
        }
        if (remainingNet >= context.snapshot.upshiftPositionNetAssets) {
            return (false, RebalanceBlockerV2.SolverDidNotConverge);
        }
        context.achievedNetReduction = context.snapshot.upshiftPositionNetAssets - remainingNet;

        uint256 projectedTotal = context.snapshot.totalNetAssets
            - context.snapshot.upshiftPositionNetAssets + netOut + remainingNet;
        _setTargets(plan, projectedTotal, context.targetIdleBps);
        (uint256 idleWithdraw, uint256 idleDeposit) =
            _idleMovement(context.snapshot.idleAssets, plan.targetIdleAssets);
        if (idleWithdraw != 0 || idleDeposit > context.directBuffer + netOut) {
            return (false, RebalanceBlockerV2.SolverDidNotConverge);
        }
        if (netOut > context.positionLiquidity) {
            return (false, RebalanceBlockerV2.InsufficientLiquidity);
        }

        plan.idleDepositAssets = idleDeposit;
        plan.upshiftSharesToRedeem = candidateShares;
        plan.previewedUpshiftAssetsOut = netOut;
        plan.upshiftMinAssetsOut =
            Math.mulDiv(netOut, _BPS_DENOMINATOR - context.previewDeviationBps, _BPS_DENOMINATOR);
        plan.requiredProtocolLiquidity = netOut;
        uint256 projectedIdle = context.snapshot.idleAssets + idleDeposit;
        converged =
            _positionsWithinTolerance(plan, projectedIdle, remainingNet, context.toleranceBps);
    }

    function _recordSnapshot(RebalancePlanV2 memory plan, AllocationSnapshotV2 memory snapshot)
        private
        pure
    {
        plan.totalAssetsBefore = snapshot.totalNetAssets;
        plan.projectedTotalAssetsAfter = snapshot.totalNetAssets;
        plan.routerAssetsBefore = snapshot.routerDirectAssets;
        plan.idleAssetsBefore = snapshot.idleAssets;
        plan.upshiftDirectAssetsBefore = snapshot.upshiftDirectAssets;
        plan.upshiftPositionAssetsBefore = snapshot.upshiftPositionNetAssets;
    }

    function _setTargets(RebalancePlanV2 memory plan, uint256 totalAssets_, uint16 idleBps)
        private
        pure
    {
        plan.projectedTotalAssetsAfter = totalAssets_;
        plan.targetIdleAssets = Math.mulDiv(totalAssets_, idleBps, _BPS_DENOMINATOR);
        plan.targetUpshiftAssets = totalAssets_ - plan.targetIdleAssets;
    }

    function _positionsWithinTolerance(
        RebalancePlanV2 memory plan,
        uint256 actualIdle,
        uint256 actualUpshift,
        uint16 toleranceBps
    ) private pure returns (bool) {
        uint256 denominator = plan.projectedTotalAssetsAfter == 0
            ? 1
            : plan.projectedTotalAssetsAfter;
        uint256 idleDeviation = Math.mulDiv(
            _absoluteDifference(actualIdle, plan.targetIdleAssets), _BPS_DENOMINATOR, denominator
        );
        uint256 upshiftDeviation = Math.mulDiv(
            _absoluteDifference(actualUpshift, plan.targetUpshiftAssets),
            _BPS_DENOMINATOR,
            denominator
        );
        return idleDeviation <= toleranceBps && upshiftDeviation <= toleranceBps;
    }

    function _idleMovement(uint256 currentIdle, uint256 targetIdle)
        private
        pure
        returns (uint256 withdrawAssets, uint256 depositAssets)
    {
        if (currentIdle > targetIdle) return (currentIdle - targetIdle, 0);
        return (0, targetIdle - currentIdle);
    }

    function _enforcePreviewDeviation(uint256 previewed, uint256 actual, uint16 maximumBps)
        private
        pure
    {
        uint256 adverseDifference = previewed > actual ? previewed - actual : 0;
        uint256 denominator = previewed == 0 ? 1 : previewed;
        uint256 deviationBps = Math.mulDiv(adverseDifference, _BPS_DENOMINATOR, denominator);
        if (deviationBps > maximumBps) revert PreviewDeviationExceeded();
    }

    function _enforcePostAllocation(
        AllocationV2 memory target,
        uint16 toleranceBps,
        uint256 postNetAssets
    ) private view {
        AllocationSnapshotV2 memory post = this.allocation();
        if (post.totalNetAssets != postNetAssets) revert AdapterDeltaMismatch();

        uint256 targetIdle = Math.mulDiv(postNetAssets, target.idleBps, _BPS_DENOMINATOR);
        uint256 targetUpshift = postNetAssets - targetIdle;
        uint256 denominator = postNetAssets == 0 ? 1 : postNetAssets;
        uint256 idleDeviation = Math.mulDiv(
            _absoluteDifference(post.idleAssets, targetIdle), _BPS_DENOMINATOR, denominator
        );
        uint256 upshiftDeviation = Math.mulDiv(
            _absoluteDifference(post.upshiftPositionNetAssets, targetUpshift),
            _BPS_DENOMINATOR,
            denominator
        );
        if (idleDeviation > toleranceBps || upshiftDeviation > toleranceBps) {
            revert AllocationToleranceExceeded();
        }
    }

    function _hasMovement(RebalancePlanV2 memory plan) private pure returns (bool) {
        return plan.idleWithdrawAssets != 0 || plan.upshiftLiquidWithdrawAssets != 0
            || plan.upshiftSharesToRedeem != 0 || plan.idleDepositAssets != 0
            || plan.upshiftDepositAssets != 0;
    }

    function _validAllocation(AllocationV2 memory target) private pure returns (bool) {
        return target.firelightBps == 0 && target.sparkdexBps == 0
            && uint256(target.upshiftBps) + target.idleBps == _BPS_DENOMINATOR;
    }

    function _validSignedLimits(RebalanceLimitsV2 memory limits) private view returns (bool) {
        return limits.maximumRebalanceLossBps <= _riskConfiguration.maximumRebalanceLossBps
            && limits.maximumPreviewDeviationBps <= _riskConfiguration.maximumPreviewDeviationBps
            && limits.allocationToleranceBps <= _riskConfiguration.allocationToleranceBps;
    }

    function _cooldownActive() private view returns (bool) {
        if (lastRebalanceTimestamp == 0) return false;
        uint256 interval = _riskConfiguration.minimumRebalanceInterval;
        if (interval > type(uint256).max - lastRebalanceTimestamp) return true;
        // Validator timestamp latitude is acceptable for the configured coarse cooldown boundary.
        // forge-lint: disable-next-line(block-timestamp)
        return block.timestamp < lastRebalanceTimestamp + interval;
    }

    function _absoluteDifference(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _blocked(RebalancePlanV2 memory plan, RebalanceBlockerV2 blocker)
        private
        pure
        returns (RebalancePlanV2 memory)
    {
        plan.projectedTotalAssetsAfter = 0;
        plan.targetIdleAssets = 0;
        plan.targetUpshiftAssets = 0;
        plan.idleWithdrawAssets = 0;
        plan.upshiftLiquidWithdrawAssets = 0;
        plan.upshiftSharesToRedeem = 0;
        plan.previewedUpshiftAssetsOut = 0;
        plan.upshiftMinAssetsOut = 0;
        plan.idleDepositAssets = 0;
        plan.upshiftDepositAssets = 0;
        plan.previewedUpshiftSharesOut = 0;
        plan.previewedUpshiftNetAdded = 0;
        plan.requiredProtocolLiquidity = 0;
        plan.feasible = false;
        plan.blocker = blocker;
        return plan;
    }

    function strategyState() public view returns (RouterStateV2) {
        if (upshiftRecovered) return RouterStateV2.UpshiftRecovered;
        if (executionPaused || !configurationFrozen) return RouterStateV2.UpshiftUnavailable;

        try IStrategyAdapterV2(upshiftAdapter).protocolStatus() returns (
            bool depositsEnabled, bool withdrawalsEnabled, uint256, uint256
        ) {
            if (depositsEnabled && withdrawalsEnabled) return RouterStateV2.Operational;
            return RouterStateV2.UpshiftUnavailable;
        } catch {
            return RouterStateV2.UpshiftUnavailable;
        }
    }

    function _requireConfigurator() private view {
        if (msg.sender != vaultOwner) revert UnauthorizedConfigurator();
    }

    function _requireMutable() private view {
        if (configurationFrozen) revert ConfigurationFrozen();
    }
}
