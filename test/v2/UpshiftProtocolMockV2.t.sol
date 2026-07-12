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

interface IFeeAwareUpshiftVaultMockConfiguration {
    function setReportedAsset(address reportedAsset) external;
    function setReportedLPToken(address reportedLPToken) external;
    function setDepositRates(
        uint256 shareNumerator,
        uint256 shareDenominator,
        uint256 referenceNumerator,
        uint256 referenceDenominator
    ) external;
    function setDepositPreviewOverride(
        uint256 amountIn,
        bool enabled,
        uint256 shares,
        uint256 referenceAmount
    ) external;
    function setRedemptionPreviewOverride(
        uint256 shares,
        bool enabled,
        uint256 gross,
        uint256 net,
        uint256 internalReference
    ) external;
    function setWithdrawalLimitMode(uint8 mode) external;
}

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

        lp.mint(address(this), 1);
        vm.expectRevert();
        protocol.instantRedeem(1, address(this));
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
        protocol.setInstantFee(50);
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

    function testDepositReferencePreviewDoesNotApplyRedemptionFee() external {
        protocol.setInstantFee(5_000);

        (uint256 shares, uint256 referenceAmount) = protocol.previewDeposit(address(asset), 10_000);

        assertEq(shares, 10_000);
        assertEq(referenceAmount, 10_000);
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

    function testReportedBindingsCanChangeWithoutChangingExecutionBindings() external {
        IFeeAwareUpshiftVaultMockConfiguration configuration =
            IFeeAwareUpshiftVaultMockConfiguration(address(protocol));
        address reportedAsset = makeAddr("reportedAsset");
        address reportedLPToken = makeAddr("reportedLPToken");
        configuration.setReportedAsset(reportedAsset);
        configuration.setReportedLPToken(reportedLPToken);

        assertEq(protocol.asset(), reportedAsset);
        assertEq(protocol.lpTokenAddress(), reportedLPToken);

        asset.mint(address(this), 10_000);
        asset.approve(address(protocol), 10_000);
        uint256 shares = protocol.deposit(address(asset), 10_000, address(this));
        assertEq(shares, 10_000);
        assertEq(lp.balanceOf(address(this)), 10_000);
        assertEq(asset.balanceOf(address(protocol)), 10_000);
    }

    function testDepositRatesUseFloorRoundingForPreviewAndExecution() external {
        IFeeAwareUpshiftVaultMockConfiguration(address(protocol)).setDepositRates(3, 2, 5, 4);

        (uint256 shares, uint256 referenceAmount) = protocol.previewDeposit(address(asset), 3);
        assertEq(shares, 4);
        assertEq(referenceAmount, 3);

        asset.mint(address(this), 3);
        asset.approve(address(protocol), 3);
        uint256 ownerAssetsBefore = asset.balanceOf(address(this));
        uint256 actualShares = protocol.deposit(address(asset), 3, address(this));
        assertEq(actualShares, 4);
        assertEq(lp.balanceOf(address(this)), 4);
        assertEq(ownerAssetsBefore - asset.balanceOf(address(this)), 3);
        assertEq(asset.balanceOf(address(protocol)), 3);
        assertEq(asset.allowance(address(this), address(protocol)), 0);
    }

    function testDepositRatesRejectZeroDenominators() external {
        IFeeAwareUpshiftVaultMockConfiguration configuration =
            IFeeAwareUpshiftVaultMockConfiguration(address(protocol));
        vm.expectRevert();
        configuration.setDepositRates(1, 0, 1, 1);
        vm.expectRevert();
        configuration.setDepositRates(1, 1, 1, 0);
    }

    function testDepositPreviewOverridesAreDeterministicPerInput() external {
        IFeeAwareUpshiftVaultMockConfiguration configuration =
            IFeeAwareUpshiftVaultMockConfiguration(address(protocol));
        configuration.setDepositPreviewOverride(10, true, 0, 0);
        configuration.setDepositPreviewOverride(11, true, 77, 3);

        (uint256 firstShares, uint256 firstReference) = protocol.previewDeposit(address(asset), 10);
        (uint256 repeatedShares, uint256 repeatedReference) =
            protocol.previewDeposit(address(asset), 10);
        (uint256 otherShares, uint256 otherReference) = protocol.previewDeposit(address(asset), 11);

        assertEq(firstShares, 0);
        assertEq(firstReference, 0);
        assertEq(repeatedShares, firstShares);
        assertEq(repeatedReference, firstReference);
        assertEq(otherShares, 77);
        assertEq(otherReference, 3);
    }

    function testDepositExecutionUsesRateRatherThanPreviewOverride() external {
        IFeeAwareUpshiftVaultMockConfiguration configuration =
            IFeeAwareUpshiftVaultMockConfiguration(address(protocol));
        configuration.setDepositRates(2, 1, 1, 1);
        configuration.setDepositPreviewOverride(100, true, 999, 777);
        asset.mint(address(this), 100);
        asset.approve(address(protocol), 100);

        uint256 actualShares = protocol.deposit(address(asset), 100, address(this));

        assertEq(actualShares, 200);
        assertEq(lp.balanceOf(address(this)), 200);
    }

    function testRedemptionPreviewOverridesSupportContradictoryCandidates() external {
        IFeeAwareUpshiftVaultMockConfiguration configuration =
            IFeeAwareUpshiftVaultMockConfiguration(address(protocol));
        configuration.setRedemptionPreviewOverride(10, true, 0, 0, 0);
        configuration.setRedemptionPreviewOverride(11, true, 5, 6, 4);
        configuration.setRedemptionPreviewOverride(12, true, 9, 8, 7);

        (uint256 zeroGross, uint256 zeroNet) = protocol.previewRedemption(10, true);
        (uint256 contradictoryGross, uint256 contradictoryNet) =
            protocol.previewRedemption(11, true);
        (uint256 stableGross, uint256 stableNet) = protocol.previewRedemption(12, true);

        assertEq(zeroGross, 0);
        assertEq(zeroNet, 0);
        assertEq(contradictoryGross, 5);
        assertEq(contradictoryNet, 6);
        assertEq(stableGross, 9);
        assertEq(stableNet, 8);
    }

    function testWithdrawalLimitModesEnforceEqualityAndRejectOneAbove() external {
        _assertWithdrawalLimitMode(0, 80, 70, 60, 80, 81, 70, 60);
        _assertWithdrawalLimitMode(1, 80, 70, 60, 70, 80, 71, 60);
        _assertWithdrawalLimitMode(2, 80, 70, 60, 60, 80, 70, 61);
    }

    function testSelectorPrefixCountsVariedRedemptionPreviewCalls() external {
        vm.expectCall(
            address(protocol), abi.encodePacked(IUpshiftVaultV2.previewRedemption.selector), 3
        );
        protocol.previewRedemption(1, true);
        protocol.previewRedemption(2, true);
        protocol.previewRedemption(3, false);
    }

    function _assertWithdrawalLimitMode(
        uint8 mode,
        uint256 equalityGross,
        uint256 equalityNet,
        uint256 equalityInternalReference,
        uint256 limit,
        uint256 aboveGross,
        uint256 aboveNet,
        uint256 aboveInternalReference
    ) internal {
        IFeeAwareUpshiftVaultMockConfiguration configuration =
            IFeeAwareUpshiftVaultMockConfiguration(address(protocol));
        configuration.setWithdrawalLimitMode(mode);
        protocol.setMaxWithdrawalReferenceAmount(limit);
        configuration.setRedemptionPreviewOverride(
            100, true, equalityGross, equalityNet, equalityInternalReference
        );
        asset.mint(address(protocol), equalityNet);
        lp.mint(address(this), 100);
        protocol.instantRedeem(100, address(this));

        configuration.setRedemptionPreviewOverride(
            101, true, aboveGross, aboveNet, aboveInternalReference
        );
        asset.mint(address(protocol), aboveNet);
        uint256 lpBalanceBefore = lp.balanceOf(address(this));
        lp.mint(address(this), 101);
        vm.expectRevert();
        protocol.instantRedeem(101, address(this));
        assertEq(lp.balanceOf(address(this)), lpBalanceBefore + 101);
    }
}
