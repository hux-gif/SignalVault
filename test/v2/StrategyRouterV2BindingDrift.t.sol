// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {IdleAdapterV2} from "../../src/v2/adapters/IdleAdapterV2.sol";
import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {RouterStateV2} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {RiskConfigurationV2} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {FeeAwareUpshiftVaultMock} from "./mocks/FeeAwareUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";

contract StrategyRouterV2BindingDriftTest is Test {
    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    FeeAwareUpshiftVaultMock internal protocol;
    StrategyRouterV2 internal router;
    IdleAdapterV2 internal idle;
    UpshiftAdapterV2 internal upshift;

    address internal owner = address(0xA11CE);
    function setUp() public {
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        protocol = new FeeAwareUpshiftVaultMock(address(asset), address(lpToken));
        router = new StrategyRouterV2(IERC20(address(asset)), owner);
        idle = new IdleAdapterV2(IERC20(address(asset)), address(router));
        upshift = new UpshiftAdapterV2(
            IERC20(address(asset)), address(router), protocol, IERC20(address(lpToken))
        );

        vm.startPrank(owner);
        router.configureAdapters(address(upshift), address(idle));
        router.configureRisk(_validRisk());
        router.bindVault(address(new RouterBoundVaultMockV2(owner)));
        vm.stopPrank();

        asset.mint(address(upshift), 7);
    }

    function testAssetBindingDriftExcludesUnwithdrawableDirectUnderlyingFromLiquidity() external {
        protocol.setReportedAsset(address(0xDEAD));

        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftUnavailable));
        assertEq(router.availableLiquidity(), 0);
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        router.totalAssets();
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        router.grossAssets();

        vm.prank(address(router));
        vm.expectRevert(UpshiftAdapterV2.AssetBindingMismatch.selector);
        upshift.withdrawLiquid(7);
        assertEq(asset.balanceOf(address(upshift)), 7);
        assertEq(asset.balanceOf(address(router)), 0);
    }

    function testLPBindingDriftExcludesUnwithdrawableDirectUnderlyingFromLiquidity() external {
        protocol.setReportedLPToken(address(0xDEAD));

        assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftUnavailable));
        assertEq(router.availableLiquidity(), 0);
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        router.totalAssets();
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        router.grossAssets();

        vm.prank(address(router));
        vm.expectRevert(UpshiftAdapterV2.LPBindingMismatch.selector);
        upshift.withdrawLiquid(7);
        assertEq(asset.balanceOf(address(upshift)), 7);
        assertEq(asset.balanceOf(address(router)), 0);
    }

    function _validRisk() private pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 0,
            minimumAllocationChangeBps: 100,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }
}
