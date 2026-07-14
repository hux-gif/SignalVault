// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StrategyRouterV2} from "../../src/v2/StrategyRouterV2.sol";
import {IStrategyRouterV2} from "../../src/v2/interfaces/IStrategyRouterV2.sol";
import {RiskConfigurationV2} from "../../src/v2/types/SignalVaultTypesV2.sol";
import {SignalVaultHashesV2} from "../../src/v2/libraries/SignalVaultHashesV2.sol";
import {MockLPTokenV2} from "./mocks/MockLPTokenV2.sol";
import {RouterBindingAdapterMockV2} from "./mocks/RouterBindingAdapterMockV2.sol";
import {RouterBoundVaultMockV2} from "./mocks/RouterBoundVaultMockV2.sol";

contract StrategyRouterV2ConfigurationTest is Test {
    address internal constant HASH_VAULT = address(0x1111);
    address internal constant HASH_ROUTER = address(0x2222);
    address internal constant HASH_ASSET = address(0x3333);
    address internal constant HASH_UPSHIFT = address(0x4444);
    address internal constant HASH_IDLE = address(0x5555);
    bytes32 internal constant HASH_PROFILE = keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1");
    bytes32 internal constant HASH_RISK = keccak256("risk");

    MockLPTokenV2 internal asset;
    MockLPTokenV2 internal lpToken;
    StrategyRouterV2 internal router;
    RouterBindingAdapterMockV2 internal upshift;
    RouterBindingAdapterMockV2 internal idle;
    address internal owner = address(0xA11CE);

    function setUp() public {
        asset = new MockLPTokenV2("Mock FXRP", "mFXRP", 6);
        lpToken = new MockLPTokenV2("Mock Upshift LP", "mULP", 6);
        router = new StrategyRouterV2(IERC20(address(asset)), owner);
        upshift = new RouterBindingAdapterMockV2(address(asset), address(router), address(lpToken));
        idle = new RouterBindingAdapterMockV2(address(asset), address(router), address(asset));
    }

    function testConstructorBindsImmutableIdentitiesAndEmptyState() external {
        StrategyRouterV2 freshRouter = new StrategyRouterV2(IERC20(address(asset)), owner);

        assertEq(address(freshRouter.asset()), address(asset));
        assertEq(freshRouter.vaultOwner(), owner);
        assertEq(freshRouter.vault(), address(0));
        assertEq(freshRouter.idleAdapter(), address(0));
        assertEq(freshRouter.upshiftAdapter(), address(0));
        assertEq(freshRouter.riskConfigurationHash(), bytes32(0));
        assertEq(freshRouter.routerConfigHash(), bytes32(0));
        assertFalse(freshRouter.configurationFrozen());
    }

    function testConstructorRejectsZeroAsset() external {
        vm.expectRevert(StrategyRouterV2.ZeroAddress.selector);
        new StrategyRouterV2(IERC20(address(0)), owner);
    }

    function testConstructorRejectsZeroProspectiveVaultOwner() external {
        vm.expectRevert(StrategyRouterV2.ZeroAddress.selector);
        new StrategyRouterV2(IERC20(address(asset)), address(0));
    }

    function testFinalRuntimeInterfaceSelectorsAreFrozen() external pure {
        assertEq(IStrategyRouterV2.asset.selector, bytes4(keccak256("asset()")));
        assertEq(IStrategyRouterV2.vaultOwner.selector, bytes4(keccak256("vaultOwner()")));
        assertEq(IStrategyRouterV2.vault.selector, bytes4(keccak256("vault()")));
        assertEq(IStrategyRouterV2.idleAdapter.selector, bytes4(keccak256("idleAdapter()")));
        assertEq(IStrategyRouterV2.upshiftAdapter.selector, bytes4(keccak256("upshiftAdapter()")));
        assertEq(
            IStrategyRouterV2.capabilityProfile.selector, bytes4(keccak256("capabilityProfile()"))
        );
        assertEq(
            IStrategyRouterV2.routerConfigVersion.selector,
            bytes4(keccak256("routerConfigVersion()"))
        );
        assertEq(
            IStrategyRouterV2.riskConfiguration.selector, bytes4(keccak256("riskConfiguration()"))
        );
        assertEq(
            IStrategyRouterV2.riskConfigurationHash.selector,
            bytes4(keccak256("riskConfigurationHash()"))
        );
        assertEq(
            IStrategyRouterV2.routerConfigHash.selector, bytes4(keccak256("routerConfigHash()"))
        );
        assertEq(
            IStrategyRouterV2.configurationFrozen.selector,
            bytes4(keccak256("configurationFrozen()"))
        );
        assertEq(IStrategyRouterV2.executionPaused.selector, bytes4(keccak256("executionPaused()")));
        assertEq(
            IStrategyRouterV2.upshiftRecovered.selector, bytes4(keccak256("upshiftRecovered()"))
        );
        assertEq(IStrategyRouterV2.strategyState.selector, bytes4(keccak256("strategyState()")));
        assertEq(
            IStrategyRouterV2.lastRebalanceTimestamp.selector,
            bytes4(keccak256("lastRebalanceTimestamp()"))
        );
        assertEq(IStrategyRouterV2.totalAssets.selector, bytes4(keccak256("totalAssets()")));
        assertEq(IStrategyRouterV2.grossAssets.selector, bytes4(keccak256("grossAssets()")));
        assertEq(
            IStrategyRouterV2.availableLiquidity.selector, bytes4(keccak256("availableLiquidity()"))
        );
        assertEq(IStrategyRouterV2.allocation.selector, bytes4(keccak256("allocation()")));
        assertEq(
            IStrategyRouterV2.previewRebalance.selector,
            bytes4(
                keccak256(
                    "previewRebalance((uint16,uint16,uint16,uint16),(uint256,uint16,uint16,uint16))"
                )
            )
        );
        assertEq(
            IStrategyRouterV2.rebalance.selector,
            bytes4(
                keccak256(
                    "rebalance(bytes32,(uint16,uint16,uint16,uint16),(uint256,uint16,uint16,uint16),uint256)"
                )
            )
        );
        assertEq(
            IStrategyRouterV2.withdrawToVault.selector,
            bytes4(keccak256("withdrawToVault(uint256)"))
        );
        assertEq(
            IStrategyRouterV2.withdrawAllToVault.selector, bytes4(keccak256("withdrawAllToVault()"))
        );
        assertEq(
            IStrategyRouterV2.recoverAdapterPosition.selector,
            bytes4(keccak256("recoverAdapterPosition()"))
        );
        assertEq(
            IStrategyRouterV2.setExecutionPaused.selector,
            bytes4(keccak256("setExecutionPaused(bool)"))
        );
    }

    function testProspectiveVaultOwnerConfiguresOrderedAdaptersOnce() external {
        vm.prank(owner);
        router.configureAdapters(address(upshift), address(idle));

        assertEq(router.upshiftAdapter(), address(upshift));
        assertEq(router.idleAdapter(), address(idle));

        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.ConfigurationAlreadySet.selector);
        router.configureAdapters(address(upshift), address(idle));
    }

    function testUnauthorizedCannotConfigureAdapters() external {
        vm.expectRevert(StrategyRouterV2.UnauthorizedConfigurator.selector);
        router.configureAdapters(address(upshift), address(idle));
    }

    function testRejectsZeroAdapterIdentity() external {
        vm.startPrank(owner);
        vm.expectRevert(StrategyRouterV2.ZeroAddress.selector);
        router.configureAdapters(address(0), address(idle));
        vm.expectRevert(StrategyRouterV2.ZeroAddress.selector);
        router.configureAdapters(address(upshift), address(0));
        vm.stopPrank();
    }

    function testRejectsDuplicateAdapterIdentity() external {
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.DuplicateAdapter.selector);
        router.configureAdapters(address(idle), address(idle));
    }

    function testRejectsAdapterWithWrongAsset() external {
        MockLPTokenV2 otherAsset = new MockLPTokenV2("Other", "OTHER", 6);
        RouterBindingAdapterMockV2 wrong =
            new RouterBindingAdapterMockV2(address(otherAsset), address(router), address(lpToken));

        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.AdapterAssetMismatch.selector);
        router.configureAdapters(address(wrong), address(idle));
    }

    function testConfigureAdaptersRejectsIdleAssetMismatch() public {
        MockLPTokenV2 wrongAsset = new MockLPTokenV2("Wrong Idle Asset", "WIA", 6);
        RouterBindingAdapterMockV2 wrongIdle =
            new RouterBindingAdapterMockV2(address(wrongAsset), address(router), address(asset));

        assertEq(wrongIdle.asset(), address(wrongAsset));
        assertEq(wrongIdle.positionToken(), address(asset));
        assertEq(wrongIdle.router(), address(router));

        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.AdapterAssetMismatch.selector);
        router.configureAdapters(address(upshift), address(wrongIdle));

        assertEq(router.upshiftAdapter(), address(0));
        assertEq(router.idleAdapter(), address(0));
        assertFalse(router.configurationFrozen());
    }

    function testRejectsAdapterBoundToAnotherRouter() external {
        RouterBindingAdapterMockV2 wrong =
            new RouterBindingAdapterMockV2(address(asset), address(0xB0B), address(lpToken));

        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.AdapterRouterMismatch.selector);
        router.configureAdapters(address(wrong), address(idle));
    }

    function testConfigureAdaptersRejectsIdleRouterMismatch() public {
        RouterBindingAdapterMockV2 wrongIdle =
            new RouterBindingAdapterMockV2(address(asset), address(0xB0B), address(asset));

        assertEq(wrongIdle.asset(), address(asset));
        assertEq(wrongIdle.positionToken(), address(asset));
        assertTrue(wrongIdle.router() != address(router));

        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.AdapterRouterMismatch.selector);
        router.configureAdapters(address(upshift), address(wrongIdle));

        assertEq(router.upshiftAdapter(), address(0));
        assertEq(router.idleAdapter(), address(0));
        assertFalse(router.configurationFrozen());
    }

    function testRejectsIdlePositionTokenThatIsNotUnderlying() external {
        RouterBindingAdapterMockV2 wrongIdle =
            new RouterBindingAdapterMockV2(address(asset), address(router), address(lpToken));

        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.AdapterAssetMismatch.selector);
        router.configureAdapters(address(upshift), address(wrongIdle));
    }

    function testRejectsSwappedAdapterOrdering() external {
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.AdapterAssetMismatch.selector);
        router.configureAdapters(address(idle), address(upshift));
    }

    function testProspectiveVaultOwnerConfiguresRiskOnce() external {
        RiskConfigurationV2 memory risk = _validRisk();
        vm.prank(owner);
        router.configureRisk(risk);

        RiskConfigurationV2 memory stored = router.riskConfiguration();
        assertEq(stored.minimumRebalanceInterval, risk.minimumRebalanceInterval);
        assertEq(stored.minimumAllocationChangeBps, risk.minimumAllocationChangeBps);
        assertEq(stored.maximumRebalanceLossBps, risk.maximumRebalanceLossBps);
        assertEq(stored.maximumPreviewDeviationBps, risk.maximumPreviewDeviationBps);
        assertEq(stored.allocationToleranceBps, risk.allocationToleranceBps);

        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.ConfigurationAlreadySet.selector);
        router.configureRisk(risk);
    }

    function testUnauthorizedCannotConfigureRisk() external {
        vm.expectRevert(StrategyRouterV2.UnauthorizedConfigurator.selector);
        router.configureRisk(_validRisk());
    }

    function testRiskAcceptsZeroBpsBoundary() external {
        RiskConfigurationV2 memory risk = RiskConfigurationV2({
            minimumRebalanceInterval: 0,
            minimumAllocationChangeBps: 0,
            maximumRebalanceLossBps: 0,
            maximumPreviewDeviationBps: 0,
            allocationToleranceBps: 0
        });
        vm.prank(owner);
        router.configureRisk(risk);
    }

    function testRiskAcceptsTenThousandBpsBoundary() external {
        RiskConfigurationV2 memory risk = RiskConfigurationV2({
            minimumRebalanceInterval: type(uint64).max,
            minimumAllocationChangeBps: 10_000,
            maximumRebalanceLossBps: 10_000,
            maximumPreviewDeviationBps: 10_000,
            allocationToleranceBps: 10_000
        });
        vm.prank(owner);
        router.configureRisk(risk);
    }

    function testRiskRejectsBpsAboveTenThousand() external {
        RiskConfigurationV2 memory risk = _validRisk();
        risk.minimumAllocationChangeBps = 10_001;
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.InvalidBps.selector);
        router.configureRisk(risk);

        risk = _validRisk();
        risk.maximumRebalanceLossBps = 10_001;
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.InvalidBps.selector);
        router.configureRisk(risk);

        risk = _validRisk();
        risk.maximumPreviewDeviationBps = 10_001;
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.InvalidBps.selector);
        router.configureRisk(risk);

        risk = _validRisk();
        risk.allocationToleranceBps = 10_001;
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.InvalidBps.selector);
        router.configureRisk(risk);
    }

    function testRiskRejectsToleranceAboveMinimumChange() external {
        RiskConfigurationV2 memory risk = _validRisk();
        risk.minimumAllocationChangeBps = 99;
        risk.allocationToleranceBps = 100;
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.InvalidRiskConfiguration.selector);
        router.configureRisk(risk);
    }

    function testBindFreezesExactIdentitiesAndConfigHash() external {
        _configure();
        RouterBoundVaultMockV2 boundVault = new RouterBoundVaultMockV2(owner);
        vm.prank(owner);
        router.bindVault(address(boundVault));

        RiskConfigurationV2 memory risk = _validRisk();
        bytes32 expectedRisk = keccak256(
            abi.encode(
                keccak256("SIGNALVAULT_ROUTER_RISK_CONFIG_V1"),
                risk.minimumRebalanceInterval,
                risk.minimumAllocationChangeBps,
                risk.maximumRebalanceLossBps,
                risk.maximumPreviewDeviationBps,
                risk.allocationToleranceBps
            )
        );
        bytes32 expectedConfig = keccak256(
            abi.encode(
                keccak256("SIGNALVAULT_ROUTER_CONFIG_V1"),
                block.chainid,
                address(boundVault),
                address(router),
                address(asset),
                address(upshift),
                address(idle),
                keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1"),
                expectedRisk,
                uint256(1)
            )
        );

        assertEq(router.vault(), address(boundVault));
        assertEq(router.riskConfigurationHash(), expectedRisk);
        assertEq(router.routerConfigHash(), expectedConfig);
        assertTrue(router.configurationFrozen());
        assertEq(router.capabilityProfile(), keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1"));
        assertEq(router.routerConfigVersion(), 1);
    }

    function testUnauthorizedCannotBindVault() external {
        _configure();
        RouterBoundVaultMockV2 boundVault = new RouterBoundVaultMockV2(owner);
        vm.expectRevert(StrategyRouterV2.UnauthorizedConfigurator.selector);
        router.bindVault(address(boundVault));
    }

    function testBindRequiresBothPriorConfigurations() external {
        RouterBoundVaultMockV2 boundVault = new RouterBoundVaultMockV2(owner);
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.ConfigurationIncomplete.selector);
        router.bindVault(address(boundVault));

        vm.prank(owner);
        router.configureAdapters(address(upshift), address(idle));
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.ConfigurationIncomplete.selector);
        router.bindVault(address(boundVault));
    }

    function testBindRejectsRiskOnlyConfiguration() external {
        RouterBoundVaultMockV2 boundVault = new RouterBoundVaultMockV2(owner);
        vm.prank(owner);
        router.configureRisk(_validRisk());
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.ConfigurationIncomplete.selector);
        router.bindVault(address(boundVault));
    }

    function testBindRejectsZeroVault() external {
        _configure();
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.ZeroAddress.selector);
        router.bindVault(address(0));
    }

    function testBindRejectsVaultOwnerMismatch() external {
        _configure();
        RouterBoundVaultMockV2 wrongVault = new RouterBoundVaultMockV2(address(0xB0B));
        vm.prank(owner);
        vm.expectRevert(StrategyRouterV2.VaultOwnerMismatch.selector);
        router.bindVault(address(wrongVault));
    }

    function testSecondBindAndEveryPostBindMutationRevert() external {
        _bind();
        RouterBoundVaultMockV2 otherVault = new RouterBoundVaultMockV2(owner);

        vm.startPrank(owner);
        vm.expectRevert(StrategyRouterV2.ConfigurationFrozen.selector);
        router.bindVault(address(otherVault));
        vm.expectRevert(StrategyRouterV2.ConfigurationFrozen.selector);
        router.configureAdapters(address(upshift), address(idle));
        vm.expectRevert(StrategyRouterV2.ConfigurationFrozen.selector);
        router.configureRisk(_validRisk());
        vm.stopPrank();
    }

    function testRouterConfigHashIsDeterministic() external view {
        assertEq(_canonicalConfigHash(), _canonicalConfigHash());
    }

    function testRouterConfigHashChangesWithChainId() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid + 1,
                HASH_VAULT,
                HASH_ROUTER,
                HASH_ASSET,
                HASH_UPSHIFT,
                HASH_IDLE,
                HASH_PROFILE,
                HASH_RISK,
                1
            )
        );
    }

    function testRouterConfigHashChangesWithVault() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid,
                address(0x1112),
                HASH_ROUTER,
                HASH_ASSET,
                HASH_UPSHIFT,
                HASH_IDLE,
                HASH_PROFILE,
                HASH_RISK,
                1
            )
        );
    }

    function testRouterConfigHashChangesWithRouter() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid,
                HASH_VAULT,
                address(0x2223),
                HASH_ASSET,
                HASH_UPSHIFT,
                HASH_IDLE,
                HASH_PROFILE,
                HASH_RISK,
                1
            )
        );
    }

    function testRouterConfigHashChangesWithAsset() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid,
                HASH_VAULT,
                HASH_ROUTER,
                address(0x3334),
                HASH_UPSHIFT,
                HASH_IDLE,
                HASH_PROFILE,
                HASH_RISK,
                1
            )
        );
    }

    function testRouterConfigHashChangesWithUpshiftAdapter() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid,
                HASH_VAULT,
                HASH_ROUTER,
                HASH_ASSET,
                address(0x4445),
                HASH_IDLE,
                HASH_PROFILE,
                HASH_RISK,
                1
            )
        );
    }

    function testRouterConfigHashChangesWithIdleAdapter() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid,
                HASH_VAULT,
                HASH_ROUTER,
                HASH_ASSET,
                HASH_UPSHIFT,
                address(0x5556),
                HASH_PROFILE,
                HASH_RISK,
                1
            )
        );
    }

    function testRouterConfigHashChangesWithCapabilityProfile() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid,
                HASH_VAULT,
                HASH_ROUTER,
                HASH_ASSET,
                HASH_UPSHIFT,
                HASH_IDLE,
                bytes32(uint256(HASH_PROFILE) ^ 1),
                HASH_RISK,
                1
            )
        );
    }

    function testRouterConfigHashChangesWithRiskHash() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid,
                HASH_VAULT,
                HASH_ROUTER,
                HASH_ASSET,
                HASH_UPSHIFT,
                HASH_IDLE,
                HASH_PROFILE,
                bytes32(uint256(HASH_RISK) ^ 1),
                1
            )
        );
    }

    function testRouterConfigHashChangesWithVersion() external view {
        assertNotEq(
            _canonicalConfigHash(),
            _configHash(
                block.chainid,
                HASH_VAULT,
                HASH_ROUTER,
                HASH_ASSET,
                HASH_UPSHIFT,
                HASH_IDLE,
                HASH_PROFILE,
                HASH_RISK,
                2
            )
        );
    }

    function testRiskConfigurationHashIsSensitiveToEveryField() external pure {
        RiskConfigurationV2 memory risk = _validRisk();
        bytes32 canonical = SignalVaultHashesV2.computeRiskConfigurationHash(risk);

        risk.minimumRebalanceInterval++;
        assertNotEq(canonical, SignalVaultHashesV2.computeRiskConfigurationHash(risk));
        risk = _validRisk();
        risk.minimumAllocationChangeBps++;
        assertNotEq(canonical, SignalVaultHashesV2.computeRiskConfigurationHash(risk));
        risk = _validRisk();
        risk.maximumRebalanceLossBps++;
        assertNotEq(canonical, SignalVaultHashesV2.computeRiskConfigurationHash(risk));
        risk = _validRisk();
        risk.maximumPreviewDeviationBps++;
        assertNotEq(canonical, SignalVaultHashesV2.computeRiskConfigurationHash(risk));
        risk = _validRisk();
        risk.allocationToleranceBps++;
        assertNotEq(canonical, SignalVaultHashesV2.computeRiskConfigurationHash(risk));
    }

    function _configHash(
        uint256 chainId,
        address vaultAddress,
        address routerAddress,
        address assetAddress,
        address upshiftAddress,
        address idleAddress,
        bytes32 profile,
        bytes32 riskHash,
        uint256 version
    ) internal pure returns (bytes32) {
        return SignalVaultHashesV2.computeRouterConfigHash(
            chainId,
            vaultAddress,
            routerAddress,
            assetAddress,
            upshiftAddress,
            idleAddress,
            profile,
            riskHash,
            version
        );
    }

    function _canonicalConfigHash() internal view returns (bytes32) {
        return _configHash(
            block.chainid,
            HASH_VAULT,
            HASH_ROUTER,
            HASH_ASSET,
            HASH_UPSHIFT,
            HASH_IDLE,
            HASH_PROFILE,
            HASH_RISK,
            1
        );
    }

    function _configure() internal {
        vm.startPrank(owner);
        router.configureAdapters(address(upshift), address(idle));
        router.configureRisk(_validRisk());
        vm.stopPrank();
    }

    function _bind() internal returns (RouterBoundVaultMockV2 boundVault) {
        _configure();
        boundVault = new RouterBoundVaultMockV2(owner);
        vm.prank(owner);
        router.bindVault(address(boundVault));
    }

    function _validRisk() internal pure returns (RiskConfigurationV2 memory) {
        return RiskConfigurationV2({
            minimumRebalanceInterval: 1 hours,
            minimumAllocationChangeBps: 100,
            maximumRebalanceLossBps: 75,
            maximumPreviewDeviationBps: 50,
            allocationToleranceBps: 25
        });
    }
}
