// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IntentVerifier} from "src/IntentVerifier.sol";
import {StrategyRouter} from "src/StrategyRouter.sol";
import {SignalVault} from "src/SignalVault.sol";
import {MockStrategyAdapter} from "src/adapters/MockStrategyAdapter.sol";
import {IdleAdapter} from "src/adapters/IdleAdapter.sol";

contract DeploySignalVault is Script {
    struct Deployment {
        IntentVerifier verifier;
        StrategyRouter router;
        SignalVault vault;
        address[4] adapters;
    }

    function run() external virtual returns (Deployment memory deployed) {
        address fxrp = vm.envAddress("FXRP_ADDRESS");
        address trustedSigner = vm.envAddress("TRUSTED_SIGNER");
        address vaultOwner = vm.envAddress("VAULT_OWNER");

        vm.startBroadcast();
        deployed = _deploy(IERC20(fxrp), trustedSigner, vaultOwner);
        vm.stopBroadcast();

        _assertDeployment(deployed, fxrp, trustedSigner, vaultOwner);
    }

    function deployContracts(IERC20 asset, address trustedSigner, address vaultOwner)
        external
        returns (Deployment memory deployed)
    {
        deployed = _deploy(asset, trustedSigner, vaultOwner);
        _assertDeployment(deployed, address(asset), trustedSigner, vaultOwner);
    }

    function configureAgain(Deployment calldata deployed) external {
        deployed.router
            .configureAdapters(
                deployed.adapters[0],
                deployed.adapters[1],
                deployed.adapters[2],
                deployed.adapters[3]
            );
    }

    function bindAgain(Deployment calldata deployed) external {
        deployed.router.bindVault(address(deployed.vault));
    }

    function _deploy(IERC20 asset, address trustedSigner, address vaultOwner)
        internal
        returns (Deployment memory deployed)
    {
        deployed.verifier = new IntentVerifier(trustedSigner);
        deployed.router = new StrategyRouter(asset);

        deployed.adapters[0] = address(
            new MockStrategyAdapter(asset, address(deployed.router), "Upshift Simulation", 20)
        );
        deployed.adapters[1] = address(
            new MockStrategyAdapter(asset, address(deployed.router), "Firelight Simulation", 35)
        );
        deployed.adapters[2] = address(
            new MockStrategyAdapter(asset, address(deployed.router), "SparkDEX Simulation", 70)
        );
        deployed.adapters[3] = address(new IdleAdapter(asset, address(deployed.router)));

        deployed.router
            .configureAdapters(
                deployed.adapters[0],
                deployed.adapters[1],
                deployed.adapters[2],
                deployed.adapters[3]
            );
        deployed.vault = new SignalVault(
            asset, address(deployed.router), address(deployed.verifier), vaultOwner
        );
        deployed.router.bindVault(address(deployed.vault));
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
    }
}
