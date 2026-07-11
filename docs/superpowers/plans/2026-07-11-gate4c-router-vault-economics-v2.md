# Gate 4C Router and Vault Economics V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement independent StrategyRouterV2 and SignalVaultV2 contracts with net-liquidation accounting, differential rebalance, liquidity-first withdrawal, frozen risk configuration, and signed V2 execution.

**Architecture:** SignalVaultV2 owns personal shares and authenticates results; StrategyRouterV2 owns allocation policy and composes reviewed V2 adapters. Vault funding is pushed with exact balance reconciliation, withdrawals consume fee-free tiers first, and every rebalance is bounded by signed limits that cannot exceed frozen Router limits.

**Tech Stack:** Solidity 0.8.27, Foundry, OpenZeppelin ERC20/SafeERC20/ReentrancyGuard/Math, Gate 4A V2 hashes/verifier, Gate 4B adapters and hostile mocks.

## Global Constraints

* V2 contracts are independent deployments; do not modify or reuse deployed P0 addresses.
* P0 contracts and tests remain as a verified baseline.
* All production behavior begins with a failing test.
* No task may weaken existing security assertions to obtain a green test.
* Coston2 enables only real Upshift and Idle.
* Firelight and SparkDEX weights must be exactly zero in the Coston2 capability profile.
* Unsupported strategy weights revert and are never silently redirected.
* Net-liquidation value prices shares and withdrawals.
* Gross value is telemetry only.
* The live Upshift preview is authoritative; never hardcode 50 BPS.
* All underlying amounts use six-decimal token smallest units at runtime, without assuming six decimals inside generic arithmetic.
* Every BPS denominator is 10,000.
* Use full-precision multiplication/division helpers where multiplication may overflow.
* No unlimited token approval.
* Exact approvals must be zero after successful and reverted protocol flows where cleanup is reachable.
* No real private key, `.env`, deployment secret, or Coston2 wallet credential may be committed.
* Every task ends with fresh focused tests, full relevant regressions, diff review, and an independent review gate.
* Do not deploy to Coston2 until the complete Anvil V2 E2E passes.
* Do not begin frontend or TEE work during Gate 4.

---

## Frozen Router and Vault Surfaces

`IStrategyRouterV2` uses the approved getters and:

```solidity
function withdrawAssets(uint256 assets) external returns (uint256 assetsOut);
function withdrawAll() external returns (uint256 assetsOut);
function rebalance(
    bytes32 resultHash,
    AllocationV2 calldata allocation,
    RebalanceLimitsV2 calldata limits,
    uint256 fundingAssets
) external returns (uint256 postNetAssets);
```

Configuration methods are owner-only and one-time: `configureAdapters(address upshift,address idle)`, `configureRisk(RiskConfigurationV2)`, and `bindVault(address vault)`. Runtime owner methods are `setExecutionPaused(bool)` and the explicitly named recovery selectors; none changes frozen adapters, capability, risk, or config hash.

`SignalVaultV2` exposes:

```solidity
function deposit(uint256 assets) external returns (uint256 shares);
function withdraw(uint256 shares, uint256 minAssetsOut) external returns (uint256 assetsOut);
function withdrawAll(uint256 minAssetsOut) external returns (uint256 assetsOut);
function executeTEEAllocation(TEEResultV2 calldata result, bytes calldata signature) external;
```

## Frozen Risk Semantics

| Parameter | Unit and denominator | Formula / comparison | Enforcement point | Emergency behavior |
|---|---|---|---|---|
| `minimumRebalanceInterval` | seconds | `block.timestamp - lastSuccessfulRebalance >= frozen.minimumRebalanceInterval` | before any qualifying rebalance external call | withdrawals/recovery bypass; ordinary rebalance never bypasses |
| `minimumAllocationChangeBps` | BPS / 10,000 | `floor(sum(abs(currentBps-targetBps))/2)` | before adapter mutation; smaller change is consumed/skipped | not applicable to withdrawal/recovery |
| `maximumRebalanceLossBps` | BPS / 10,000 | `floor(max(preNAV-postNAV,0)*10_000/preNAV)` | after rebalance mutations, before success | ordinary withdrawal does not use it; emergency is separately named/emitted |
| `maximumPreviewDeviationBps` | BPS / 10,000 | `floor(max(previewNet-actualNet,0)*10_000/max(previewNet,1))` | after each measured protocol mutation | no ordinary bypass; emergency uses explicit owner minimum |
| `allocationToleranceBps` | BPS / 10,000 | `floor(abs(actualNet-targetNet)*10_000/max(postNAV,1))` | post-rebalance for Upshift and Idle | not applicable to withdrawal/recovery |

All five values are configured once by Vault owner and frozen at `bindVault`. Each BPS field is `<= 10_000`, and `allocationToleranceBps <= minimumAllocationChangeBps`. SignalVault enforces these exact strength directions before funding Router:

```text
signed.maximumRebalanceLossBps
    <= frozen.maximumRebalanceLossBps

signed.maximumPreviewDeviationBps
    <= frozen.maximumPreviewDeviationBps

signed.allocationToleranceBps
    <= frozen.allocationToleranceBps
```

`minimumPostNAV` is an absolute underlying-smallest-unit floor checked after execution and has no frozen maximum counterpart.

### Task 1: RouterV2 Configuration, Binding, Risk Freeze, and Config Hash

**Files:**
- Create: `src/v2/interfaces/IStrategyRouterV2.sol`
- Create: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Configuration.t.sol`
- Create: `test/v2/mocks/RouterBoundVaultMockV2.sol`

**Interfaces:**
- Consumes: Gate 4A `AllocationV2`, `RebalanceLimitsV2`, `RiskConfigurationV2`, `SignalVaultHashesV2`; Gate 4B `IStrategyAdapterV2`.
- Produces: Router configuration/getter ABI, immutable asset/vaultOwner, two-adapter capability, frozen risk hash, and frozen Router config hash.

- [ ] **Step 1: Write failing configuration tests.**

```solidity
function testBindFreezesExactRouterConfigHash() external {
    router.configureAdapters(address(upshift), address(idle));
    router.configureRisk(risk());
    RouterBoundVaultMockV2 vault = new RouterBoundVaultMockV2(owner);
    router.bindVault(address(vault));
    bytes32 expected = SignalVaultHashesV2.computeRouterConfigHash(
        block.chainid, address(vault), address(router), address(asset),
        address(upshift), address(idle), router.capabilityProfile(),
        router.riskConfigurationHash(), router.routerConfigVersion()
    );
    assertEq(router.routerConfigHash(), expected);
    assertTrue(router.riskConfigurationFrozen());
}

function testRejectsRiskBoundsAndOwnerMismatch() external {
    RiskConfigurationV2 memory bad = risk();
    bad.maximumRebalanceLossBps = 10_001;
    vm.expectRevert(StrategyRouterV2.InvalidBps.selector);
    router.configureRisk(bad);
}
```

Also test zero/duplicate/wrong-asset adapters, configure twice, bind before configuration, bind twice, Vault owner mismatch, every BPS at 0/10,000/10,001, `allocationToleranceBps > minimumAllocationChangeBps`, and post-bind mutation rejection.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Configuration.t.sol -vvv`

Expected: FAIL because RouterV2 and its interface are absent.

- [ ] **Step 3: Implement one-time configuration.**

Constructor arguments are `(IERC20 asset_, address vaultOwner_)`; ownership is transferred to `vaultOwner_`. `configureAdapters` requires unique nonzero adapters whose `asset()` equals the Router asset. `configureRisk` validates all BPS `<= 10_000` and `allocationToleranceBps <= minimumAllocationChangeBps`. `bindVault` requires both configurations, checks `vault.vaultOwner() == owner()`, stores the Vault, computes/fixes both hashes, and disables every configuration setter forever.

Use capability `keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1")` and config version `1`. No constructor or binding path approves tokens.

- [ ] **Step 4: Run GREEN and Gate 4A/4B regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Configuration.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv`

Expected: configuration and adapter suites PASS.

- [ ] **Step 5: Review and commit Task 1.**

Review checklist: circular deployment remains resolvable; hash fields/order match Gate 4A; only Vault owner configures; bind freezes state; no P0 import except shared libraries allowed by plan; no approval exists.

```powershell
git diff --check
git add src/v2/interfaces/IStrategyRouterV2.sol src/v2/StrategyRouterV2.sol test/v2/StrategyRouterV2Configuration.t.sol test/v2/mocks/RouterBoundVaultMockV2.sol
git commit -m "feat: configure strategy router v2"
```

Request independent review and resolve every Critical or Important finding before Task 2.

### Task 2: RouterV2 NAV and Liquidity-First Withdrawal

**Files:**
- Modify: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Accounting.t.sol`
- Create: `test/v2/StrategyRouterV2Withdraw.t.sol`
- Create: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`

**Interfaces:**
- Consumes: Adapter V2 net/gross/liquidity/withdraw methods.
- Produces: `totalAssets`, `grossAssets`, `depositsEnabled`, `withdrawAssets`, `withdrawAll`, detailed withdrawal events, and `InstrumentedStrategyAdapterV2` with `seedValues(direct,gross,net,liquidity)`, `redeemCallCount`, `withdrawCallCount`, `lastRedeemNetRequested`, `lastDepositAssets`, `stateChangingCallCount`, `protocolPreviewCallCount`, and `resetCallCounters()`.

- [ ] **Step 1: Write failing NAV and waterfall tests.**

```solidity
function testNavUsesNetAndGrossIsTelemetry() external {
    asset.mint(address(router), 5);
    idle.seedValues(20, 20, 20, 20);
    upshift.seedValues(0, 99, 95, 95);
    assertEq(router.totalAssets(), 5 + 20 + 95);
    assertEq(router.grossAssets(), 5 + 20 + 99);
}

function testWithdrawalUsesEveryFeeFreeTierBeforeShares() external {
    seedRouterLiquid(10);
    seedIdle(20);
    seedUpshiftDirect(5);
    seedUpshiftPosition(100);
    vm.prank(vault);
    assertEq(router.withdrawAssets(40), 40);
    assertEq(upshift.redeemCallCount(), 1);
    assertEq(upshift.lastRedeemNetRequested(), 5);
}
```

Add tier-only cases, over-redemption retained as Router liquid, pause with fee-free success, insufficient capacity atomic revert, Router/adapter donation single-counting, full withdrawal, zero Upshift position, and reported-versus-measured mismatch.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Accounting.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Withdraw.t.sol -vvv`

Expected: both commands FAIL because accounting/withdrawal bodies are absent.

- [ ] **Step 3: Implement accounting and waterfall.**

`totalAssets = router direct + idle.totalAssets() + upshift.totalAssets()`. `grossAssets` uses adapter gross views and is never referenced by Vault pricing. `withdrawAssets(assets)` is onlyVault/nonReentrant and consumes Router direct, Idle `withdrawLiquid`, Upshift `withdrawLiquid`, then the minimum share redemption needed for the deficit. Measure Router balance around every adapter call. Transfer exactly `assets` to Vault; retain over-redemption.

`withdrawAll` drains Router direct, calls `idle.redeemAll(0)` and `upshift.redeemAll(preview-derived minimum)`, checks adapter shares and underlying are zero, transfers the complete measured Router balance to Vault, and returns that delta.

- [ ] **Step 4: Run GREEN and adapter regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Accounting.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Withdraw.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv`

Expected: all accounting, waterfall, full recovery, and adapter suites PASS.

- [ ] **Step 5: Review and commit Task 2.**

Review checklist: net and gross never cross; direct donations count once; tier order is exact; every adapter call is reconciled; partial output is exact; full close leaves no recoverable underlying.

```powershell
git diff --check
git add src/v2/StrategyRouterV2.sol test/v2/StrategyRouterV2Accounting.t.sol test/v2/StrategyRouterV2Withdraw.t.sol test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "feat: add router v2 asset accounting"
```

Request independent review and resolve every Critical or Important finding before Task 3.

### Task 3: Differential Rebalance and Economic Controls

**Files:**
- Modify: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Rebalance.t.sol`
- Create: `test/v2/StrategyRouterV2Risk.t.sol`

**Interfaces:**
- Consumes: `rebalance(resultHash,allocation,limits,fundingAssets)`, Task 2 `InstrumentedStrategyAdapterV2`, adapter previews/execution, OpenZeppelin `Math.mulDiv` and `Math.Rounding.Ceil`.
- Produces: differential two-candidate solver, cooldown/turnover/loss/deviation/tolerance enforcement, no-op event semantics.

- [ ] **Step 1: Write failing differential tests.**

```solidity
function testIncreaseMovesOnlyDeltaAndUsesAtMostFourProtocolPreviews() external {
    seedAllocation(4_000, 6_000);
    rebalance(AllocationV2(5_000, 0, 0, 5_000));
    assertEq(upshift.withdrawCallCount(), 0);
    assertLt(upshift.lastDepositAssets(), preNAV);
    assertLe(upshift.protocolPreviewCallCount(), 4);
}

function testBelowThresholdConsumesResultWithoutAdvancingCooldown() external {
    uint256 beforeTimestamp = router.lastSuccessfulRebalance();
    vm.expectEmit();
    emit RebalanceSkipped(HASH, 50, 100);
    rebalance(AllocationV2(5_050, 0, 0, 4_950));
    assertEq(router.lastSuccessfulRebalance(), beforeTimestamp);
    assertEq(upshift.stateChangingCallCount(), 0);
}
```

Add decrease-only-delta, exact no-op, one refinement, nonconvergence, zero candidate, candidate above shares, six-decimal rounding, `preNAV == 0`, funding mismatch, cooldown boundary, loss boundary, preview deviation boundary, allocation tolerance boundary, minimum post-NAV, overflow-sized values, pause, and unsupported weight cases.

Add Router allowance cases asserting exact approval to the selected adapter, zero allowance after success, zero allowance after a protocol-revert rollback, and no allowance to the adapter that is not receiving funds.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Rebalance.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Risk.t.sol -vvv`

Expected: FAIL because differential rebalance and controls are absent.

- [ ] **Step 3: Implement bounded differential math.**

Classify Router/Idle/Upshift-adapter direct underlying as Idle; only LP net value is Upshift exposure. Compute current and target BPS with `Math.mulDiv(value,10_000,nav)` floor. Turnover is half the sum of absolute weight deltas. A no-op or turnover below `minimumAllocationChangeBps` emits `RebalanceSkipped`, makes no external call, and does not advance cooldown.

For decrease, estimate shares with `Math.mulDiv(heldShares,requiredNet,currentPositionNet,Math.Rounding.Ceil)`, preview, and permit one scaled refinement. For increase, each candidate calls composed adapter preview; permit the initial candidate plus one refinement. Execute only the final candidate. Before `adapter.deposit`, Router uses `forceApprove(adapter, assets)` for the exact candidate; after the call it uses `forceApprove(adapter, 0)` and requires allowance zero. A revert rolls back both approval and protocol state. Around deposit, Router reconciles its exact underlying decrease and the adapter's exact position-share increase with the adapter return; around `withdrawLiquid`/redeem it reconciles its exact underlying increase with the adapter return. After every mutation enforce adverse preview deviation, then `postNAV >= minimumPostNAV`, Vault-level loss BPS, and per-strategy allocation tolerance. All denominators are 10,000 and all zero denominators use explicit branches.

- [ ] **Step 4: Run GREEN and Router regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Rebalance.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Risk.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv`

Expected: all differential/risk/router suites PASS.

- [ ] **Step 5: Review and commit Task 3.**

Review checklist: full unwind is impossible in ordinary rebalance; two candidate evaluations are hard-bounded; all multiplication uses full precision; signed limits cannot exceed frozen limits; no-op/cooldown semantics match design; postconditions revert atomically.

```powershell
git diff --check
git add src/v2/StrategyRouterV2.sol test/v2/StrategyRouterV2Rebalance.t.sol test/v2/StrategyRouterV2Risk.t.sol
git commit -m "feat: add differential rebalance v2"
```

Request independent review and resolve every Critical or Important finding before Task 4.

### Task 4: SignalVaultV2 Net Share Accounting and Withdrawals

**Files:**
- Create: `src/v2/SignalVaultV2.sol`
- Create: `src/v2/interfaces/ISignalVaultV2.sol`
- Create: `test/v2/SignalVaultV2Accounting.t.sol`
- Create: `test/v2/SignalVaultV2Withdraw.t.sol`
- Create: `test/v2/mocks/RouterAccountingMockV2.sol`
- Create: `test/v2/mocks/ExactDeltaERC20Mock.sol`

**Interfaces:**
- Consumes: `IStrategyRouterV2`, IERC20 metadata, non-transferable ERC20 shares, `Math.mulDiv`.
- Produces: owner-only deposit/withdraw/full-withdraw, net/gross views, exact push funding helper, balance reconciliation, and `ExactDeltaERC20Mock.setTransferFeeBps(uint16)` for rejection-only tests.

- [ ] **Step 1: Write failing Vault accounting tests.**

```solidity
function testDepositPricesAgainstNetNavAndCreatesNoRouterAllowance() external {
    router.setNetAssets(95);
    depositAsOwner(95);
    assertEq(vault.balanceOf(owner), 95);
    assertEq(asset.allowance(address(vault), address(router)), 0);
}

function testDepositRejectsUnderlyingUnderReceipt() external {
    asset.setTransferFeeBps(100);
    vm.prank(owner);
    vm.expectRevert(SignalVaultV2.AssetDeltaMismatch.selector);
    vault.deposit(100);
    assertEq(vault.totalSupply(), 0);
}

function testPartialWithdrawalPricesBeforeBurnAndPaysExactOwed() external {
    seedVault(100, 100);
    router.setNetAssets(100);
    vm.prank(owner);
    uint256 out = vault.withdraw(25, 49);
    assertEq(out, 50);
    assertEq(vault.totalSupply(), 75);
}
```

Add decimals, owner-only, non-transferable shares, second deposit, donation, zero mint, minimum output, Router under/over-report, fee-on-transfer deposit under-receipt, owner payout under-receipt, transfer reentrancy, Vault-only liquidity, partial waterfall, full close before burn, paused zero-position full close, and unrecoverable-position revert cases. Extend the test token mock with a configurable transfer fee solely to prove V2 rejects non-exact asset deltas.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignalVaultV2Accounting.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignalVaultV2Withdraw.t.sol -vvv`

Expected: FAIL because SignalVaultV2 is absent.

- [ ] **Step 3: Implement minimal Vault economics.**

`totalAssets = Vault asset balance + router.totalAssets()` and `grossAssets` is telemetry. Deposit snapshots net NAV and Vault balance before transfer, requires the Vault balance increase to equal requested `assets`, then mints with floor `Math.mulDiv(assets,supply,assetsBefore)`; no Router approval is set. Partial withdrawal snapshots NAV/supply, computes floor owed, uses Vault liquid then exact `router.withdrawAssets(deficit)`, reconciles Vault balance delta, burns only after success, snapshots owner balance around the payout, and requires the owner increase to equal owed. Non-exact-transfer assets are rejected rather than silently socialized.

Full withdrawal calls `router.withdrawAll`, reconciles the Router delta, checks the final combined amount against owner `minAssetsOut`, requires all normal recoverable balances/shares zero, then burns all shares, transfers every underlying unit, and requires the owner's measured balance increase to equal `assetsOut`. Reverts roll back all burns and protocol calls.

- [ ] **Step 4: Run GREEN and Router regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignalVaultV2Accounting.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignalVaultV2Withdraw.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv`

Expected: Vault and Router suites PASS.

- [ ] **Step 5: Review and commit Task 4.**

Review checklist: only net NAV prices shares; burn occurs after reconciliation; partial pays exact owed; full close cannot strand underlying; no unlimited approval; owner-only and reentrancy protections preserve P0 assertions.

```powershell
git diff --check
git add src/v2/SignalVaultV2.sol src/v2/interfaces/ISignalVaultV2.sol test/v2/SignalVaultV2Accounting.t.sol test/v2/SignalVaultV2Withdraw.t.sol test/v2/mocks/RouterAccountingMockV2.sol test/v2/mocks/ExactDeltaERC20Mock.sol
git commit -m "feat: add signal vault v2 accounting"
```

Request independent review and resolve every Critical or Important finding before Task 5.

### Task 5: Signed Execution, Exact Funding, Pause, Replay, and Emergency Recovery

**Files:**
- Modify: `src/v2/SignalVaultV2.sol`
- Modify: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/SignalVaultV2Execution.t.sol`
- Create: `test/v2/SignalVaultV2Emergency.t.sol`
- Create: `test/v2/mocks/ReentrantRouterV2.sol`

**Interfaces:**
- Consumes: `IntentVerifierV2`, `SignalVaultHashesV2`, frozen Router getters, Router rebalance/pause/recovery.
- Produces: V2 intent/replay execution, exact Vault→Router push, owner pause, underlying recovery, LP-position recovery, and emergency close.

- [ ] **Step 1: Write failing signed-execution tests.**

```solidity
function testExecutionBindsProfileConfigAndStricterLimits() external {
    TEEResultV2 memory result = validResult();
    result.routerConfigHash = bytes32(uint256(1));
    result.resultHash = SignalVaultHashesV2.computeResultHash(result);
    vm.expectRevert(SignalVaultV2.InvalidRouterConfig.selector);
    vault.executeTEEAllocation(result, sign(result));
}

function testPushFundingMeasuresBothBalancesAndLeavesNoAllowance() external {
    depositAsOwner(100);
    execute(validResult());
    assertEq(router.lastFundingAssets(), 100);
    assertEq(asset.balanceOf(address(vault)), 0);
    assertEq(asset.allowance(address(vault), address(router)), 0);
}
```

Add every-field mutation, wrong domain/profile/config/chain/Vault/deadline, V1 signature, replay, loose loss/deviation/tolerance, resultHash mismatch, no-op consumed, cooldown unchanged, funding under-transfer, pause, ordinary recovery rejection, emergency owner checks, LP recovery event, post-recovery disabled state, and reentrancy.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignalVaultV2Execution.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignalVaultV2Emergency.t.sol -vvv`

Expected: FAIL because V2 signed execution and recovery selectors are absent.

- [ ] **Step 3: Implement authenticated execution and recovery.**

Recompute canonical hash; verify owner/Vault/intent nonce/commitment/signature; require signed profile/config equal Router; enforce each signed maximum `<=` frozen maximum; mark canonical hash executed before external calls; measure Router balance, push exact Vault liquid, require Router delta equals `fundingAssets`, then call rebalance. Revert atomicity restores replay state on failure.

`setExecutionPaused` is owner-only. Emergency selectors require pause and owner, emit separate underlying versus LP recovery events, and never report LP recovery as underlying. Router snapshots the recovery receiver's LP balance and the adapter LP balance, then requires both deltas and `sharesRecovered` to agree. `emergencyClose` may burn remaining personal shares only after underlying and position-token outputs are recorded and normal Router accounting is permanently disabled.

- [ ] **Step 4: Run GREEN and complete V2 economics regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignalVaultV2Execution.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignalVaultV2Emergency.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*.t.sol' -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test -vvv`

Expected: all V2 and P0 Foundry tests PASS.

- [ ] **Step 5: Review and commit Task 5.**

Review checklist: all signed fields are authenticated; inequalities point stricter; replay state is atomic; funding has two balance checks; pause cannot weaken config; emergency path is distinct and owner-only; P0 files remain unchanged.

```powershell
git diff --check
git add src/v2/SignalVaultV2.sol src/v2/StrategyRouterV2.sol test/v2/SignalVaultV2Execution.t.sol test/v2/SignalVaultV2Emergency.t.sol test/v2/mocks/ReentrantRouterV2.sol
git commit -m "feat: bind signed execution and recovery v2"
```

Request independent review and resolve every Critical or Important finding.

## Gate 4C Completion Verification

Run fresh:

```powershell
D:\xhy\tools\foundry\forge.exe fmt --check
D:\xhy\tools\foundry\forge.exe build
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/SignalVaultV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test -vvv
npm test
npm run typecheck
```

Require every Gate 3 Section 12 case mapped to a focused test, every external mutation reconciled, every loop bounded, no P0 source/test change, and no unresolved Critical or Important review issue. Stop before deployment, Coston2 transactions, frontend, or TEE work.
