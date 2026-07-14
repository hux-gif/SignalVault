// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyAdapterV2} from "./interfaces/IStrategyAdapterV2.sol";
import {AllocationSnapshotV2, RouterStateV2} from "./interfaces/IStrategyRouterV2.sol";
import {RiskConfigurationV2} from "./types/SignalVaultTypesV2.sol";
import {SignalVaultHashesV2} from "./libraries/SignalVaultHashesV2.sol";

interface IRouterBoundAdapterV2 {
    function router() external view returns (address);
}

interface IRouterBoundVaultV2 {
    function vaultOwner() external view returns (address);
}

/// @notice One-asset V2 strategy Router. Task 1 freezes deployment identities and configuration;
/// runtime accounting and execution are introduced by later independently reviewed tasks.
contract StrategyRouterV2 {
    uint16 private constant _BPS_DENOMINATOR = 10_000;

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
    error AdapterDeltaMismatch();

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
