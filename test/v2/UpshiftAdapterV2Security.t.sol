// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {IdleAdapterV2} from "../../src/v2/adapters/IdleAdapterV2.sol";
import {IStrategyRecoveryV2} from "../../src/v2/interfaces/IStrategyRecoveryV2.sol";
import {ExecutionUpshiftVaultMock} from "./mocks/ExecutionUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {FalseReturnERC20V2} from "./mocks/FalseReturnERC20V2.sol";
import {ReentrantERC20V2} from "./mocks/ReentrantERC20V2.sol";
import {AdversarialDebitERC20V2} from "./mocks/AdversarialDebitERC20V2.sol";
import {SkimmingERC20V2} from "./mocks/SkimmingERC20V2.sol";
import {ReentrantUpshiftVaultMock} from "./mocks/ReentrantUpshiftVaultMock.sol";
import {MaliciousStrategyAdapterV2} from "./mocks/MaliciousStrategyAdapterV2.sol";

contract UpshiftAdapterV2SecurityTest is Test {
    bytes4 internal constant ONLY_ROUTER = bytes4(keccak256("OnlyRouter()"));
    bytes4 internal constant ZERO_ADDRESS = bytes4(keccak256("ZeroAddress()"));
    bytes4 internal constant ZERO_POSITION = bytes4(keccak256("ZeroPosition()"));
    bytes4 internal constant POSITION_RECOVERED = bytes4(keccak256("PositionRecovered()"));
    bytes4 internal constant ASSET_DELTA_MISMATCH = bytes4(keccak256("AssetDeltaMismatch()"));

    event EmergencyPositionRecovered(address indexed token, uint256 amount, address receiver);

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lp;
    ExecutionUpshiftVaultMock internal protocol;
    UpshiftAdapterV2 internal adapter;
    IStrategyRecoveryV2 internal recovery;

    address internal attacker = address(0xBAD);
    address internal receiver = address(0xBEEF);

    function setUp() public {
        asset = new MockLPTokenV2("MockFXRP", "MFXRP", 6);
        lp = new MockLPTokenV2("MockUpshiftLP", "MULP", 6);
        protocol = new ReentrantUpshiftVaultMock(address(asset), address(lp));
        adapter = new UpshiftAdapterV2(
            IERC20(address(asset)), address(this), protocol, IERC20(address(lp))
        );
        recovery = IStrategyRecoveryV2(address(adapter));
    }

    function _isRecovered() internal view returns (bool) {
        (bool ok, bytes memory data) =
            address(adapter).staticcall(abi.encodeWithSignature("positionRecovered()"));
        assertTrue(ok);
        return abi.decode(data, (bool));
    }

    function testRecoverPositionIsRouterOnly() external {
        lp.mint(address(adapter), 100);
        vm.prank(attacker);
        vm.expectRevert(ONLY_ROUTER);
        recovery.recoverPosition(receiver);
    }

    function testProtocolCannotInvokeRecovery() external {
        lp.mint(address(adapter), 100);
        vm.prank(address(protocol));
        vm.expectRevert(ONLY_ROUTER);
        recovery.recoverPosition(receiver);
    }

    function testRecoverPositionRejectsZeroReceiver() external {
        lp.mint(address(adapter), 100);
        vm.expectRevert(ZERO_ADDRESS);
        recovery.recoverPosition(address(0));
    }

    function testRecoverPositionRejectsZeroPosition() external {
        vm.expectRevert(ZERO_POSITION);
        recovery.recoverPosition(receiver);
    }

    function testRecoverPositionTransfersCompletePinnedLpAndMeasuresDeltas() external {
        lp.mint(address(adapter), 10_000);
        vm.expectEmit(address(adapter));
        emit EmergencyPositionRecovered(address(lp), 10_000, receiver);

        uint256 recovered = recovery.recoverPosition(receiver);

        assertEq(recovered, 10_000);
        assertEq(lp.balanceOf(address(adapter)), 0);
        assertEq(lp.balanceOf(receiver), 10_000);
        assertTrue(_isRecovered());
        assertEq(protocol.redeemCallCount(), 0);
        assertEq(asset.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(protocol)), 0);
        assertEq(lp.allowance(address(adapter), address(this)), 0);
    }

    function testRecoveryLeavesDirectUnderlyingForRouterSweep() external {
        asset.mint(address(adapter), 77);
        lp.mint(address(adapter), 100);
        recovery.recoverPosition(receiver);

        assertEq(asset.balanceOf(address(adapter)), 77);
        assertEq(adapter.withdrawLiquid(77), 77);
        assertEq(asset.balanceOf(address(this)), 77);
        assertEq(asset.balanceOf(address(adapter)), 0);
    }

    function testWithdrawLiquidAfterRecoveryStillRejectsAdapterOverDebitAtomically() external {
        AdversarialDebitERC20V2 hostileAsset = new AdversarialDebitERC20V2();
        MockLPTokenV2 hostileLP = new MockLPTokenV2("Hostile LP", "HLP", 18);
        ExecutionUpshiftVaultMock hostileProtocol =
            new ExecutionUpshiftVaultMock(address(hostileAsset), address(hostileLP));
        UpshiftAdapterV2 hostileAdapter = new UpshiftAdapterV2(
            IERC20(address(hostileAsset)),
            address(this),
            hostileProtocol,
            IERC20(address(hostileLP))
        );

        hostileLP.mint(address(hostileAdapter), 1);
        IStrategyRecoveryV2(address(hostileAdapter)).recoverPosition(receiver);
        hostileAsset.mint(address(hostileAdapter), 200);
        hostileAsset.configureDebit(
            address(hostileAdapter), AdversarialDebitERC20V2.DebitMode.OverDebit, 1
        );

        vm.expectRevert(UpshiftAdapterV2.AssetDeltaMismatch.selector);
        hostileAdapter.withdrawLiquid(100);

        assertEq(hostileAsset.balanceOf(address(hostileAdapter)), 200);
        assertEq(hostileAsset.balanceOf(address(this)), 0);
        assertEq(hostileProtocol.depositCallCount(), 0);
        assertEq(hostileProtocol.redeemCallCount(), 0);
        assertTrue(hostileAdapter.positionRecovered());
    }

    function testNormalProtocolOperationsAreDisabledAfterRecovery() external {
        asset.mint(address(this), 100);
        asset.approve(address(adapter), 100);
        lp.mint(address(adapter), 100);
        recovery.recoverPosition(receiver);

        vm.expectRevert(POSITION_RECOVERED);
        adapter.deposit(100, 1);
        vm.expectRevert(POSITION_RECOVERED);
        adapter.redeem(1, 0);
        vm.expectRevert(POSITION_RECOVERED);
        adapter.redeemAll(0);
        vm.expectRevert(POSITION_RECOVERED);
        adapter.totalAssets();
        vm.expectRevert(POSITION_RECOVERED);
        adapter.grossAssets();
        vm.expectRevert(POSITION_RECOVERED);
        adapter.availableLiquidity();
        vm.expectRevert(POSITION_RECOVERED);
        adapter.protocolStatus();
        vm.expectRevert(POSITION_RECOVERED);
        adapter.previewDeposit(1);
        vm.expectRevert(POSITION_RECOVERED);
        adapter.previewRedeem(1);
    }

    function testDepositRejectsUnderlyingUnderTransferAtomically() external {
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

        vm.expectRevert(ASSET_DELTA_MISMATCH);
        skimAdapter.deposit(1_000, 1);

        assertEq(skimAsset.balanceOf(address(this)), 1_000);
        assertEq(skimAsset.balanceOf(address(skimAdapter)), 0);
        assertEq(skimAsset.balanceOf(address(skimProtocol)), 0);
        assertEq(skimLP.balanceOf(address(skimAdapter)), 0);
        assertEq(skimAsset.allowance(address(skimAdapter), address(skimProtocol)), 0);
    }

    function testSecondRecoveryIsPermanentlyDisabled() external {
        lp.mint(address(adapter), 100);
        recovery.recoverPosition(receiver);
        lp.mint(address(adapter), 1);
        vm.expectRevert(POSITION_RECOVERED);
        recovery.recoverPosition(receiver);
    }

    function testRecoveryUsesPinnedLpDespitePauseAndBrokenProtocolGetters() external {
        lp.mint(address(adapter), 100);
        protocol.setPaused(true);
        protocol.setPreviewReverts(true);
        protocol.setBindingGettersRevert(true);

        assertEq(recovery.recoverPosition(receiver), 100);
        assertEq(lp.balanceOf(receiver), 100);
    }

    function testRecoveryRemainsAvailableWhenPositionNetIsZero() external {
        lp.mint(address(adapter), 100);
        protocol.setFee(10_000);

        assertEq(recovery.recoverPosition(receiver), 100);
        assertEq(lp.balanceOf(receiver), 100);
        assertEq(protocol.redeemCallCount(), 0);
    }

    function testRecoveryDoesNotSweepUnknownTokenOrUnderlying() external {
        MockLPTokenV2 unknown = new MockLPTokenV2("Unknown", "UNK", 18);
        asset.mint(address(adapter), 7);
        unknown.mint(address(adapter), 9);
        lp.mint(address(adapter), 100);

        recovery.recoverPosition(receiver);

        assertEq(asset.balanceOf(address(adapter)), 7);
        assertEq(unknown.balanceOf(address(adapter)), 9);
        assertEq(asset.balanceOf(receiver), 0);
        assertEq(unknown.balanceOf(receiver), 0);
    }

    function testFalseReturnLpRecoveryRevertsAtomically() external {
        FalseReturnERC20V2 falseLP = new FalseReturnERC20V2();
        ExecutionUpshiftVaultMock localProtocol =
            new ExecutionUpshiftVaultMock(address(asset), address(falseLP));
        UpshiftAdapterV2 localAdapter = new UpshiftAdapterV2(
            IERC20(address(asset)), address(this), localProtocol, IERC20(address(falseLP))
        );
        falseLP.mint(address(localAdapter), 100);
        falseLP.setFailureMode(FalseReturnERC20V2.FailureMode.Transfer);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseLP))
        );
        IStrategyRecoveryV2(address(localAdapter)).recoverPosition(receiver);
        assertEq(falseLP.balanceOf(address(localAdapter)), 100);
        assertEq(falseLP.balanceOf(receiver), 0);
    }

    function testSkimmingLpRecoveryRejectsReceiverDeltaAndRollsBack() external {
        SkimmingERC20V2 skimLP = new SkimmingERC20V2();
        ExecutionUpshiftVaultMock localProtocol =
            new ExecutionUpshiftVaultMock(address(asset), address(skimLP));
        UpshiftAdapterV2 localAdapter = new UpshiftAdapterV2(
            IERC20(address(asset)), address(this), localProtocol, IERC20(address(skimLP))
        );
        skimLP.mint(address(localAdapter), 100);
        skimLP.setTransferShortfall(address(localAdapter), 1);

        vm.expectRevert(UpshiftAdapterV2.RecoveryDeltaMismatch.selector);
        IStrategyRecoveryV2(address(localAdapter)).recoverPosition(receiver);
        assertEq(skimLP.balanceOf(address(localAdapter)), 100);
        assertEq(skimLP.balanceOf(receiver), 0);
    }

    UpshiftAdapterV2 internal callbackAdapter;
    IStrategyRecoveryV2 internal callbackRecovery;
    ExecutionUpshiftVaultMock internal callbackProtocol;

    function reenterRecovery() external {
        callbackRecovery.recoverPosition(receiver);
    }

    function reenterWithdrawLiquid() external {
        callbackAdapter.withdrawLiquid(1);
    }

    function reenterRedeem() external {
        callbackProtocol.armRedeemCallback(address(0), "");
        callbackAdapter.redeem(1, 0);
    }

    function reenterRedeemAll() external {
        callbackProtocol.armRedeemCallback(address(0), "");
        callbackAdapter.redeemAll(0);
    }

    function reenterWithdrawLiquidAfterDisarm() external {
        callbackProtocol.armRedeemCallback(address(0), "");
        callbackAdapter.withdrawLiquid(1);
    }

    function _setUpProtocolCallbackAdapter(uint256 shares, uint256 directAssets) internal {
        MockLPTokenV2 localLP = new MockLPTokenV2("CallbackLP", "CLP", 18);
        callbackProtocol = new ExecutionUpshiftVaultMock(address(asset), address(localLP));
        callbackAdapter = new UpshiftAdapterV2(
            IERC20(address(asset)), address(this), callbackProtocol, IERC20(address(localLP))
        );
        localLP.mint(address(callbackAdapter), shares);
        asset.mint(address(callbackProtocol), shares);
        if (directAssets > 0) asset.mint(address(callbackAdapter), directAssets);
    }

    function testRedeemCannotReenterRedeemOrRedeemAll() external {
        _setUpProtocolCallbackAdapter(100, 0);
        callbackProtocol.armRedeemCallback(address(this), abi.encodeCall(this.reenterRedeem, ()));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        callbackAdapter.redeem(100, 0);

        callbackProtocol.armRedeemCallback(address(this), abi.encodeCall(this.reenterRedeemAll, ()));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        callbackAdapter.redeem(100, 0);
    }

    function testRedeemAllCannotReenterWithdrawLiquid() external {
        _setUpProtocolCallbackAdapter(100, 1);
        callbackProtocol.armRedeemCallback(
            address(this), abi.encodeCall(this.reenterWithdrawLiquidAfterDisarm, ())
        );
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        callbackAdapter.redeemAll(0);
    }

    function testRecoveryCannotReenterRecoveryOrNormalOperation() external {
        ReentrantERC20V2 callbackLP = new ReentrantERC20V2();
        ExecutionUpshiftVaultMock localProtocol =
            new ExecutionUpshiftVaultMock(address(asset), address(callbackLP));
        callbackAdapter = new UpshiftAdapterV2(
            IERC20(address(asset)), address(this), localProtocol, IERC20(address(callbackLP))
        );
        callbackRecovery = IStrategyRecoveryV2(address(callbackAdapter));
        callbackLP.mint(address(callbackAdapter), 100);
        callbackLP.armCallback(address(this), abi.encodeCall(this.reenterRecovery, ()));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        callbackRecovery.recoverPosition(receiver);
        assertEq(callbackLP.balanceOf(address(callbackAdapter)), 100);

        asset.mint(address(callbackAdapter), 1);
        callbackLP.armCallback(address(this), abi.encodeCall(this.reenterWithdrawLiquid, ()));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        callbackRecovery.recoverPosition(receiver);
        assertEq(asset.balanceOf(address(callbackAdapter)), 1);
    }

    function testNormalDepositCannotReenterRecovery() external {
        ReentrantERC20V2 callbackAsset = new ReentrantERC20V2();
        MockLPTokenV2 localLP = new MockLPTokenV2("LocalLP", "LLP", 18);
        ExecutionUpshiftVaultMock localProtocol =
            new ExecutionUpshiftVaultMock(address(callbackAsset), address(localLP));
        callbackAdapter = new UpshiftAdapterV2(
            IERC20(address(callbackAsset)), address(this), localProtocol, IERC20(address(localLP))
        );
        callbackRecovery = IStrategyRecoveryV2(address(callbackAdapter));
        localLP.mint(address(callbackAdapter), 1);
        callbackAsset.mint(address(this), 100);
        callbackAsset.approve(address(callbackAdapter), 100);
        callbackAsset.armCallback(address(this), abi.encodeCall(this.reenterRecovery, ()));

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        callbackAdapter.deposit(100, 1);
        assertEq(callbackAsset.balanceOf(address(this)), 100);
        assertEq(localLP.balanceOf(address(callbackAdapter)), 1);
    }

    function testBindingChangeDuringProtocolCallsRollsBack() external {
        asset.mint(address(this), 100);
        asset.approve(address(adapter), 100);
        protocol.setChangeBindingOnDeposit(true);
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        adapter.deposit(100, 1);
        assertEq(asset.balanceOf(address(this)), 100);
        assertEq(lp.balanceOf(address(adapter)), 0);

        protocol.setChangeBindingOnDeposit(false);
        protocol.setReportedAsset(address(asset));
        lp.mint(address(adapter), 100);
        asset.mint(address(protocol), 100);
        protocol.setChangeBindingOnRedeem(true);
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        adapter.redeem(100, 0);
        assertEq(lp.balanceOf(address(adapter)), 100);
    }

    function testIdleAdapterDoesNotExposePositionRecovery() external {
        IdleAdapterV2 idle = new IdleAdapterV2(IERC20(address(asset)), address(this));
        (bool ok,) =
            address(idle).call(abi.encodeCall(IStrategyRecoveryV2.recoverPosition, (receiver)));
        assertFalse(ok);
    }

    function testPlanNamedMaliciousAdapterOverReportsWithoutBalanceDelta() external {
        MaliciousStrategyAdapterV2 malicious =
            new MaliciousStrategyAdapterV2(address(asset), address(lp));
        malicious.setReportedValue(1_000);
        asset.mint(address(this), 10);
        asset.approve(address(malicious), 10);

        uint256 callerBefore = asset.balanceOf(address(this));
        uint256 adapterBefore = asset.balanceOf(address(malicious));
        assertEq(malicious.deposit(1, 0), 1_000);
        assertEq(asset.balanceOf(address(this)), callerBefore);
        assertEq(asset.balanceOf(address(malicious)), adapterBefore);
        assertEq(malicious.totalAssets(), 1_000);
    }
}
