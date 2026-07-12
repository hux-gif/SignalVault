// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {FeeAwareUpshiftVaultMock} from "./mocks/FeeAwareUpshiftVaultMock.sol";
import {FalseReturnERC20V2} from "./mocks/FalseReturnERC20V2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {ObservableCallbackReceiverV2} from "./mocks/ObservableCallbackReceiverV2.sol";
import {IUpshiftVaultV2} from "../../src/v2/interfaces/IUpshiftVaultV2.sol";

contract UpshiftProtocolMockV2Test is Test {
    MockLPTokenV2 internal lp;
    FeeAwareUpshiftVaultMock internal protocol;
    MockLPTokenV2 internal asset;

    function setUp() public {
        asset = new MockLPTokenV2("MockFXRP", "MFXRP", 6);
        lp = new MockLPTokenV2("UpshiftLP", "ULP", 6);
        protocol = new FeeAwareUpshiftVaultMock(address(asset), address(lp));
    }

    function testMockAppliesDynamicFeeAndNoReturnInstantRedeem() external {
        protocol.setInstantFee(50);
        (uint256 shares,) = protocol.previewDeposit(address(asset), 10_000);
        (uint256 gross, uint256 net) = protocol.previewRedemption(shares, true);
        assertEq(net, gross - Math.mulDiv(gross, 50, 10_000));
        protocol.setInstantFee(100);
        (, uint256 changedNet) = protocol.previewRedemption(shares, true);
        assertLt(changedNet, net);
    }

    function testInstantRedeemHasNoReturnValue() external {
        protocol.setInstantFee(50);
        (uint256 shares,) = protocol.previewDeposit(address(asset), 10_000);
        asset.mint(address(protocol), 10_000);
        lp.mint(address(this), shares);
        uint256 before = asset.balanceOf(address(this));
        protocol.instantRedeem(shares, address(this));
        assertGt(asset.balanceOf(address(this)), before);
    }

    function testFeeTable() external {
        uint256[5] memory fees = [uint256(0), 25, 50, 100, 1_000];
        for (uint256 i = 0; i < fees.length; i++) {
            protocol.setInstantFee(fees[i]);
            (uint256 shares,) = protocol.previewDeposit(address(asset), 10_000);
            (uint256 gross, uint256 net) = protocol.previewRedemption(shares, true);
            assertEq(net, gross - Math.mulDiv(gross, fees[i], 10_000));
        }
    }

    function testFeeBoundsIncludeFullFeeAndRejectAboveTenThousand() external {
        protocol.setInstantFee(0);
        protocol.setInstantFee(50);
        protocol.setInstantFee(10_000);
        (, uint256 net) = protocol.previewRedemption(10_000, true);
        assertEq(net, 0);

        vm.expectRevert();
        protocol.setInstantFee(10_001);
    }

    function testPauseBlocksWithdrawals() external {
        protocol.setPaused(true);
        assertTrue(protocol.withdrawalsPaused());
        assertEq(protocol.maxWithdrawalAmount(), 0);
    }

    function testPreviewCallCounters() external {
        // Preview functions are view (matching live ABI); call counts are
        // asserted via vm.expectCall instead of storage counters.
        bytes memory depositData =
            abi.encodeCall(IUpshiftVaultV2.previewDeposit, (address(asset), 10_000));
        vm.expectCall(address(protocol), depositData, 2);
        protocol.previewDeposit(address(asset), 10_000);
        (uint256 shares,) = protocol.previewDeposit(address(asset), 10_000);

        bytes memory redeemData = abi.encodeCall(IUpshiftVaultV2.previewRedemption, (shares, true));
        vm.expectCall(address(protocol), redeemData, 1);
        protocol.previewRedemption(shares, true);
    }

    function testSetPreviewInconsistency() external {
        protocol.setPreviewInconsistent(true);
        (uint256 shares1,) = protocol.previewDeposit(address(asset), 10_000);
        // Advance time so the block.timestamp nonce diverges (view preview).
        vm.warp(block.timestamp + 1);
        (uint256 shares2,) = protocol.previewDeposit(address(asset), 10_000);
        assertNotEq(shares1, shares2);
    }

    function testUnderTransferOnInstantRedeem() external {
        protocol.setInstantFee(0);
        protocol.setUnderTransferAmount(5_000);
        (uint256 shares,) = protocol.previewDeposit(address(asset), 10_000);
        asset.mint(address(protocol), 5_000);
        lp.mint(address(this), shares);
        uint256 before = asset.balanceOf(address(this));
        protocol.instantRedeem(shares, address(this));
        assertEq(asset.balanceOf(address(this)) - before, 5_000);
    }

    function testInstantRedeemMatchesPreviewAndBurnsExactShares() external {
        protocol.setInstantFee(0);
        (uint256 shares,) = protocol.previewDeposit(address(asset), 10_000);
        asset.mint(address(protocol), 10_000);
        lp.mint(address(this), shares);
        (, uint256 expectedNet) = protocol.previewRedemption(shares, true);
        uint256 receiverAssetsBefore = asset.balanceOf(address(this));
        uint256 protocolAssetsBefore = asset.balanceOf(address(protocol));
        uint256 callerLPBefore = lp.balanceOf(address(this));

        protocol.instantRedeem(shares, address(this));

        assertEq(asset.balanceOf(address(this)) - receiverAssetsBefore, expectedNet);
        assertEq(protocolAssetsBefore - asset.balanceOf(address(protocol)), expectedNet);
        assertEq(callerLPBefore - lp.balanceOf(address(this)), shares);
        assertEq(lp.allowance(address(this), address(protocol)), 0);
    }

    function testSuccessfulCallbackIsObservable() external {
        ObservableCallbackReceiverV2 receiver = new ObservableCallbackReceiverV2();
        asset.mint(address(protocol), 10_000);
        lp.mint(address(this), 10_000);
        protocol.armReentry(
            address(receiver), abi.encodeCall(ObservableCallbackReceiverV2.recordCallback, ())
        );

        protocol.instantRedeem(10_000, address(this));

        assertEq(receiver.callbackCount(), 1);
        (bool countOk, bytes memory countData) =
            address(protocol).staticcall(abi.encodeWithSignature("reentryAttemptCount()"));
        (bool successOk, bytes memory successData) =
            address(protocol).staticcall(abi.encodeWithSignature("lastReentrySucceeded()"));
        assertTrue(countOk);
        assertTrue(successOk);
        assertEq(abi.decode(countData, (uint256)), 1);
        assertTrue(abi.decode(successData, (bool)));
    }

    function testCallbackFailureIsObservableAndSwallowed() external {
        ObservableCallbackReceiverV2 receiver = new ObservableCallbackReceiverV2();
        asset.mint(address(protocol), 10_000);
        lp.mint(address(this), 10_000);
        protocol.armReentry(
            address(receiver), abi.encodeCall(ObservableCallbackReceiverV2.revertCallback, ())
        );

        protocol.instantRedeem(10_000, address(this));

        (bool countOk, bytes memory countData) =
            address(protocol).staticcall(abi.encodeWithSignature("reentryAttemptCount()"));
        (bool successOk, bytes memory successData) =
            address(protocol).staticcall(abi.encodeWithSignature("lastReentrySucceeded()"));
        assertTrue(countOk);
        assertTrue(successOk);
        assertEq(abi.decode(countData, (uint256)), 1);
        assertFalse(abi.decode(successData, (bool)));
    }

    function testFalseReturnTransferFromRevertsWithoutMintingShares() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        MockLPTokenV2 localLP = new MockLPTokenV2("LocalLP", "LLP", 6);
        FeeAwareUpshiftVaultMock localProtocol =
            new FeeAwareUpshiftVaultMock(address(falseAsset), address(localLP));
        falseAsset.mint(address(this), 10_000);
        falseAsset.approve(address(localProtocol), 10_000);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.TransferFrom);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseAsset))
        );
        localProtocol.deposit(address(falseAsset), 10_000, address(this));

        assertEq(localLP.balanceOf(address(this)), 0);
        assertEq(falseAsset.balanceOf(address(localProtocol)), 0);
    }

    function testFalseReturnTransferRevertsAndRollsBackShareBurn() external {
        FalseReturnERC20V2 falseAsset = new FalseReturnERC20V2();
        MockLPTokenV2 localLP = new MockLPTokenV2("LocalLP", "LLP", 6);
        FeeAwareUpshiftVaultMock localProtocol =
            new FeeAwareUpshiftVaultMock(address(falseAsset), address(localLP));
        falseAsset.mint(address(localProtocol), 10_000);
        localLP.mint(address(this), 10_000);
        falseAsset.setFailureMode(FalseReturnERC20V2.FailureMode.Transfer);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseAsset))
        );
        localProtocol.instantRedeem(10_000, address(this));

        assertEq(localLP.balanceOf(address(this)), 10_000);
        assertEq(falseAsset.balanceOf(address(localProtocol)), 10_000);
    }

    function testAssetAndLPTokenBindings() external view {
        assertEq(protocol.asset(), address(asset));
        assertEq(protocol.lpTokenAddress(), address(lp));
    }

    function testSetMaxWithdrawalReferenceAmount() external {
        protocol.setMaxWithdrawalReferenceAmount(5_000);
        assertFalse(protocol.withdrawalsPaused());
        assertEq(protocol.maxWithdrawalAmount(), 5_000);
    }
}
