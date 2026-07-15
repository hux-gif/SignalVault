// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {IStrategyRouterV2} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {RiskConfigurationV2} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {InstrumentedStrategyAdapterV2} from "./mocks/InstrumentedStrategyAdapterV2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";
import {FalseReturnERC20V2} from "./mocks/FalseReturnERC20V2.sol";
import {SkimmingERC20V2} from "./mocks/SkimmingERC20V2.sol";

contract OverDebitingWithdrawalERC20V2 is ERC20 {
    constructor() ERC20("Over-debit Token", "OVER") {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function transfer(address receiver, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, receiver, amount);
        _burn(msg.sender, 1);
        return true;
    }
}

contract ReentrantWithdrawalVaultV2 {
    address public immutable vaultOwner;
    address private _target;
    bytes private _data;

    constructor(address owner_) {
        vaultOwner = owner_;
    }

    function arm(address target, bytes calldata data) external {
        _target = target;
        _data = data;
    }

    function reenter() external {
        address target = _target;
        bytes memory data = _data;
        _target = address(0);
        delete _data;
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }
}

contract StrategyRouterV2WithdrawalTest is Test {
    using stdStorage for StdStorage;

    event AssetsWithdrawnToVault(
        uint256 requestedAssets,
        uint256 deliveredAssets,
        uint256 routerDirectUsed,
        uint256 idleAssetsUsed,
        uint256 upshiftDirectUsed,
        uint256 upshiftSharesRedeemed,
        uint256 upshiftAssetsReceived
    );

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    StrategyRouterV2 internal router;
    InstrumentedStrategyAdapterV2 internal idle;
    InstrumentedStrategyAdapterV2 internal upshift;
    RouterBoundVaultMockV2 internal vault;
    address internal owner = address(0xA11CE);

    function setUp() public {
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        router = new StrategyRouterV2(IERC20(address(asset)), owner);
        idle = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(router), address(asset)
        );
        upshift = new InstrumentedStrategyAdapterV2(
            IERC20(address(asset)), address(router), address(lpToken)
        );
        vault = new RouterBoundVaultMockV2(owner);

        vm.startPrank(owner);
        router.configureAdapters(address(upshift), address(idle));
        router.configureRisk(_risk());
        router.bindVault(address(vault));
        vm.stopPrank();
    }

    function testWithdrawalUsesFeeFreeTiersBeforeFinalUpshiftDeficit() external {
        asset.mint(address(router), 10);
        asset.mint(address(idle), 20);
        asset.mint(address(upshift), 5);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRequiredPriorAdapter(address(idle));
        uint256 vaultBefore = asset.balanceOf(address(vault));

        vm.prank(address(vault));
        uint256 delivered = IStrategyRouterV2(address(router)).withdrawToVault(40);

        assertEq(delivered, 40);
        assertEq(asset.balanceOf(address(vault)) - vaultBefore, 40);
        assertEq(idle.lastWithdrawLiquidAssets(), 20);
        assertEq(upshift.lastWithdrawLiquidAssets(), 5);
        assertEq(upshift.lastRedeemShares(), 5);
        assertEq(upshift.redeemCallCount(), 1);
    }

    function testRouterOnlyWithdrawalMakesNoAdapterCall() external {
        asset.mint(address(router), 10);

        assertEq(_withdraw(10), 10);

        assertEq(asset.balanceOf(address(vault)), 10);
        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testIdleOnlyWithdrawalUsesExactDeficit() external {
        asset.mint(address(idle), 20);

        assertEq(_withdraw(12), 12);

        assertEq(idle.lastWithdrawLiquidAssets(), 12);
        assertEq(asset.balanceOf(address(idle)), 8);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testUpshiftDirectOnlyWithdrawalDoesNotRedeemShares() external {
        asset.mint(address(upshift), 7);

        assertEq(_withdraw(7), 7);

        assertEq(upshift.lastWithdrawLiquidAssets(), 7);
        assertEq(upshift.redeemCallCount(), 0);
        assertEq(asset.balanceOf(address(upshift)), 0);
    }

    function testUpshiftRedemptionOverageRemainsRouterDirect() external {
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(5, 6, 6);

        assertEq(_withdraw(5), 5);

        assertEq(upshift.lastRedeemShares(), 5);
        assertEq(asset.balanceOf(address(router)), 1);
        assertEq(asset.balanceOf(address(vault)), 5);
    }

    function testInsufficientAggregateLiquidityRevertsBeforeMutation() external {
        asset.mint(address(router), 10);
        asset.mint(address(idle), 20);
        upshift.setPositionValues(100, 100, 4, 100);

        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouterV2.InsufficientLiquidity.selector, 35, 34)
        );
        _withdraw(35);

        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testPausedWithdrawalSucceedsThroughFeeFreeTiers() external {
        asset.mint(address(router), 10);
        asset.mint(address(idle), 20);
        asset.mint(address(upshift), 7);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setStatus(true, false);

        assertEq(_withdraw(30), 30);

        assertEq(asset.balanceOf(address(vault)), 30);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testPausedWithdrawalRevertsWhenUpshiftIsRequired() external {
        asset.mint(address(router), 10);
        asset.mint(address(idle), 20);
        asset.mint(address(upshift), 7);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setStatus(true, false);

        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouterV2.InsufficientLiquidity.selector, 31, 30)
        );
        _withdraw(31);

        assertEq(idle.stateChangingCallCount(), 0);
        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testZeroProtocolLiquidityRevertsBeforeMutation() external {
        asset.mint(address(upshift), 5);
        upshift.setPositionValues(100, 100, 0, 100);

        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouterV2.InsufficientLiquidity.selector, 6, 5)
        );
        _withdraw(6);

        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testPreviewRevertRollsBackFeeFreeTiers() external {
        asset.mint(address(idle), 20);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setPreviewReverts(true);

        vm.expectRevert(InstrumentedStrategyAdapterV2.PreviewReverted.selector);
        _withdraw(25);

        assertEq(asset.balanceOf(address(idle)), 20);
        assertEq(asset.balanceOf(address(router)), 0);
    }

    function testZeroNetPositionCannotProduceWithdrawalCandidate() external {
        upshift.setPositionValues(0, 0, 100, 100);

        vm.expectRevert();
        _withdraw(1);

        assertEq(upshift.stateChangingCallCount(), 0);
    }

    function testWithdrawalUsesOnlyInitialCandidateAndOneRefinement() external {
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(5, 4, 4);
        upshift.setRedeemPreview(7, 6, 6);
        vm.expectCall(address(upshift), abi.encodeCall(upshift.previewRedeem, (5)), 1);
        vm.expectCall(address(upshift), abi.encodeCall(upshift.previewRedeem, (7)), 1);

        assertEq(_withdraw(5), 5);

        assertEq(upshift.lastRedeemShares(), 7);
        assertEq(asset.balanceOf(address(router)), 1);
    }

    function testSecondNonCoveringCandidateRevertsAtomically() external {
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(5, 4, 4);
        upshift.setRedeemPreview(7, 4, 4);

        vm.expectRevert();
        _withdraw(5);

        assertEq(upshift.redeemCallCount(), 0);
        assertEq(upshift.positionShares(), 100);
    }

    function testPreviewCannotExceedConservativePositionLiquidity() external {
        upshift.setPositionValues(100, 100, 5, 100);
        upshift.setRedeemPreview(5, 6, 6);

        vm.expectRevert();
        _withdraw(5);

        assertEq(upshift.redeemCallCount(), 0);
    }

    function testPreviewDerivedMinimumUsesFrozenDeviation() external {
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(10, 10, 10);

        _withdraw(10);

        assertEq(upshift.lastRedeemMinAssetsOut(), 9);
    }

    function testZeroPreviewDerivedMinimumRevertsBeforeRedemption() external {
        upshift.setPositionValues(1, 1, 1, 1);
        upshift.setRedeemPreview(1, 1, 1);

        vm.expectRevert();
        _withdraw(1);

        assertEq(upshift.redeemCallCount(), 0);
    }

    function testIdleUnderDeliveryRevertsAtomically() external {
        asset.mint(address(idle), 20);
        idle.setWithdrawalExecution(10, 9, 9);

        vm.expectRevert(IStrategyRouterV2.AssetDeltaMismatch.selector);
        _withdraw(10);

        assertEq(asset.balanceOf(address(idle)), 20);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testUpshiftUnderDeliveryRevertsAtomically() external {
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemExecution(10, 9, 9);

        vm.expectRevert();
        _withdraw(10);

        assertEq(upshift.positionShares(), 100);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testVaultUnderReceiptRevertsAtomically() external {
        SkimmingERC20V2 skim = new SkimmingERC20V2();
        (
            StrategyRouterV2 skimRouter,
            InstrumentedStrategyAdapterV2 skimIdle,
            InstrumentedStrategyAdapterV2 skimUpshift,
            RouterBoundVaultMockV2 skimVault
        ) = _deploy(IERC20(address(skim)));
        skim.mint(address(skimRouter), 10);
        skim.setTransferShortfall(address(skimRouter), 1);

        vm.expectRevert(IStrategyRouterV2.AssetDeltaMismatch.selector);
        vm.prank(address(skimVault));
        IStrategyRouterV2(address(skimRouter)).withdrawToVault(10);

        assertEq(skim.balanceOf(address(skimRouter)), 10);
        assertEq(skim.balanceOf(address(skimVault)), 0);
        assertEq(skimIdle.stateChangingCallCount(), 0);
        assertEq(skimUpshift.stateChangingCallCount(), 0);
    }

    function testRouterOverDebitRevertsAtomically() external {
        OverDebitingWithdrawalERC20V2 over = new OverDebitingWithdrawalERC20V2();
        (StrategyRouterV2 overRouter,,, RouterBoundVaultMockV2 overVault) =
            _deploy(IERC20(address(over)));
        over.mint(address(overRouter), 11);

        vm.expectRevert(IStrategyRouterV2.AssetDeltaMismatch.selector);
        vm.prank(address(overVault));
        IStrategyRouterV2(address(overRouter)).withdrawToVault(10);

        assertEq(over.balanceOf(address(overRouter)), 11);
        assertEq(over.balanceOf(address(overVault)), 0);
    }

    function testFalseReturnVaultTransferFailsClosed() external {
        FalseReturnERC20V2 falseToken = new FalseReturnERC20V2();
        (StrategyRouterV2 falseRouter,,, RouterBoundVaultMockV2 falseVault) =
            _deploy(IERC20(address(falseToken)));
        falseToken.mint(address(falseRouter), 10);
        falseToken.setFailureMode(FalseReturnERC20V2.FailureMode.Transfer);

        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken))
        );
        vm.prank(address(falseVault));
        IStrategyRouterV2(address(falseRouter)).withdrawToVault(10);
    }

    function testWithdrawalRejectsNonVaultCaller() external {
        asset.mint(address(router), 10);

        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        IStrategyRouterV2(address(router)).withdrawToVault(10);
    }

    function testWithdrawalRejectsReentrancy() external {
        ReentrantWithdrawalVaultV2 callbackVault = new ReentrantWithdrawalVaultV2(owner);
        (StrategyRouterV2 callbackRouter,, InstrumentedStrategyAdapterV2 callbackUpshift) =
            _deployWithVault(IERC20(address(asset)), address(callbackVault));
        callbackUpshift.setPositionValues(100, 100, 100, 100);
        bytes memory nested = abi.encodeCall(IStrategyRouterV2.withdrawToVault, (10));
        callbackVault.arm(address(callbackRouter), nested);
        callbackUpshift.setRedeemCallback(
            address(callbackVault), abi.encodeCall(callbackVault.reenter, ())
        );

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(callbackVault));
        IStrategyRouterV2(address(callbackRouter)).withdrawToVault(10);
    }

    function testWithdrawalDoesNotChangeCooldown() external {
        asset.mint(address(router), 10);
        stdstore.target(address(router)).sig(router.lastRebalanceTimestamp.selector)
            .checked_write(1234);

        _withdraw(10);

        assertEq(router.lastRebalanceTimestamp(), 1234);
    }

    function testFullCloseDrainsEveryNormalRecoverableAsset() external {
        asset.mint(address(router), 10);
        asset.mint(address(idle), 20);
        asset.mint(address(upshift), 5);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(100, 100, 100);

        uint256 delivered = _withdrawAll();

        assertEq(delivered, 135);
        assertEq(asset.balanceOf(address(vault)), 135);
        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(idle)), 0);
        assertEq(asset.balanceOf(address(upshift)), 0);
        assertEq(upshift.positionShares(), 0);
        assertEq(idle.redeemAllCallCount(), 1);
        assertEq(upshift.redeemAllCallCount(), 1);
        assertEq(upshift.lastRedeemMinAssetsOut(), 99);
    }

    function testFullCloseEventReportsDisjointAssetSources() external {
        asset.mint(address(router), 10);
        asset.mint(address(idle), 20);
        asset.mint(address(upshift), 5);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(100, 100, 100);

        vm.expectEmit(address(router));
        emit AssetsWithdrawnToVault(135, 135, 10, 20, 5, 100, 100);

        assertEq(_withdrawAll(), 135);
    }

    function testFullCloseRejectsNonVaultCaller() external {
        asset.mint(address(router), 10);

        vm.expectRevert(IStrategyRouterV2.OnlyVault.selector);
        IStrategyRouterV2(address(router)).withdrawAllToVault();
    }

    function testFullCloseRejectsReentrancy() external {
        ReentrantWithdrawalVaultV2 callbackVault = new ReentrantWithdrawalVaultV2(owner);
        (StrategyRouterV2 callbackRouter,, InstrumentedStrategyAdapterV2 callbackUpshift) =
            _deployWithVault(IERC20(address(asset)), address(callbackVault));
        callbackUpshift.setPositionValues(100, 100, 100, 100);
        callbackUpshift.setRedeemPreview(100, 100, 100);
        bytes memory nested = abi.encodeCall(IStrategyRouterV2.withdrawAllToVault, ());
        callbackVault.arm(address(callbackRouter), nested);
        callbackUpshift.setRedeemCallback(
            address(callbackVault), abi.encodeCall(callbackVault.reenter, ())
        );

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(callbackVault));
        IStrategyRouterV2(address(callbackRouter)).withdrawAllToVault();
    }

    function testFullCloseRetainsNoRoundingDust() external {
        asset.mint(address(upshift), 1);
        upshift.setPositionValues(101, 101, 101, 100);
        upshift.setRedeemPreview(100, 101, 101);

        assertEq(_withdrawAll(), 102);

        assertEq(asset.balanceOf(address(vault)), 102);
        assertEq(asset.balanceOf(address(router)), 0);
    }

    function testFullCloseSweepsUpshiftDirectWithoutPositionShares() external {
        asset.mint(address(upshift), 7);

        assertEq(_withdrawAll(), 7);

        assertEq(upshift.withdrawLiquidCallCount(), 1);
        assertEq(upshift.redeemAllCallCount(), 0);
        assertEq(asset.balanceOf(address(upshift)), 0);
    }

    function testFullCloseResidualSharesRevertAtomically() external {
        asset.mint(address(upshift), 5);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(100, 100, 100);
        upshift.setRedeemAllExecution(1, 0, 105, 105);

        vm.expectRevert(IStrategyRouterV2.ResidualPosition.selector);
        _withdrawAll();

        assertEq(upshift.positionShares(), 100);
        assertEq(asset.balanceOf(address(upshift)), 5);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testFullCloseResidualUnderlyingRevertsAtomically() external {
        asset.mint(address(upshift), 5);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(100, 100, 100);
        upshift.setRedeemAllExecution(0, 1, 104, 104);

        vm.expectRevert(IStrategyRouterV2.ResidualAssets.selector);
        _withdrawAll();

        assertEq(upshift.positionShares(), 100);
        assertEq(asset.balanceOf(address(upshift)), 5);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testFullCloseRejectsAdapterOverReport() external {
        asset.mint(address(upshift), 5);
        upshift.setPositionValues(100, 100, 100, 100);
        upshift.setRedeemPreview(100, 100, 100);
        upshift.setRedeemAllExecution(0, 0, 105, 106);

        vm.expectRevert(IStrategyRouterV2.AdapterDeltaMismatch.selector);
        _withdrawAll();

        assertEq(upshift.positionShares(), 100);
        assertEq(asset.balanceOf(address(upshift)), 5);
    }

    function testFullCloseWithRouterOnlySkipsZeroAmountAdapters() external {
        asset.mint(address(router), 10);

        assertEq(_withdrawAll(), 10);

        assertEq(idle.redeemAllCallCount(), 0);
        assertEq(upshift.redeemAllCallCount(), 0);
    }

    function testFullCloseDoesNotChangeCooldown() external {
        asset.mint(address(router), 10);
        stdstore.target(address(router)).sig(router.lastRebalanceTimestamp.selector)
            .checked_write(1234);

        _withdrawAll();

        assertEq(router.lastRebalanceTimestamp(), 1234);
    }

    function _withdraw(uint256 assets_) internal returns (uint256 delivered) {
        vm.prank(address(vault));
        return IStrategyRouterV2(address(router)).withdrawToVault(assets_);
    }

    function _withdrawAll() internal returns (uint256 delivered) {
        vm.prank(address(vault));
        return IStrategyRouterV2(address(router)).withdrawAllToVault();
    }

    function _deploy(IERC20 token)
        internal
        returns (
            StrategyRouterV2 deployedRouter,
            InstrumentedStrategyAdapterV2 deployedIdle,
            InstrumentedStrategyAdapterV2 deployedUpshift,
            RouterBoundVaultMockV2 deployedVault
        )
    {
        deployedVault = new RouterBoundVaultMockV2(owner);
        (deployedRouter, deployedIdle, deployedUpshift) =
            _deployWithVault(token, address(deployedVault));
    }

    function _deployWithVault(IERC20 token, address vault_)
        internal
        returns (
            StrategyRouterV2 deployedRouter,
            InstrumentedStrategyAdapterV2 deployedIdle,
            InstrumentedStrategyAdapterV2 deployedUpshift
        )
    {
        deployedRouter = new StrategyRouterV2(token, owner);
        deployedIdle =
            new InstrumentedStrategyAdapterV2(token, address(deployedRouter), address(token));
        deployedUpshift =
            new InstrumentedStrategyAdapterV2(token, address(deployedRouter), address(lpToken));
        vm.startPrank(owner);
        deployedRouter.configureAdapters(address(deployedUpshift), address(deployedIdle));
        deployedRouter.configureRisk(_risk());
        deployedRouter.bindVault(vault_);
        vm.stopPrank();
    }

    function _risk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 1 hours,
            minimumAllocationChangeBps: 100,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }
}
