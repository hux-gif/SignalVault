// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DeploySignalVault} from "script/DeploySignalVault.s.sol";
import {SignalVault} from "src/SignalVault.sol";
import {IntentVerifier} from "src/IntentVerifier.sol";
import {StrategyRouter} from "src/StrategyRouter.sol";
import {MockStrategyAdapter} from "src/adapters/MockStrategyAdapter.sol";
import {Allocation, TEEResult} from "src/types/SignalVaultTypes.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract DeploymentFlowTest is Test {
    uint256 internal constant SIGNER_PK = 0xA11CE;
    address internal constant VAULT_OWNER = address(0xBEEF);

    DeploySignalVault internal deployer;
    MockERC20 internal fxrp;
    DeploySignalVault.Deployment internal deployed;

    function setUp() external {
        deployer = new DeploySignalVault();
        fxrp = new MockERC20("Local FXRP", "FXRP");
        deployed = deployer.deployContracts(fxrp, vm.addr(SIGNER_PK), VAULT_OWNER);
    }

    function testDeploymentUsesValidOneTimeConfigurationOrder() external {
        assertEq(address(deployed.verifier).code.length > 0, true);
        assertEq(address(deployed.router.asset()), address(fxrp));
        assertTrue(deployed.router.adaptersConfigured());
        assertEq(deployed.router.vault(), address(deployed.vault));
        assertEq(address(deployed.vault.asset()), address(fxrp));
        assertEq(address(deployed.vault.router()), address(deployed.router));
        assertEq(address(deployed.vault.verifier()), address(deployed.verifier));

        address[4] memory adapters = deployed.adapters;
        for (uint256 i; i < adapters.length; ++i) {
            assertTrue(adapters[i] != address(0));
            assertEq(MockStrategyAdapter(adapters[i]).router(), address(deployed.router));
            for (uint256 j; j < i; ++j) {
                assertTrue(adapters[i] != adapters[j]);
            }
        }

        vm.expectRevert(StrategyRouter.AlreadyConfigured.selector);
        deployer.configureAgain(deployed);
        vm.expectRevert(StrategyRouter.AlreadyBound.selector);
        deployer.bindAgain(deployed);
    }

    function testDeploymentSetsTrustedSignerAndOwners() external view {
        assertEq(deployed.verifier.trustedSigner(), vm.addr(SIGNER_PK));
        assertEq(deployed.verifier.owner(), address(deployer));
        assertEq(deployed.router.owner(), address(deployer));
        assertEq(deployed.vault.vaultOwner(), VAULT_OWNER);
    }

    function testFullLocalLifecycleRebalancesWithoutDoubleDepositAndRecoversDust() external {
        fxrp.mint(VAULT_OWNER, 101);
        vm.startPrank(VAULT_OWNER);
        fxrp.approve(address(deployed.vault), type(uint256).max);
        assertEq(deployed.vault.deposit(101), 101);
        vm.stopPrank();

        _submitAndExecute(1, Allocation(5_000, 2_000, 1_000, 2_000));
        assertEq(deployed.vault.totalAssets(), 101);
        assertEq(fxrp.balanceOf(deployed.adapters[0]), 50);
        assertEq(fxrp.balanceOf(deployed.adapters[3]), 21);

        _submitAndExecute(2, Allocation(4_000, 2_000, 0, 4_000));
        assertEq(deployed.vault.totalAssets(), 101);
        assertEq(fxrp.balanceOf(deployed.adapters[0]), 40);
        assertEq(fxrp.balanceOf(deployed.adapters[1]), 20);
        assertEq(fxrp.balanceOf(deployed.adapters[2]), 0);
        assertEq(fxrp.balanceOf(deployed.adapters[3]), 41);

        vm.prank(VAULT_OWNER);
        uint256 partialAssets = deployed.vault.withdraw(33);
        assertApproxEqAbs(partialAssets, 33, 3);
        vm.prank(VAULT_OWNER);
        uint256 remainder = deployed.vault.withdraw(68);
        assertEq(partialAssets + remainder, 101);
        assertEq(deployed.vault.totalSupply(), 0);
        assertEq(deployed.router.totalAssets(), 0);
        assertEq(fxrp.balanceOf(VAULT_OWNER), 101);
    }

    function _submitAndExecute(uint256 nonce, Allocation memory allocation) internal {
        bytes32 commitment = keccak256(abi.encode("deployment flow", nonce));
        vm.prank(VAULT_OWNER);
        deployed.vault.submitPrivateIntent(hex"c0ffee", commitment, nonce);
        TEEResult memory result = TEEResult(
            VAULT_OWNER,
            address(deployed.vault),
            commitment,
            allocation,
            nonce,
            block.timestamp + 1 hours,
            block.timestamp,
            block.chainid,
            bytes32(0)
        );
        result.resultHash = deployed.vault.computeResultHash(result);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(SIGNER_PK, deployed.verifier.hashTypedData(result));
        deployed.vault.executeTEEAllocation(result, abi.encodePacked(r, s, v));
    }
}
