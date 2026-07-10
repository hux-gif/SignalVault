// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SignalVault} from "src/SignalVault.sol";
import {IntentVerifier} from "src/IntentVerifier.sol";
import {Allocation, TEEResult} from "src/types/SignalVaultTypes.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract EmptyRouter {
    IERC20 public immutable asset;
    address public vault;

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    function bindVault(address vault_) external {
        vault = vault_;
    }

    function totalAssets() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function rebalance(Allocation calldata) external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function withdrawProRata(uint256, uint256) external pure returns (uint256) {
        return 0;
    }
}

contract ReentrantERC20 is MockERC20 {
    enum Attack {
        None,
        Deposit,
        Withdraw
    }
    SignalVault internal target;
    Attack internal attack;

    constructor() MockERC20("Reentrant FXRP", "rFXRP") {}

    function setAttack(SignalVault target_, Attack attack_) external {
        target = target_;
        attack = attack_;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (attack == Attack.Deposit && msg.sender == address(target)) target.deposit(1);
        return super.transferFrom(from, to, value);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (attack == Attack.Withdraw && msg.sender == address(target)) target.withdraw(1);
        return super.transfer(to, value);
    }
}

contract SixDecimalERC20 is MockERC20 {
    constructor() MockERC20("Six Decimal FXRP", "sFXRP") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract SignalVaultTest is Test {
    uint256 internal constant SIGNER_PK = 0xA11CE;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    MockERC20 internal fxrp;
    EmptyRouter internal router;
    IntentVerifier internal verifier;
    SignalVault internal vault;

    function setUp() external {
        fxrp = new MockERC20("Test FXRP", "FXRP");
        router = new EmptyRouter(fxrp);
        verifier = new IntentVerifier(vm.addr(SIGNER_PK));
        vault = new SignalVault(fxrp, address(router), address(verifier), ALICE);
        router.bindVault(address(vault));
        fxrp.mint(ALICE, 1_000 ether);
        vm.prank(ALICE);
        fxrp.approve(address(vault), type(uint256).max);
    }

    function testFirstDepositMintsOneToOneShares() external {
        vm.prank(ALICE);
        uint256 shares = vault.deposit(100 ether);
        assertEq(shares, 100 ether);
        assertEq(vault.balanceOf(ALICE), 100 ether);
    }

    function testShareDecimalsMatchAssetDecimals() external {
        SixDecimalERC20 token = new SixDecimalERC20();
        EmptyRouter decimalRouter = new EmptyRouter(token);
        SignalVault decimalVault =
            new SignalVault(token, address(decimalRouter), address(verifier), ALICE);
        assertEq(decimalVault.decimals(), 6);
    }

    function testSecondDepositUsesAssetsBeforeTransfer() external {
        vm.prank(ALICE);
        vault.deposit(100 ether);
        fxrp.mint(address(vault), 100 ether);
        vm.prank(ALICE);
        uint256 shares = vault.deposit(100 ether);
        assertEq(shares, 50 ether);
        assertEq(vault.totalAssets(), 300 ether);
    }

    function testWithdrawBurnsSharesAndReturnsAssets() external {
        vm.prank(ALICE);
        vault.deposit(100 ether);
        vm.prank(ALICE);
        uint256 assets = vault.withdraw(40 ether);
        assertEq(assets, 40 ether);
        assertEq(vault.balanceOf(ALICE), 60 ether);
    }

    function testNonOwnerCannotDepositWithdrawOrSubmitIntent() external {
        fxrp.mint(BOB, 10 ether);
        vm.startPrank(BOB);
        fxrp.approve(address(vault), type(uint256).max);
        vm.expectRevert(SignalVault.Unauthorized.selector);
        vault.deposit(1 ether);
        vm.expectRevert(SignalVault.Unauthorized.selector);
        vault.withdraw(1 ether);
        vm.expectRevert(SignalVault.Unauthorized.selector);
        vault.submitPrivateIntent(hex"01", bytes32(uint256(1)), 1);
        vm.stopPrank();
    }

    function testSharesCannotBeTransferred() external {
        vm.prank(ALICE);
        vault.deposit(10 ether);
        vm.prank(ALICE);
        vm.expectRevert(SignalVault.SharesNonTransferable.selector);
        bool transferred = vault.transfer(BOB, 1 ether);
        if (transferred) fail();
    }

    function testRejectsRouterAlreadyBoundToAnotherVault() external {
        vm.expectRevert(SignalVault.InvalidRouterVault.selector);
        new SignalVault(fxrp, address(router), address(verifier), BOB);
    }

    function testRejectsEmptyIntentOrZeroCommitment() external {
        vm.startPrank(ALICE);
        vm.expectRevert(SignalVault.EmptyEncryptedIntent.selector);
        vault.submitPrivateIntent("", bytes32(uint256(1)), 1);
        vm.expectRevert(SignalVault.InvalidIntentCommitment.selector);
        vault.submitPrivateIntent(hex"01", bytes32(0), 1);
        vm.stopPrank();
    }

    function testCanonicalResultHashAndOwnerAreRequired() external {
        bytes32 commitment = _submitIntent();
        TEEResult memory result = _result(commitment);
        result.resultHash = bytes32(uint256(123));
        bytes memory signature = _sign(result);
        vm.expectRevert(SignalVault.InvalidResultHash.selector);
        vault.executeTEEAllocation(result, signature);

        result = _result(commitment);
        result.user = BOB;
        result.resultHash = vault.computeResultHash(result);
        signature = _sign(result);
        vm.expectRevert(SignalVault.InvalidResultUser.selector);
        vault.executeTEEAllocation(result, signature);
    }

    function testCanonicalResultCannotBeReplayed() external {
        bytes32 commitment = _submitIntent();
        TEEResult memory result = _result(commitment);
        bytes memory signature = _sign(result);
        vault.executeTEEAllocation(result, signature);
        vm.expectRevert(SignalVault.ResultAlreadyExecuted.selector);
        vault.executeTEEAllocation(result, signature);
    }

    function testCannotExecuteBeforeOwnerSubmitsIntent() external {
        TEEResult memory result = _result(bytes32(0));
        result.nonce = 0;
        result.resultHash = vault.computeResultHash(result);
        bytes memory signature = _sign(result);

        vm.expectRevert(SignalVault.InvalidResult.selector);
        vault.executeTEEAllocation(result, signature);
    }

    function testTokenCannotReenterDeposit() external {
        (ReentrantERC20 token, SignalVault attackVault) = _reentrantVault();
        token.setAttack(attackVault, ReentrantERC20.Attack.Deposit);
        vm.prank(ALICE);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        attackVault.deposit(10 ether);
    }

    function testTokenCannotReenterWithdraw() external {
        (ReentrantERC20 token, SignalVault attackVault) = _reentrantVault();
        vm.prank(ALICE);
        attackVault.deposit(10 ether);
        token.setAttack(attackVault, ReentrantERC20.Attack.Withdraw);
        vm.prank(ALICE);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        attackVault.withdraw(1 ether);
    }

    function _submitIntent() internal returns (bytes32 commitment) {
        commitment = keccak256("salted commitment");
        vm.prank(ALICE);
        vault.submitPrivateIntent(hex"deadbeef", commitment, 1);
    }

    function _result(bytes32 commitment) internal view returns (TEEResult memory result) {
        result = TEEResult(
            ALICE,
            address(vault),
            commitment,
            Allocation(5_000, 2_000, 1_000, 2_000),
            1,
            block.timestamp + 1 hours,
            block.timestamp,
            block.chainid,
            bytes32(0)
        );
        result.resultHash = vault.computeResultHash(result);
    }

    function _sign(TEEResult memory result) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, verifier.hashTypedData(result));
        return abi.encodePacked(r, s, v);
    }

    function _reentrantVault() internal returns (ReentrantERC20 token, SignalVault attackVault) {
        token = new ReentrantERC20();
        EmptyRouter attackRouter = new EmptyRouter(token);
        attackVault = new SignalVault(token, address(attackRouter), address(verifier), ALICE);
        attackRouter.bindVault(address(attackVault));
        token.mint(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(address(attackVault), type(uint256).max);
    }
}
