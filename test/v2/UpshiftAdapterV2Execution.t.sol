// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {FeeAwareUpshiftVaultMock} from "./mocks/FeeAwareUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {ExecutionUpshiftVaultMock} from "./mocks/ExecutionUpshiftVaultMock.sol";
import {FalseReturnERC20V2} from "./mocks/FalseReturnERC20V2.sol";
import {SkimmingERC20V2} from "./mocks/SkimmingERC20V2.sol";

contract UpshiftAdapterV2ExecutionTest is Test {
    bytes4 internal constant ONLY_ROUTER = bytes4(keccak256("OnlyRouter()"));
    bytes4 internal constant ZERO_AMOUNT = bytes4(keccak256("ZeroAmount()"));
    bytes4 internal constant INSUFFICIENT_BALANCE = bytes4(keccak256("InsufficientBalance()"));
    bytes4 internal constant INSUFFICIENT_SHARES_OUT = bytes4(keccak256("InsufficientSharesOut()"));
    bytes4 internal constant INSUFFICIENT_ASSETS_OUT = bytes4(keccak256("InsufficientAssetsOut()"));
    bytes4 internal constant PROTOCOL_PAUSED = bytes4(keccak256("ProtocolPaused()"));
    bytes4 internal constant WITHDRAWAL_LIMIT_EXCEEDED =
        bytes4(keccak256("WithdrawalLimitExceeded()"));
    bytes4 internal constant PREVIEW_ZERO_NET = bytes4(keccak256("PreviewZeroNet()"));

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lp;
    FeeAwareUpshiftVaultMock internal protocol;
    UpshiftAdapterV2 internal adapter;

    address internal attacker = address(0xBAD);

    function setUp() public {
        asset = new MockLPTokenV2("MockFXRP", "MFXRP", 6);
        lp = new MockLPTokenV2("MockUpshiftLP", "MULP", 6);
        protocol = new FeeAwareUpshiftVaultMock(address(asset), address(lp));
        protocol.setInstantFee(50);
        adapter = new UpshiftAdapterV2(
            IERC20(address(asset)), address(this), protocol, IERC20(address(lp))
        );
    }

    function _fundAndApprove(uint256 amount) internal {
        asset.mint(address(this), amount);
        asset.approve(address(adapter), amount);
    }

    function _seedPosition(uint256 shares) internal {
        lp.mint(address(adapter), shares);
        asset.mint(address(protocol), shares);
    }

    function testAllMutationsAreRouterOnly() external {
        vm.startPrank(attacker);
        vm.expectRevert(ONLY_ROUTER);
        adapter.withdrawLiquid(1);
        vm.expectRevert(ONLY_ROUTER);
        adapter.deposit(1, 1);
        vm.expectRevert(ONLY_ROUTER);
        adapter.redeem(1, 1);
        vm.expectRevert(ONLY_ROUTER);
        adapter.redeemAll(1);
        vm.stopPrank();
    }

    function testWithdrawLiquidTransfersOnlyDirectUnderlying() external {
        asset.mint(address(adapter), 100);
        lp.mint(address(adapter), 77);
        uint256 routerBefore = asset.balanceOf(address(this));

        uint256 received = adapter.withdrawLiquid(40);

        assertEq(received, 40);
        assertEq(asset.balanceOf(address(this)) - routerBefore, 40);
        assertEq(asset.balanceOf(address(adapter)), 60);
        assertEq(lp.balanceOf(address(adapter)), 77);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testWithdrawLiquidRejectsZeroAndInsufficientDirectBalance() external {
        vm.expectRevert(ZERO_AMOUNT);
        adapter.withdrawLiquid(0);

        asset.mint(address(adapter), 9);
        vm.expectRevert(INSUFFICIENT_BALANCE);
        adapter.withdrawLiquid(10);
    }

    function testDepositUsesExactAllowanceAndMeasuresLpDelta() external {
        _fundAndApprove(10_000);
        uint256 shares = adapter.deposit(10_000, 9_000);

        assertEq(shares, 10_000);
        assertEq(lp.balanceOf(address(adapter)), 10_000);
        assertEq(asset.balanceOf(address(protocol)), 10_000);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(asset.allowance(address(this), address(adapter)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testDepositUsesActualNonOneToOneLpDelta() external {
        protocol.setDepositRates(2, 1, 3, 1);
        _fundAndApprove(5_000);

        uint256 shares = adapter.deposit(5_000, 9_999);

        assertEq(shares, 10_000);
        assertEq(lp.balanceOf(address(adapter)), 10_000);
    }

    function testDepositDoesNotApproveOrSpendPreexistingDirectUnderlying() external {
        asset.mint(address(adapter), 777);
        _fundAndApprove(1_000);

        adapter.deposit(1_000, 1);

        assertEq(asset.balanceOf(address(adapter)), 777);
        assertEq(asset.balanceOf(address(protocol)), 1_000);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
    }

    function testDepositMinSharesOutRevertsAtomically() external {
        _fundAndApprove(1_000);
        uint256 routerBefore = asset.balanceOf(address(this));

        vm.expectRevert(INSUFFICIENT_SHARES_OUT);
        adapter.deposit(1_000, 1_001);

        assertEq(asset.balanceOf(address(this)), routerBefore);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(asset.balanceOf(address(protocol)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(asset.allowance(address(this), address(adapter)), 1_000);
    }

    function testDepositRejectsZeroPauseAndBindingMismatch() external {
        vm.expectRevert(ZERO_AMOUNT);
        adapter.deposit(0, 0);

        protocol.setPaused(true);
        vm.expectRevert(PROTOCOL_PAUSED);
        adapter.deposit(1, 0);
        protocol.setPaused(false);

        protocol.setReportedAsset(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        adapter.deposit(1, 0);
    }

    function testRedeemMeasuresProtocolLpAndRouterDeltas() external {
        asset.mint(address(adapter), 100);
        _seedPosition(10_000);
        uint256 routerBefore = asset.balanceOf(address(this));

        uint256 received = adapter.redeem(10_000, 9_950);

        assertEq(received, 9_950);
        assertEq(asset.balanceOf(address(this)) - routerBefore, 9_950);
        assertEq(asset.balanceOf(address(adapter)), 100);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testRedeemMinAssetsOutRevertsAtomically() external {
        _seedPosition(10_000);

        vm.expectRevert(INSUFFICIENT_ASSETS_OUT);
        adapter.redeem(10_000, 9_951);

        assertEq(lp.balanceOf(address(adapter)), 10_000);
        assertEq(asset.balanceOf(address(protocol)), 10_000);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(asset.balanceOf(address(this)), 0);
    }

    function testRedeemRejectsZeroInsufficientSharesPauseAndBindingMismatch() external {
        vm.expectRevert(ZERO_AMOUNT);
        adapter.redeem(0, 0);

        vm.expectRevert(INSUFFICIENT_BALANCE);
        adapter.redeem(1, 0);

        _seedPosition(10);
        protocol.setPaused(true);
        vm.expectRevert(PROTOCOL_PAUSED);
        adapter.redeem(1, 0);
        protocol.setPaused(false);

        protocol.setReportedLPToken(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        adapter.redeem(1, 0);
    }

    function testRedeemConservativelyEnforcesGrossLimitBoundary() external {
        _seedPosition(100);
        protocol.setMaxWithdrawalReferenceAmount(100);
        assertEq(adapter.redeem(100, 1), 100);
    }

    function testRedeemRejectsGrossOneAboveLimit() external {
        _seedPosition(101);
        protocol.setMaxWithdrawalReferenceAmount(100);

        vm.expectRevert(WITHDRAWAL_LIMIT_EXCEEDED);
        adapter.redeem(101, 0);
    }

    function testRedeemRejectsZeroNetForNonzeroShares() external {
        _seedPosition(100);
        protocol.setInstantFee(10_000);
        vm.expectRevert(PREVIEW_ZERO_NET);
        adapter.redeem(100, 0);
        assertEq(lp.balanceOf(address(adapter)), 100);
        assertEq(asset.balanceOf(address(this)), 0);
    }

    function testRedeemAllSweepsDirectUnderlyingAndFullPositionWithoutDust() external {
        asset.mint(address(adapter), 100);
        _seedPosition(10_000);
        uint256 routerBefore = asset.balanceOf(address(this));

        uint256 received = adapter.redeemAll(10_050);

        assertEq(received, 10_050);
        assertEq(asset.balanceOf(address(this)) - routerBefore, 10_050);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testRedeemAllSupportsDirectOnlyAndSkipsProtocol() external {
        asset.mint(address(adapter), 123);

        assertEq(adapter.redeemAll(123), 123);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
    }

    function testRedeemAllRejectsZeroNetAndPreservesDirectUnderlying() external {
        protocol.setInstantFee(10_000);
        asset.mint(address(adapter), 7);
        _seedPosition(100);

        vm.expectRevert(PREVIEW_ZERO_NET);
        adapter.redeemAll(0);
        assertEq(asset.balanceOf(address(adapter)), 7);
        assertEq(lp.balanceOf(address(adapter)), 100);
    }

    function testRedeemAllRejectsEmptyAdapter() external {
        vm.expectRevert(ZERO_AMOUNT);
        adapter.redeemAll(0);
    }
}

contract UpshiftAdapterV2AdversarialExecutionTest is Test {
    event Deposited(
        uint256 requestedAssets,
        uint256 previewedShares,
        uint256 actualAssetsReceived,
        uint256 actualSharesReceived,
        uint256 rawInstantRedemptionFee
    );

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lp;
    ExecutionUpshiftVaultMock internal protocol;
    UpshiftAdapterV2 internal adapter;

    function setUp() public {
        asset = new MockLPTokenV2("MockFXRP", "MFXRP", 6);
        lp = new MockLPTokenV2("MockUpshiftLP", "MULP", 6);
        protocol = new ExecutionUpshiftVaultMock(address(asset), address(lp));
        adapter = new UpshiftAdapterV2(
            IERC20(address(asset)), address(this), protocol, IERC20(address(lp))
        );
    }

    function _fundAndApprove(uint256 amount) internal {
        asset.mint(address(this), amount);
        asset.approve(address(adapter), amount);
    }

    function _seedPosition(uint256 shares) internal {
        lp.mint(address(adapter), shares);
        asset.mint(address(protocol), shares);
    }

    function testWithdrawLiquidMakesNoProtocolCall() external {
        asset.mint(address(adapter), 100);
        adapter.withdrawLiquid(40);
        assertEq(protocol.depositCallCount(), 0);
        assertEq(protocol.redeemCallCount(), 0);
    }

    function testWithdrawLiquidFalseReturnRevertsAtomically() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        MockLPTokenV2 falseLP = new MockLPTokenV2("FalseLP", "FLP", 18);
        ExecutionUpshiftVaultMock falseProtocol =
            new ExecutionUpshiftVaultMock(address(falseAsset), address(falseLP));
        UpshiftAdapterV2 falseAdapter = new UpshiftAdapterV2(
            IERC20(address(falseAsset)), address(this), falseProtocol, IERC20(address(falseLP))
        );
        falseAsset.mint(address(falseAdapter), 100);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.Transfer);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseAsset))
        );
        falseAdapter.withdrawLiquid(50);

        assertEq(falseAsset.balanceOf(address(falseAdapter)), 100);
        assertEq(falseAsset.balanceOf(address(this)), 0);
    }

    function testWithdrawLiquidRejectsRouterUnderReceiptAndRollsBack() external {
        SkimmingERC20V2 skimAsset = new SkimmingERC20V2();
        MockLPTokenV2 skimLP = new MockLPTokenV2("SkimLP", "SLP", 18);
        ExecutionUpshiftVaultMock skimProtocol =
            new ExecutionUpshiftVaultMock(address(skimAsset), address(skimLP));
        UpshiftAdapterV2 skimAdapter = new UpshiftAdapterV2(
            IERC20(address(skimAsset)), address(this), skimProtocol, IERC20(address(skimLP))
        );
        skimAsset.mint(address(skimAdapter), 100);
        skimAsset.setTransferShortfall(address(skimAdapter), 1);

        vm.expectRevert(UpshiftAdapterV2.RouterDeltaMismatch.selector);
        skimAdapter.withdrawLiquid(50);

        assertEq(skimAsset.balanceOf(address(skimAdapter)), 100);
        assertEq(skimAsset.balanceOf(address(this)), 0);
    }

    function testDepositRejectsTransferFromShortfallAtomically() external {
        SkimmingERC20V2 skimAsset = new SkimmingERC20V2();
        MockLPTokenV2 skimLP = new MockLPTokenV2("SkimLP", "SLP", 18);
        ExecutionUpshiftVaultMock skimProtocol =
            new ExecutionUpshiftVaultMock(address(skimAsset), address(skimLP));
        UpshiftAdapterV2 skimAdapter = new UpshiftAdapterV2(
            IERC20(address(skimAsset)), address(this), skimProtocol, IERC20(address(skimLP))
        );
        skimAsset.mint(address(this), 1_000);
        skimAsset.approve(address(skimAdapter), 1_000);
        skimAsset.setTransferFromShortfall(address(this), 1);

        vm.expectRevert(UpshiftAdapterV2.AssetDeltaMismatch.selector);
        skimAdapter.deposit(1_000, 999);

        assertEq(skimAsset.balanceOf(address(this)), 1_000);
        assertEq(skimAsset.balanceOf(address(skimAdapter)), 0);
        assertEq(skimLP.balanceOf(address(skimAdapter)), 0);
        assertEq(skimAsset.balanceOf(address(skimProtocol)), 0);
        assertEq(skimAsset.allowance(address(skimAdapter), address(skimProtocol)), 0);
        assertEq(skimProtocol.depositCallCount(), 0);
    }

    function testDepositIgnoresProtocolReturnAndUsesActualMintDelta() external {
        protocol.setDepositMintOverride(true, 700);
        protocol.setDepositReturnOverride(true, type(uint256).max);
        _fundAndApprove(1_000);

        uint256 shares = adapter.deposit(1_000, 700);

        assertEq(shares, 700);
        assertEq(lp.balanceOf(address(adapter)), 700);
    }

    function testDepositClearsPartiallyConsumedAllowance() external {
        protocol.setDepositPullOverride(true, 600);
        protocol.setDepositMintOverride(true, 600);
        _fundAndApprove(1_000);

        assertEq(adapter.deposit(1_000, 600), 600);
        assertEq(asset.balanceOf(address(adapter)), 400);
        assertEq(protocol.lastRequestedDepositAmount(), 1_000);
        assertEq(protocol.lastObservedDepositAllowance(), 1_000);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
    }

    function testDepositApprovalCannotExposePreexistingDirectDonationToOverPull() external {
        asset.mint(address(adapter), 777);
        protocol.setDepositPullOverride(true, 1_777);
        _fundAndApprove(1_000);

        vm.expectRevert();
        adapter.deposit(1_000, 1);

        assertEq(asset.balanceOf(address(this)), 1_000);
        assertEq(asset.balanceOf(address(adapter)), 777);
        assertEq(asset.balanceOf(address(protocol)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(asset.allowance(address(this), address(adapter)), 1_000);
    }

    function testDepositEventSeparatesRequestedPreviewedAndActualValues() external {
        protocol.setFee(50);
        protocol.setDepositMintOverride(true, 700);
        _fundAndApprove(1_000);
        vm.expectEmit(address(adapter));
        emit Deposited(1_000, 1_000, 1_000, 700, 50);

        adapter.deposit(1_000, 700);
    }

    function testDepositZeroMintRevertsAtomically() external {
        protocol.setDepositMintOverride(true, 0);
        _fundAndApprove(1_000);

        vm.expectRevert(UpshiftAdapterV2.ZeroSharesReceived.selector);
        adapter.deposit(1_000, 0);

        assertEq(asset.balanceOf(address(this)), 1_000);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(asset.balanceOf(address(protocol)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
    }

    function testDepositProtocolRevertRollsBackTransferAndApproval() external {
        protocol.setDepositReverts(true);
        _fundAndApprove(1_000);

        vm.expectRevert(ExecutionUpshiftVaultMock.ConfiguredRevert.selector);
        adapter.deposit(1_000, 1);

        assertEq(asset.balanceOf(address(this)), 1_000);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
    }

    function testDepositFalseReturnTransferFromRevertsAtomically() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        MockLPTokenV2 falseLP = new MockLPTokenV2("FalseLP", "FLP", 18);
        ExecutionUpshiftVaultMock falseProtocol =
            new ExecutionUpshiftVaultMock(address(falseAsset), address(falseLP));
        UpshiftAdapterV2 falseAdapter = new UpshiftAdapterV2(
            IERC20(address(falseAsset)), address(this), falseProtocol, IERC20(address(falseLP))
        );
        falseAsset.mint(address(this), 1_000);
        falseAsset.approve(address(falseAdapter), 1_000);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.TransferFrom);

        vm.expectRevert();
        falseAdapter.deposit(1_000, 1);

        assertEq(falseAsset.balanceOf(address(this)), 1_000);
        assertEq(falseAsset.balanceOf(address(falseAdapter)), 0);
        assertEq(falseLP.balanceOf(address(falseAdapter)), 0);
    }

    function reenterDepositPath() external {
        adapter.withdrawLiquid(1);
    }

    function testDepositProtocolCallbackHitsReentrancyGuardThroughRouterIdentity() external {
        _fundAndApprove(100);
        protocol.armDepositCallback(address(this), abi.encodeCall(this.reenterDepositPath, ()));

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        adapter.deposit(100, 1);

        assertEq(asset.balanceOf(address(this)), 100);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(protocol.depositCallCount(), 0);
    }

    /// @dev Direct reentrancy test: the callback calls adapter.deposit (not withdrawLiquid)
    /// so the inner deposit hits the ReentrancyGuard directly. Removing the outer
    /// deposit.nonReentrant lets the inner deposit proceed and the expected selector
    /// never materializes, failing the test without relying on bypass errors.
    function reenterDepositDirectly() external {
        // Disarm callback so it only fires once.
        protocol.armDepositCallback(address(0), "");
        // Inner deposit — router (test contract) has pre-funded balance and allowance.
        adapter.deposit(50, 1);
    }

    function testDepositProtocolCallbackHitsReentrancyGuardDirectly() external {
        // Fund for outer (100) and inner (50) deposits.
        _fundAndApprove(150);
        protocol.armDepositCallback(address(this), abi.encodeCall(this.reenterDepositDirectly, ()));

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        adapter.deposit(100, 1);

        assertEq(asset.balanceOf(address(this)), 150);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(asset.balanceOf(address(protocol)), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
        assertEq(protocol.depositCallCount(), 0);
    }

    /// @dev A skimming Router transfer must fail before a malicious protocol can over-pull
    /// or gain access to a pre-existing direct donation.
    function testDepositShortfallBlocksProtocolOverPullAndProtectsDonation() external {
        SkimmingERC20V2 skimAsset = new SkimmingERC20V2();
        MockLPTokenV2 skimLP = new MockLPTokenV2("SkimLP", "SLP", 18);
        ExecutionUpshiftVaultMock skimProtocol =
            new ExecutionUpshiftVaultMock(address(skimAsset), address(skimLP));
        UpshiftAdapterV2 skimAdapter = new UpshiftAdapterV2(
            IERC20(address(skimAsset)), address(this), skimProtocol, IERC20(address(skimLP))
        );

        // D = 100 preexisting direct donation.
        skimAsset.mint(address(skimAdapter), 100);
        // A = 1_000 requested, S = 1 shortfall → actualAssetsReceived = 999.
        skimAsset.mint(address(this), 1_000);
        skimAsset.approve(address(skimAdapter), 1_000);
        skimAsset.setTransferFromShortfall(address(this), 1);
        // Malicious protocol tries to pull A = 1_000 instead of 999.
        skimProtocol.setDepositPullOverride(true, 1_000);

        vm.expectRevert(UpshiftAdapterV2.AssetDeltaMismatch.selector);
        skimAdapter.deposit(1_000, 1);

        // Rollback: everything restored.
        assertEq(skimAsset.balanceOf(address(this)), 1_000);
        assertEq(skimAsset.balanceOf(address(skimAdapter)), 100);
        assertEq(skimAsset.balanceOf(address(skimProtocol)), 0);
        assertEq(skimLP.balanceOf(address(skimAdapter)), 0);
        assertEq(skimAsset.allowance(address(skimAdapter), address(skimProtocol)), 0);
        assertEq(skimLP.allowance(address(skimAdapter), address(skimProtocol)), 0);
        assertEq(skimProtocol.depositCallCount(), 0);
    }

    /// @dev A Router-to-adapter shortfall must fail before protocol approval or deposit.
    function testDepositUnderTransferNeverReachesProtocol() external {
        SkimmingERC20V2 skimAsset = new SkimmingERC20V2();
        MockLPTokenV2 skimLP = new MockLPTokenV2("SkimLP", "SLP", 18);
        ExecutionUpshiftVaultMock skimProtocol =
            new ExecutionUpshiftVaultMock(address(skimAsset), address(skimLP));
        UpshiftAdapterV2 skimAdapter = new UpshiftAdapterV2(
            IERC20(address(skimAsset)), address(this), skimProtocol, IERC20(address(skimLP))
        );

        skimAsset.mint(address(this), 1_000);
        skimAsset.approve(address(skimAdapter), 1_000);
        skimAsset.setTransferFromShortfall(address(this), 1);

        vm.expectRevert(UpshiftAdapterV2.AssetDeltaMismatch.selector);
        skimAdapter.deposit(1_000, 999);

        assertEq(skimProtocol.lastRequestedDepositAmount(), 0);
        assertEq(skimProtocol.lastObservedDepositAllowance(), 0);
        assertEq(skimProtocol.depositCallCount(), 0);
        assertEq(skimAsset.balanceOf(address(this)), 1_000);
        assertEq(skimAsset.balanceOf(address(skimAdapter)), 0);
    }

    function testRedeemRejectsUnderBurnAndRollsBack() external {
        _seedPosition(100);
        protocol.setRedeemBurnOverride(true, 99);

        vm.expectRevert(UpshiftAdapterV2.ShareDeltaMismatch.selector);
        adapter.redeem(100, 0);

        assertEq(lp.balanceOf(address(adapter)), 100);
        assertEq(asset.balanceOf(address(protocol)), 100);
        assertEq(asset.balanceOf(address(adapter)), 0);
    }

    function testRedeemRejectsOverBurnAndRollsBack() external {
        _seedPosition(101);
        protocol.setRedeemBurnOverride(true, 101);

        vm.expectRevert(UpshiftAdapterV2.ShareDeltaMismatch.selector);
        adapter.redeem(100, 0);

        assertEq(lp.balanceOf(address(adapter)), 101);
        assertEq(asset.balanceOf(address(protocol)), 101);
    }

    function testRedeemUnderTransferFailsMinOutAndRollsBack() external {
        _seedPosition(100);
        protocol.setRedeemTransferOverride(true, 99);

        vm.expectRevert(UpshiftAdapterV2.InsufficientAssetsOut.selector);
        adapter.redeem(100, 100);

        assertEq(lp.balanceOf(address(adapter)), 100);
        assertEq(asset.balanceOf(address(protocol)), 100);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(asset.balanceOf(address(this)), 0);
    }

    function testRedeemProtocolAndPreviewRevertsAreAtomic() external {
        _seedPosition(100);
        protocol.setPreviewReverts(true);
        vm.expectRevert(UpshiftAdapterV2.PreviewReverted.selector);
        adapter.redeem(100, 0);
        protocol.setPreviewReverts(false);
        protocol.setRedeemReverts(true);
        vm.expectRevert(ExecutionUpshiftVaultMock.ConfiguredRevert.selector);
        adapter.redeem(100, 0);

        assertEq(lp.balanceOf(address(adapter)), 100);
        assertEq(asset.balanceOf(address(protocol)), 100);
    }

    function testRedeemRejectsRouterUnderReceiptAndRollsBack() external {
        SkimmingERC20V2 skimAsset = new SkimmingERC20V2();
        MockLPTokenV2 skimLP = new MockLPTokenV2("SkimLP", "SLP", 18);
        ExecutionUpshiftVaultMock skimProtocol =
            new ExecutionUpshiftVaultMock(address(skimAsset), address(skimLP));
        UpshiftAdapterV2 skimAdapter = new UpshiftAdapterV2(
            IERC20(address(skimAsset)), address(this), skimProtocol, IERC20(address(skimLP))
        );
        skimLP.mint(address(skimAdapter), 100);
        skimAsset.mint(address(skimProtocol), 100);
        skimAsset.setTransferShortfall(address(skimAdapter), 1);

        vm.expectRevert(UpshiftAdapterV2.RouterDeltaMismatch.selector);
        skimAdapter.redeem(100, 0);

        assertEq(skimLP.balanceOf(address(skimAdapter)), 100);
        assertEq(skimAsset.balanceOf(address(skimProtocol)), 100);
        assertEq(skimAsset.balanceOf(address(this)), 0);
    }

    function testRedeemFalseReturnProtocolTransferRevertsAtomically() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        MockLPTokenV2 falseLP = new MockLPTokenV2("FalseLP", "FLP", 18);
        ExecutionUpshiftVaultMock falseProtocol =
            new ExecutionUpshiftVaultMock(address(falseAsset), address(falseLP));
        UpshiftAdapterV2 falseAdapter = new UpshiftAdapterV2(
            IERC20(address(falseAsset)), address(this), falseProtocol, IERC20(address(falseLP))
        );
        falseLP.mint(address(falseAdapter), 100);
        falseAsset.mint(address(falseProtocol), 100);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.Transfer);

        vm.expectRevert();
        falseAdapter.redeem(100, 0);

        assertEq(falseLP.balanceOf(address(falseAdapter)), 100);
        assertEq(falseAsset.balanceOf(address(falseProtocol)), 100);
        assertEq(falseAsset.balanceOf(address(falseAdapter)), 0);
    }

    function testRedeemFalseReturnAdapterTransferRevertsAtomically() external {
        SkimmingERC20V2 falseAsset = new SkimmingERC20V2();
        MockLPTokenV2 falseLP = new MockLPTokenV2("FalseLP", "FLP", 18);
        ExecutionUpshiftVaultMock falseProtocol =
            new ExecutionUpshiftVaultMock(address(falseAsset), address(falseLP));
        UpshiftAdapterV2 falseAdapter = new UpshiftAdapterV2(
            IERC20(address(falseAsset)), address(this), falseProtocol, IERC20(address(falseLP))
        );
        falseLP.mint(address(falseAdapter), 100);
        falseAsset.mint(address(falseProtocol), 100);
        falseAsset.setFalseTransferSender(address(falseAdapter));

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseAsset))
        );
        falseAdapter.redeem(100, 0);

        assertEq(falseLP.balanceOf(address(falseAdapter)), 100);
        assertEq(falseAsset.balanceOf(address(falseProtocol)), 100);
        assertEq(falseAsset.balanceOf(address(falseAdapter)), 0);
        assertEq(falseAsset.balanceOf(address(this)), 0);
    }

    function reenterRedeemPath() external {
        adapter.withdrawLiquid(1);
    }

    function testRedeemProtocolCallbackHitsReentrancyGuardThroughRouterIdentity() external {
        _seedPosition(100);
        protocol.armRedeemCallback(address(this), abi.encodeCall(this.reenterRedeemPath, ()));

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        adapter.redeem(100, 0);

        assertEq(lp.balanceOf(address(adapter)), 100);
        assertEq(protocol.redeemCallCount(), 0);
    }

    function testNetAtLimitStillRejectsWhenGrossExceedsLimit() external {
        protocol.setFee(50);
        _seedPosition(10_000);
        protocol.setLimit(9_950);

        vm.expectRevert(UpshiftAdapterV2.WithdrawalLimitExceeded.selector);
        adapter.redeem(10_000, 0);
    }

    function testRedeemAllDirectOnlyDoesNotCallProtocol() external {
        asset.mint(address(adapter), 10);
        assertEq(adapter.redeemAll(10), 10);
        assertEq(protocol.depositCallCount(), 0);
        assertEq(protocol.redeemCallCount(), 0);
    }

    function testRedeemAllDirectOnlyFalseReturnRevertsAtomically() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        MockLPTokenV2 falseLP = new MockLPTokenV2("FalseLP", "FLP", 18);
        ExecutionUpshiftVaultMock falseProtocol =
            new ExecutionUpshiftVaultMock(address(falseAsset), address(falseLP));
        UpshiftAdapterV2 falseAdapter = new UpshiftAdapterV2(
            IERC20(address(falseAsset)), address(this), falseProtocol, IERC20(address(falseLP))
        );
        falseAsset.mint(address(falseAdapter), 100);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.Transfer);

        vm.expectRevert();
        falseAdapter.redeemAll(0);

        assertEq(falseAsset.balanceOf(address(falseAdapter)), 100);
        assertEq(falseAsset.balanceOf(address(this)), 0);
    }

    function testRedeemAllUnderBurnRevertsAndKeepsDirectDonation() external {
        asset.mint(address(adapter), 7);
        _seedPosition(100);
        protocol.setRedeemBurnOverride(true, 99);

        vm.expectRevert(UpshiftAdapterV2.ShareDeltaMismatch.selector);
        adapter.redeemAll(0);

        assertEq(asset.balanceOf(address(adapter)), 7);
        assertEq(lp.balanceOf(address(adapter)), 100);
    }

    function testRedeemAllMinOutPauseAndLimitFailuresAreAtomic() external {
        asset.mint(address(adapter), 7);
        _seedPosition(100);
        vm.expectRevert(UpshiftAdapterV2.InsufficientAssetsOut.selector);
        adapter.redeemAll(108);
        assertEq(asset.balanceOf(address(adapter)), 7);
        assertEq(lp.balanceOf(address(adapter)), 100);

        protocol.setPaused(true);
        vm.expectRevert(UpshiftAdapterV2.ProtocolPaused.selector);
        adapter.redeemAll(0);
        protocol.setPaused(false);

        protocol.setLimit(99);
        vm.expectRevert(UpshiftAdapterV2.WithdrawalLimitExceeded.selector);
        adapter.redeemAll(0);
        assertEq(asset.balanceOf(address(adapter)), 7);
        assertEq(lp.balanceOf(address(adapter)), 100);
    }

    function testRedeemAllUnderTransferFailsFullExpectedMinOutAndRollsBack() external {
        asset.mint(address(adapter), 7);
        _seedPosition(100);
        protocol.setRedeemTransferOverride(true, 99);

        vm.expectRevert(UpshiftAdapterV2.InsufficientAssetsOut.selector);
        adapter.redeemAll(107);

        assertEq(asset.balanceOf(address(this)), 0);
        assertEq(asset.balanceOf(address(adapter)), 7);
        assertEq(asset.balanceOf(address(protocol)), 100);
        assertEq(lp.balanceOf(address(adapter)), 100);
    }

    function testRuntimeBindingsProtectWithdrawLiquidAndRedeemAll() external {
        asset.mint(address(adapter), 1);
        protocol.setReportedAsset(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        adapter.withdrawLiquid(1);
        protocol.setReportedAsset(address(asset));
        protocol.setReportedLPToken(address(0xDEAD));
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        adapter.redeemAll(0);
    }
}
