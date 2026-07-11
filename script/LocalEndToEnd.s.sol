// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DeploySignalVault} from "./DeploySignalVault.s.sol";
import {Allocation, TEEResult} from "src/types/SignalVaultTypes.sol";

contract LocalMockFXRP is ERC20 {
    constructor() ERC20("Local FXRP", "FXRP") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

/// @notice Solidity smoke flow that signs TEEResults with `vm.sign` for fast local validation.
/// @dev This is NOT the canonical HTTP signer E2E and must not be used as evidence for the
/// HTTP integration. The canonical HTTP integration test is `local-signer/src/e2e.ts`,
/// which obtains signatures through the local-signer HTTP /allocate endpoint.
contract LocalEndToEnd is DeploySignalVault {
    function run() external override returns (Deployment memory deployed) {
        uint256 signerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY");
        address vaultOwner = vm.envAddress("VAULT_OWNER");
        require(vaultOwner == msg.sender, "VAULT_OWNER must be broadcaster");

        vm.startBroadcast();
        LocalMockFXRP fxrp = new LocalMockFXRP();
        deployed = _deploy(fxrp, vm.addr(signerPrivateKey), vaultOwner);
        fxrp.mint(vaultOwner, 101);
        fxrp.approve(address(deployed.vault), type(uint256).max);
        deployed.vault.deposit(101);
        vm.stopBroadcast();

        _execute(deployed, signerPrivateKey, vaultOwner, 1, Allocation(5_000, 2_000, 1_000, 2_000));
        _execute(deployed, signerPrivateKey, vaultOwner, 2, Allocation(4_000, 2_000, 0, 4_000));

        vm.startBroadcast();
        uint256 partialAssets = deployed.vault.withdraw(33);
        uint256 remainingAssets = deployed.vault.withdraw(68);
        vm.stopBroadcast();
        require(partialAssets + remainingAssets == 101, "withdrawal dust remains");
        require(deployed.router.totalAssets() == 0, "router assets remain");
    }

    function _execute(
        Deployment memory deployed,
        uint256 signerPrivateKey,
        address vaultOwner,
        uint256 nonce,
        Allocation memory allocation
    ) internal {
        bytes32 commitment = keccak256(abi.encode("local smoke", nonce));
        TEEResult memory result = TEEResult(
            vaultOwner,
            address(deployed.vault),
            commitment,
            allocation,
            nonce,
            block.timestamp + 5 minutes,
            block.timestamp,
            block.chainid,
            bytes32(0)
        );
        result.resultHash = deployed.vault.computeResultHash(result);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signerPrivateKey, deployed.verifier.hashTypedData(result));

        vm.startBroadcast();
        deployed.vault.submitPrivateIntent(hex"c0ffee", commitment, nonce);
        deployed.vault.executeTEEAllocation(result, abi.encodePacked(r, s, v));
        vm.stopBroadcast();
    }
}
