// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IntentVerifierV2} from "src/v2/IntentVerifierV2.sol";
import {StrategyRouterV2} from "src/v2/StrategyRouterV2.sol";
import {IStrategyRouterV2} from "src/v2/interfaces/IStrategyRouterV2.sol";
import {SignalVaultV2} from "src/v2/SignalVaultV2.sol";
import {IdleAdapterV2} from "src/v2/adapters/IdleAdapterV2.sol";
import {UpshiftAdapterV2} from "src/v2/adapters/UpshiftAdapterV2.sol";
import {IUpshiftVaultV2} from "src/v2/interfaces/IUpshiftVaultV2.sol";
import {RiskConfigurationV2} from "src/v2/types/SignalVaultTypesV2.sol";

contract DeploySignalVaultV2 is Script {
    struct Deployment {
        IntentVerifierV2 verifier;
        StrategyRouterV2 router;
        IdleAdapterV2 idleAdapter;
        UpshiftAdapterV2 upshiftAdapter;
        SignalVaultV2 vault;
        bytes32 riskConfigurationHash;
        bytes32 routerConfigHash;
    }

    function run() external returns (Deployment memory deployed) {
        address fxrp = vm.envAddress("FXRP_ADDRESS");
        address trustedSigner = vm.envAddress("TRUSTED_SIGNER");
        address vaultOwner = vm.envAddress("VAULT_OWNER");
        address upshiftVault = vm.envAddress("UPSHIFT_VAULT_ADDRESS");
        address lpToken = vm.envAddress("LP_TOKEN_ADDRESS");

        vm.startBroadcast();
        deployed = _deploy(
            IERC20(fxrp), trustedSigner, vaultOwner, IUpshiftVaultV2(upshiftVault), IERC20(lpToken)
        );
        vm.stopBroadcast();

        _assertDeployment(deployed, fxrp, trustedSigner, vaultOwner);
    }

    function deployContracts(
        IERC20 asset,
        address trustedSigner,
        address vaultOwner,
        IUpshiftVaultV2 upshiftVault,
        IERC20 lpToken
    ) external returns (Deployment memory deployed) {
        deployed = _deploy(asset, trustedSigner, vaultOwner, upshiftVault, lpToken);
        _assertDeployment(deployed, address(asset), trustedSigner, vaultOwner);
    }

    function _deploy(
        IERC20 asset,
        address trustedSigner,
        address vaultOwner,
        IUpshiftVaultV2 upshiftVault,
        IERC20 lpToken
    ) internal returns (Deployment memory deployed) {
        deployed.verifier = new IntentVerifierV2(trustedSigner);
        deployed.router = new StrategyRouterV2(asset, vaultOwner);
        deployed.idleAdapter = new IdleAdapterV2(asset, address(deployed.router));
        deployed.upshiftAdapter =
            new UpshiftAdapterV2(asset, address(deployed.router), upshiftVault, lpToken);

        deployed.router
            .configureAdapters(address(deployed.upshiftAdapter), address(deployed.idleAdapter));
        deployed.router.configureRisk(_defaultRisk());

        deployed.vault = new SignalVaultV2(
            asset, IStrategyRouterV2(address(deployed.router)), deployed.verifier, vaultOwner
        );

        deployed.router.bindVault(address(deployed.vault));

        deployed.riskConfigurationHash = deployed.router.riskConfigurationHash();
        deployed.routerConfigHash = deployed.router.routerConfigHash();
    }

    function _defaultRisk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 1 hours,
            minimumAllocationChangeBps: 100,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }

    function _assertDeployment(
        Deployment memory deployed,
        address asset,
        address trustedSigner,
        address vaultOwner
    ) internal view {
        require(address(deployed.router.asset()) == asset, "router asset mismatch");
        require(deployed.router.vault() == address(deployed.vault), "router vault mismatch");
        require(address(deployed.vault.asset()) == asset, "vault asset mismatch");
        require(
            address(deployed.vault.router()) == address(deployed.router), "vault router mismatch"
        );
        require(
            address(deployed.vault.verifier()) == address(deployed.verifier),
            "vault verifier mismatch"
        );
        require(deployed.vault.vaultOwner() == vaultOwner, "vault owner mismatch");
        require(deployed.verifier.trustedSigner() == trustedSigner, "trusted signer mismatch");
        require(deployed.router.configurationFrozen(), "configuration not frozen");
        require(deployed.routerConfigHash != bytes32(0), "config hash zero");
        require(deployed.riskConfigurationHash != bytes32(0), "risk hash zero");
    }
}
