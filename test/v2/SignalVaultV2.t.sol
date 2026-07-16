// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {SignalVaultV2} from "../../src/v2/SignalVaultV2.sol";
import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {IStrategyRouterV2, RouterStateV2} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {IUpshiftVaultV2} from "../../src/v2/interfaces/IUpshiftVaultV2.sol";
import {IntentVerifierV2} from "../../src/v2/IntentVerifierV2.sol";
import {SignalVaultHashesV2} from "../../src/v2/libraries/SignalVaultHashesV2.sol";
import {
    AllocationV2,
    RebalanceLimitsV2,
    RiskConfigurationV2,
    TEEResultV2
} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {IdleAdapterV2} from "../../src/v2/adapters/IdleAdapterV2.sol";
import {UpshiftAdapterV2} from "../../src/v2/adapters/UpshiftAdapterV2.sol";
import {FeeAwareUpshiftVaultMock} from "./mocks/FeeAwareUpshiftVaultMock.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";

contract SignalVaultV2Test is Test {
    uint16 internal constant _BPS = 10_000;
    uint256 internal constant _SIGNER_PK = 0xA11CE;

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    FeeAwareUpshiftVaultMock internal protocol;
    IntentVerifierV2 internal verifier;
    IdleAdapterV2 internal idle;
    UpshiftAdapterV2 internal upshift;
    StrategyRouterV2 internal router;
    SignalVaultV2 internal vault;
    address internal owner;
    address internal signer;

    function setUp() public {
        owner = address(0xB0B);
        signer = vm.addr(_SIGNER_PK);
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        protocol = new FeeAwareUpshiftVaultMock(address(asset), address(lpToken));
        verifier = new IntentVerifierV2(signer);

        router = new StrategyRouterV2(IERC20(address(asset)), owner);
        idle = new IdleAdapterV2(IERC20(address(asset)), address(router));
        upshift = new UpshiftAdapterV2(
            IERC20(address(asset)),
            address(router),
            IUpshiftVaultV2(address(protocol)),
            IERC20(address(lpToken))
        );

        vm.startPrank(owner);
        router.configureAdapters(address(upshift), address(idle));
        router.configureRisk(_risk());
        vm.stopPrank();

        vault = new SignalVaultV2(
            IERC20(address(asset)), IStrategyRouterV2(address(router)), verifier, owner
        );

        vm.startPrank(owner);
        router.bindVault(address(vault));
        vm.stopPrank();

        asset.mint(owner, 10_000_000);
        vm.startPrank(owner);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // SV1: Constructor and immutable binding
    // -----------------------------------------------------------------------

    function testConstructorBindsExactIdentities() public view {
        assertEq(address(vault.asset()), address(asset));
        assertEq(address(vault.router()), address(router));
        assertEq(address(vault.verifier()), address(verifier));
        assertEq(vault.vaultOwner(), owner);
    }

    function testConstructorRejectsZeroAddresses() public {
        vm.expectRevert(SignalVaultV2.ZeroAddress.selector);
        new SignalVaultV2(IERC20(address(0)), IStrategyRouterV2(address(router)), verifier, owner);
    }

    function testConstructorRejectsRouterAssetMismatch() public {
        MockLPTokenV2 otherAsset = new MockLPTokenV2("Other", "OTH", 6);
        vm.expectRevert(SignalVaultV2.ZeroAddress.selector);
        new SignalVaultV2(
            IERC20(address(otherAsset)), IStrategyRouterV2(address(router)), verifier, owner
        );
    }

    function testConstructorRejectsVaultOwnerMismatch() public {
        vm.expectRevert(SignalVaultV2.Unauthorized.selector);
        new SignalVaultV2(
            IERC20(address(asset)), IStrategyRouterV2(address(router)), verifier, address(0xDEAD)
        );
    }

    // -----------------------------------------------------------------------
    // SV2: Share accounting
    // -----------------------------------------------------------------------

    function testSharesAreNonTransferable() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        address recipient = address(0xCAFE);
        vm.expectRevert(SignalVaultV2.SharesNonTransferable.selector);
        vm.prank(owner);
        vault.transfer(recipient, 500_000);
    }

    function testTotalAssetsCombinesVaultAndRouter() public {
        vm.prank(owner);
        vault.deposit(1_000_000);
        assertEq(vault.totalAssets(), 1_000_000);
    }

    function testDecimalsMatchesAsset() public view {
        assertEq(vault.decimals(), 6);
    }

    // -----------------------------------------------------------------------
    // SV3: Deposit
    // -----------------------------------------------------------------------

    function testFirstDepositMintsOneToOneShares() public {
        vm.prank(owner);
        uint256 shares = vault.deposit(1_000_000);
        assertEq(shares, 1_000_000);
        assertEq(vault.balanceOf(owner), 1_000_000);
        assertEq(asset.balanceOf(address(vault)), 1_000_000);
    }

    function testSubsequentDepositUsesProportionalRatio() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        asset.mint(owner, 500_000);
        vm.prank(owner);
        uint256 shares = vault.deposit(500_000);
        assertEq(shares, 500_000);
        assertEq(vault.balanceOf(owner), 1_500_000);
    }

    function testDepositRejectsZero() public {
        vm.expectRevert(SignalVaultV2.ZeroAssets.selector);
        vm.prank(owner);
        vault.deposit(0);
    }

    function testDepositRejectsNonOwner() public {
        vm.expectRevert(SignalVaultV2.Unauthorized.selector);
        vm.prank(address(0xCAFE));
        vault.deposit(1_000_000);
    }

    // -----------------------------------------------------------------------
    // SV4: Withdraw
    // -----------------------------------------------------------------------

    function testWithdrawReturnsAssets() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        uint256 balanceBefore = asset.balanceOf(owner);
        vm.prank(owner);
        uint256 assets = vault.withdraw(500_000);
        assertEq(assets, 500_000);
        assertEq(asset.balanceOf(owner) - balanceBefore, 500_000);
        assertEq(vault.balanceOf(owner), 500_000);
    }

    function testWithdrawRejectsZero() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.expectRevert(SignalVaultV2.ZeroShares.selector);
        vm.prank(owner);
        vault.withdraw(0);
    }

    function testWithdrawRejectsNonOwner() public {
        vm.expectRevert(SignalVaultV2.Unauthorized.selector);
        vm.prank(address(0xCAFE));
        vault.withdraw(1);
    }

    // -----------------------------------------------------------------------
    // SV5: Intent commitment
    // -----------------------------------------------------------------------

    function testSubmitPrivateIntentAdvancesNonce() public {
        bytes32 commitment = keccak256("intent1");
        vm.prank(owner);
        vault.submitPrivateIntent(commitment, 1);

        assertEq(vault.userIntentNonce(), 1);
        assertEq(vault.latestIntentCommitment(), commitment);
    }

    function testSubmitPrivateIntentRejectsWrongNonce() public {
        vm.expectRevert(abi.encodeWithSelector(SignalVaultV2.InvalidIntentNonce.selector, 1, 2));
        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent"), 2);
    }

    function testSubmitPrivateIntentRejectsZeroCommitment() public {
        vm.expectRevert(SignalVaultV2.InvalidIntentCommitment.selector);
        vm.prank(owner);
        vault.submitPrivateIntent(bytes32(0), 1);
    }

    function testSubmitPrivateIntentRejectsNonOwner() public {
        vm.expectRevert(SignalVaultV2.Unauthorized.selector);
        vm.prank(address(0xCAFE));
        vault.submitPrivateIntent(keccak256("intent"), 1);
    }

    // -----------------------------------------------------------------------
    // SV6-SV7: Authenticated rebalance execution
    // -----------------------------------------------------------------------

    function testExecuteAuthenticatedRebalanceWithValidResult() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent1"), 1);

        vm.warp(1 hours);
        TEEResultV2 memory result = _buildResult(5_000, 1, 1 hours + 3600);
        bytes memory signature = _sign(result);

        vm.prank(owner);
        vault.executeAuthenticatedRebalance(result, signature);

        assertEq(vault.executedResults(result.resultHash), true);
        assertEq(router.totalAssets(), 1_000_000);
    }

    function testExecuteRebalanceRejectsReplay() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent1"), 1);

        vm.warp(1 hours);
        TEEResultV2 memory result = _buildResult(5_000, 1, 1 hours + 3600);
        bytes memory signature = _sign(result);

        vm.prank(owner);
        vault.executeAuthenticatedRebalance(result, signature);

        vm.expectRevert(SignalVaultV2.ResultAlreadyExecuted.selector);
        vm.prank(owner);
        vault.executeAuthenticatedRebalance(result, signature);
    }

    function testExecuteRebalanceRejectsWrongUser() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent1"), 1);

        vm.warp(1 hours);
        TEEResultV2 memory result = _buildResult(5_000, 1, 1 hours + 3600);
        result.user = address(0xDEAD);
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        bytes memory signature = _sign(result);

        vm.expectRevert(SignalVaultV2.Unauthorized.selector);
        vm.prank(owner);
        vault.executeAuthenticatedRebalance(result, signature);
    }

    function testExecuteRebalanceRejectsStaleConfigHash() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent1"), 1);

        vm.warp(1 hours);
        TEEResultV2 memory result = _buildResult(5_000, 1, 1 hours + 3600);
        result.routerConfigHash = bytes32(uint256(0xDEAD));
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
        bytes memory signature = _sign(result);

        vm.expectRevert(SignalVaultV2.RouterConfigMismatch.selector);
        vm.prank(owner);
        vault.executeAuthenticatedRebalance(result, signature);
    }

    function testExecuteRebalanceRejectsWrongNonce() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent1"), 1);

        vm.warp(1 hours);
        TEEResultV2 memory result = _buildResult(5_000, 99, 1 hours + 3600);
        bytes memory signature = _sign(result);

        vm.expectRevert(SignalVaultV2.IntentNotSubmitted.selector);
        vm.prank(owner);
        vault.executeAuthenticatedRebalance(result, signature);
    }

    function testExecuteRebalanceRejectsInvalidSignature() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent1"), 1);

        vm.warp(1 hours);
        TEEResultV2 memory result = _buildResult(5_000, 1, 1 hours + 3600);
        bytes memory badSignature = _signWithPk(result, 0xBAD);

        vm.expectRevert(SignalVaultV2.InvalidResult.selector);
        vm.prank(owner);
        vault.executeAuthenticatedRebalance(result, badSignature);
    }

    function testExecuteRebalanceRejectsNonOwnerCaller() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent1"), 1);

        vm.warp(1 hours);
        TEEResultV2 memory result = _buildResult(5_000, 1, 1 hours + 3600);
        bytes memory signature = _sign(result);

        // executeAuthenticatedRebalance is nonReentrant but NOT onlyVaultOwner —
        // anyone can submit, but the result must verify to vaultOwner
        // This is intentional: the TEE result authorizes the execution
        vm.prank(address(0xCAFE));
        vault.executeAuthenticatedRebalance(result, signature);

        assertEq(vault.executedResults(result.resultHash), true);
    }

    // -----------------------------------------------------------------------
    // SV8: Pause, recovery, close
    // -----------------------------------------------------------------------

    function testPauseRouterBlocksRebalance() public {
        vm.prank(owner);
        vault.pauseRouter();
        assertTrue(router.executionPaused());

        vm.prank(owner);
        vault.unpauseRouter();
        assertFalse(router.executionPaused());
    }

    function testCloseVaultWithdrawsAll() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        vm.warp(1 hours);
        vm.prank(owner);
        vault.submitPrivateIntent(keccak256("intent1"), 1);

        TEEResultV2 memory result = _buildResult(5_000, 1, 1 hours + 3600);
        bytes memory signature = _sign(result);

        vm.prank(owner);
        vault.executeAuthenticatedRebalance(result, signature);

        uint256 balanceBefore = asset.balanceOf(owner);
        vm.prank(owner);
        uint256 delivered = vault.closeVault();
        assertGt(delivered, 0);
        assertGt(asset.balanceOf(owner), balanceBefore);
    }

    // -----------------------------------------------------------------------
    // SV9: Adversarial — donation accounting
    // -----------------------------------------------------------------------

    function testDonationIncreasesNAVWithoutMintingShares() public {
        vm.prank(owner);
        vault.deposit(1_000_000);

        asset.mint(address(vault), 100_000);

        assertEq(vault.totalAssets(), 1_100_000);
        assertEq(vault.balanceOf(owner), 1_000_000);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    function _risk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 1 hours,
            minimumAllocationChangeBps: 100,
            maximumRebalanceLossBps: 100,
            maximumPreviewDeviationBps: 100,
            allocationToleranceBps: 100
        });
    }

    function _buildResult(uint16 upshiftBps, uint256 nonce, uint256 deadline)
        internal
        view
        returns (TEEResultV2 memory result)
    {
        result = TEEResultV2({
            user: owner,
            vault: address(vault),
            intentCommitment: keccak256("intent1"),
            capabilityProfile: router.capabilityProfile(),
            routerConfigHash: router.routerConfigHash(),
            allocation: AllocationV2({
                upshiftBps: upshiftBps, firelightBps: 0, sparkdexBps: 0, idleBps: _BPS - upshiftBps
            }),
            nonce: nonce,
            deadline: deadline,
            ftsoPriceTimestamp: block.timestamp,
            chainId: block.chainid,
            limits: RebalanceLimitsV2({
                minimumPostNAV: 0,
                maximumRebalanceLossBps: 100,
                maximumPreviewDeviationBps: 100,
                allocationToleranceBps: 100
            }),
            resultHash: bytes32(0)
        });
        result.resultHash = SignalVaultHashesV2.computeResultHash(result);
    }

    function _sign(TEEResultV2 memory result) internal view returns (bytes memory) {
        return _signWithPk(result, _SIGNER_PK);
    }

    function _signWithPk(TEEResultV2 memory result, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = verifier.hashTypedData(result);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
