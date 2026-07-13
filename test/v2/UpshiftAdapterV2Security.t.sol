// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {IStrategyRecoveryV2} from "../../src/v2/interfaces/IStrategyRecoveryV2.sol";
import {ExecutionUpshiftVaultMock} from "./mocks/ExecutionUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";

contract UpshiftAdapterV2SecurityTest is Test {
    bytes4 internal constant ONLY_ROUTER = bytes4(keccak256("OnlyRouter()"));
    bytes4 internal constant ZERO_ADDRESS = bytes4(keccak256("ZeroAddress()"));
    bytes4 internal constant ZERO_POSITION = bytes4(keccak256("ZeroPosition()"));
    bytes4 internal constant POSITION_RECOVERED = bytes4(keccak256("PositionRecovered()"));

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
        protocol = new ExecutionUpshiftVaultMock(address(asset), address(lp));
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
    }
}
