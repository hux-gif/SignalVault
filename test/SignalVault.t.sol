// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SignalVault} from "src/SignalVault.sol";
import {IntentVerifier} from "src/IntentVerifier.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract EmptyRouter {
    IERC20 private immutable _asset;

    constructor(IERC20 asset_) {
        _asset = asset_;
    }

    function totalAssets() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function withdrawProRata(uint256, uint256) external pure returns (uint256) {
        return 0;
    }
}

contract SignalVaultTest is Test {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    MockERC20 internal fxrp;
    EmptyRouter internal router;
    SignalVault internal vault;

    function setUp() external {
        fxrp = new MockERC20("Test FXRP", "FXRP");
        router = new EmptyRouter(fxrp);
        vault = new SignalVault(fxrp, address(router), address(new IntentVerifier(address(0x1234))));

        fxrp.mint(ALICE, 1_000 ether);
        fxrp.mint(BOB, 1_000 ether);
        vm.prank(ALICE);
        fxrp.approve(address(vault), type(uint256).max);
        vm.prank(BOB);
        fxrp.approve(address(vault), type(uint256).max);
    }

    function testFirstDepositMintsOneToOneShares() external {
        vm.prank(ALICE);
        uint256 shares = vault.deposit(100 ether);

        assertEq(shares, 100 ether);
        assertEq(vault.balanceOf(ALICE), 100 ether);
        assertEq(vault.totalAssets(), 100 ether);
    }

    function testSecondDepositUsesAssetsBeforeTransfer() external {
        vm.prank(ALICE);
        vault.deposit(100 ether);
        fxrp.mint(address(vault), 100 ether);

        vm.prank(BOB);
        uint256 shares = vault.deposit(100 ether);

        assertEq(shares, 50 ether);
        assertEq(vault.totalSupply(), 150 ether);
        assertEq(vault.totalAssets(), 300 ether);
    }

    function testWithdrawBurnsSharesAndReturnsAssets() external {
        vm.prank(ALICE);
        vault.deposit(100 ether);

        vm.prank(ALICE);
        uint256 assets = vault.withdraw(40 ether);

        assertEq(assets, 40 ether);
        assertEq(vault.balanceOf(ALICE), 60 ether);
        assertEq(fxrp.balanceOf(ALICE), 940 ether);
    }

    function testSubmitPrivateIntentStoresCommitmentAndSequentialNonce() external {
        bytes32 commitment = keccak256("salted commitment");
        bytes memory ciphertext = hex"deadbeef";

        vm.expectEmit(true, true, false, true, address(vault));
        emit SignalVault.PrivateIntentSubmitted(ALICE, commitment, 1, ciphertext);
        vm.prank(ALICE);
        vault.submitPrivateIntent(ciphertext, commitment, 1);

        assertEq(vault.latestIntentCommitment(ALICE), commitment);
        assertEq(vault.userIntentNonce(ALICE), 1);
    }

    function testSubmitPrivateIntentRejectsStaleOrSkippedNonce() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(SignalVault.InvalidIntentNonce.selector, 1, 0));
        vault.submitPrivateIntent(hex"01", bytes32(uint256(1)), 0);

        vm.expectRevert(abi.encodeWithSelector(SignalVault.InvalidIntentNonce.selector, 1, 2));
        vault.submitPrivateIntent(hex"01", bytes32(uint256(1)), 2);
        vm.stopPrank();
    }
}
