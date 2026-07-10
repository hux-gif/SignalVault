// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SignalVault} from "src/SignalVault.sol";
import {IntentVerifier} from "src/IntentVerifier.sol";
import {StrategyRouter} from "src/StrategyRouter.sol";
import {MockStrategyAdapter} from "src/adapters/MockStrategyAdapter.sol";
import {IStrategyAdapter} from "src/interfaces/IStrategyAdapter.sol";
import {Allocation, TEEResult} from "src/types/SignalVaultTypes.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract ReentrantAdapter is IStrategyAdapter {
    using SafeERC20 for IERC20;
    IERC20 internal immutable token;
    address internal immutable router;
    SignalVault internal vault;
    TEEResult internal attackResult;
    bytes internal attackSignature;

    constructor(IERC20 token_, address router_) {
        token = token_;
        router = router_;
    }

    function setAttack(SignalVault vault_, TEEResult memory result_, bytes memory signature_)
        external
    {
        vault = vault_;
        attackResult = result_;
        attackSignature = signature_;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function deposit(uint256 amount) external returns (uint256) {
        require(msg.sender == router);
        token.safeTransferFrom(msg.sender, address(this), amount);
        vault.executeTEEAllocation(attackResult, attackSignature);
        return amount;
    }

    function withdraw(uint256 shares) external returns (uint256) {
        require(msg.sender == router);
        token.safeTransfer(msg.sender, shares);
        return shares;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function totalAssets() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function riskScore() external pure returns (uint256) {
        return 100;
    }

    function name() external pure returns (string memory) {
        return "Reentrant Adapter";
    }
}

contract StrategyRouterTest is Test {
    uint256 internal constant SIGNER_PK = 0xA11CE;
    address internal constant ALICE = address(0xCAFE);
    address internal constant ATTACKER = address(0xBAD);

    MockERC20 internal fxrp;
    IntentVerifier internal verifier;
    StrategyRouter internal router;
    SignalVault internal vault;
    MockStrategyAdapter internal upshift;
    MockStrategyAdapter internal firelight;
    MockStrategyAdapter internal sparkdex;
    MockStrategyAdapter internal idle;

    function setUp() external {
        fxrp = new MockERC20("Test FXRP", "FXRP");
        verifier = new IntentVerifier(vm.addr(SIGNER_PK));
        router = new StrategyRouter(fxrp);
        upshift = new MockStrategyAdapter(fxrp, address(router), "Upshift Simulation", 20);
        firelight = new MockStrategyAdapter(fxrp, address(router), "Firelight Simulation", 35);
        sparkdex = new MockStrategyAdapter(fxrp, address(router), "SparkDEX Simulation", 70);
        idle = new MockStrategyAdapter(fxrp, address(router), "Idle", 0);
        router.configureAdapters(
            address(upshift), address(firelight), address(sparkdex), address(idle)
        );
        vault = new SignalVault(fxrp, address(router), address(verifier), ALICE);
        router.bindVault(address(vault));
        fxrp.mint(ALICE, 1_000 ether);
        vm.prank(ALICE);
        fxrp.approve(address(vault), type(uint256).max);
    }

    function testFirstAllocationRoutesAndSecondAllocationRebalancesWithoutDoubleDeposit() external {
        _deposit(100 ether);
        _submitAndExecute(1, Allocation(5_000, 2_000, 1_000, 2_000));
        assertEq(fxrp.balanceOf(address(upshift)), 50 ether);
        assertEq(fxrp.balanceOf(address(idle)), 20 ether);
        assertEq(vault.totalAssets(), 100 ether);

        _submitAndExecute(2, Allocation(4_000, 2_000, 0, 4_000));
        assertEq(fxrp.balanceOf(address(upshift)), 40 ether);
        assertEq(fxrp.balanceOf(address(firelight)), 20 ether);
        assertEq(fxrp.balanceOf(address(sparkdex)), 0);
        assertEq(fxrp.balanceOf(address(idle)), 40 ether);
        assertEq(vault.totalAssets(), 100 ether);
    }

    function testDepositAfterAllocationUsesRouterNav() external {
        _deposit(100 ether);
        _submitAndExecute(1, Allocation(5_000, 2_000, 1_000, 2_000));
        vm.prank(ALICE);
        uint256 shares = vault.deposit(50 ether);
        assertEq(shares, 50 ether);
        assertEq(vault.totalAssets(), 150 ether);
    }

    function testFullWithdrawalReturnsAllAssetsAfterAllocation() external {
        _deposit(100 ether);
        _submitAndExecute(1, Allocation(5_000, 2_000, 1_000, 2_000));
        vm.prank(ALICE);
        uint256 received = vault.withdraw(100 ether);
        assertEq(received, 100 ether);
        assertEq(fxrp.balanceOf(ALICE), 1_000 ether);
        assertEq(router.totalAssets(), 0);
    }

    function testFullWithdrawalIncludesLiquidAssetsHeldByRouter() external {
        _deposit(100 ether);
        _submitAndExecute(1, Allocation(5_000, 2_000, 1_000, 2_000));
        fxrp.mint(address(router), 7 ether);

        vm.prank(ALICE);
        uint256 received = vault.withdraw(100 ether);

        assertEq(received, 107 ether);
        assertEq(fxrp.balanceOf(ALICE), 1_007 ether);
        assertEq(router.totalAssets(), 0);
    }

    function testWithdrawalRoundingIsBoundedAndFinalWithdrawalRecoversDust() external {
        _deposit(101);
        _submitAndExecute(1, Allocation(5_000, 2_000, 1_000, 2_000));
        vm.prank(ALICE);
        uint256 first = vault.withdraw(33);
        assertApproxEqAbs(first, 33, 3);
        vm.prank(ALICE);
        uint256 rest = vault.withdraw(68);
        assertEq(first + rest, 101);
    }

    function testRouterCanOnlyBeCalledByBoundVault() external {
        vm.startPrank(ATTACKER);
        vm.expectRevert(StrategyRouter.OnlyVault.selector);
        router.rebalance(Allocation(5_000, 2_000, 1_000, 2_000));
        vm.expectRevert(StrategyRouter.OnlyVault.selector);
        router.withdrawProRata(1, 1);
        vm.stopPrank();
    }

    function testRejectsDuplicateAdaptersAndSecondConfiguration() external {
        StrategyRouter freshRouter = new StrategyRouter(fxrp);
        MockStrategyAdapter adapterA = new MockStrategyAdapter(fxrp, address(freshRouter), "A", 1);
        MockStrategyAdapter adapterB = new MockStrategyAdapter(fxrp, address(freshRouter), "B", 2);
        MockStrategyAdapter adapterC = new MockStrategyAdapter(fxrp, address(freshRouter), "C", 3);

        vm.expectRevert(StrategyRouter.InvalidAdapter.selector);
        freshRouter.configureAdapters(
            address(adapterA), address(adapterA), address(adapterB), address(adapterC)
        );

        freshRouter.configureAdapters(
            address(adapterA), address(adapterB), address(adapterC), address(idle)
        );
        vm.expectRevert();
        freshRouter.configureAdapters(
            address(adapterA), address(adapterB), address(adapterC), address(idle)
        );
    }

    function testVaultCannotBeBoundBeforeAdaptersAreConfigured() external {
        StrategyRouter freshRouter = new StrategyRouter(fxrp);
        vm.expectRevert(StrategyRouter.AdaptersNotConfigured.selector);
        freshRouter.bindVault(address(this));
    }

    function testAdapterCannotReenterVault() external {
        StrategyRouter attackRouter = new StrategyRouter(fxrp);
        ReentrantAdapter attacker = new ReentrantAdapter(fxrp, address(attackRouter));
        MockStrategyAdapter attackFirelight =
            new MockStrategyAdapter(fxrp, address(attackRouter), "Firelight Simulation", 35);
        MockStrategyAdapter attackSparkdex =
            new MockStrategyAdapter(fxrp, address(attackRouter), "SparkDEX Simulation", 70);
        MockStrategyAdapter attackIdle =
            new MockStrategyAdapter(fxrp, address(attackRouter), "Idle", 0);
        attackRouter.configureAdapters(
            address(attacker),
            address(attackFirelight),
            address(attackSparkdex),
            address(attackIdle)
        );
        SignalVault attackVault =
            new SignalVault(fxrp, address(attackRouter), address(verifier), ALICE);
        attackRouter.bindVault(address(attackVault));
        vm.prank(ALICE);
        fxrp.approve(address(attackVault), type(uint256).max);
        vm.prank(ALICE);
        attackVault.deposit(100 ether);
        bytes32 commitment = keccak256("reentrant intent");
        vm.prank(ALICE);
        attackVault.submitPrivateIntent(hex"c0ffee", commitment, 1);
        TEEResult memory result = TEEResult(
            ALICE,
            address(attackVault),
            commitment,
            Allocation(5_000, 2_000, 1_000, 2_000),
            1,
            block.timestamp + 1 hours,
            block.timestamp,
            block.chainid,
            bytes32(0)
        );
        result.resultHash = attackVault.computeResultHash(result);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, verifier.hashTypedData(result));
        bytes memory signature = abi.encodePacked(r, s, v);
        attacker.setAttack(attackVault, result, signature);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        attackVault.executeTEEAllocation(result, signature);
        assertFalse(attackVault.executedResults(result.resultHash));
    }

    function _deposit(uint256 amount) internal {
        vm.prank(ALICE);
        vault.deposit(amount);
    }

    function _submitAndExecute(uint256 nonce, Allocation memory allocation) internal {
        bytes32 commitment = keccak256(abi.encode("intent", nonce));
        vm.prank(ALICE);
        vault.submitPrivateIntent(hex"c0ffee", commitment, nonce);
        TEEResult memory result = TEEResult(
            ALICE,
            address(vault),
            commitment,
            allocation,
            nonce,
            block.timestamp + 1 hours,
            block.timestamp,
            block.chainid,
            bytes32(0)
        );
        result.resultHash = vault.computeResultHash(result);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, verifier.hashTypedData(result));
        vault.executeTEEAllocation(result, abi.encodePacked(r, s, v));
    }
}
