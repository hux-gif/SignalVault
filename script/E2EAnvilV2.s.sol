// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeploySignalVaultV2} from "./DeploySignalVaultV2.s.sol";
import {IUpshiftVaultV2} from "src/v2/interfaces/IUpshiftVaultV2.sol";
import {MockLPTokenV2} from "test/v2/mocks/MockLPTokenV2.sol";
import {FeeAwareUpshiftVaultMock} from "test/v2/mocks/FeeAwareUpshiftVaultMock.sol";

/// @notice Deterministic Anvil E2E script.
/// Simulates the full lifecycle: deploy, deposit, intent, rebalance, withdraw.
contract E2EAnvilV2 is Script {
    function run() external returns (DeploySignalVaultV2.Deployment memory deployed) {
        address vaultOwner = vm.envOr("VAULT_OWNER", address(0xB0B));
        address trustedSigner = vm.envOr("TRUSTED_SIGNER", address(0xA11CE));

        vm.startBroadcast();

        MockLPTokenV2 asset = new MockLPTokenV2("Test FXRP", "tFXRP", 6);
        MockLPTokenV2 lpToken = new MockLPTokenV2("Test Upshift LP", "tULP", 6);
        FeeAwareUpshiftVaultMock protocol =
            new FeeAwareUpshiftVaultMock(address(asset), address(lpToken));

        deployed = (new DeploySignalVaultV2())
        .deployContracts(
            IERC20(address(asset)),
            trustedSigner,
            vaultOwner,
            IUpshiftVaultV2(address(protocol)),
            IERC20(address(lpToken))
        );

        asset.mint(vaultOwner, 1_000_000e6);

        vm.stopBroadcast();
    }
}
