// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyAdapterV2} from "./interfaces/IStrategyAdapterV2.sol";
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

    function _requireConfigurator() private view {
        if (msg.sender != vaultOwner) revert UnauthorizedConfigurator();
    }

    function _requireMutable() private view {
        if (configurationFrozen) revert ConfigurationFrozen();
    }
}
