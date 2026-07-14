# StrategyRouterV2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the reviewed StrategyRouterV2 asset-execution module with strict differential allocation, net-liquidation accounting, direct-buffer priority, exact Vault withdrawals, bounded protocol interaction, and permanent recovery state.

**Architecture:** StrategyRouterV2 is an independent V2 deep module between SignalVaultV2 and the frozen Gate 4B adapters. It owns execution math and postconditions behind a small Vault-only runtime interface. It configures exact adapter and Vault identities once, freezes Gate 4A configuration hashes, executes only Upshift/Idle targets, and never interprets private intent.

**Tech Stack:** Solidity 0.8.27, Foundry, OpenZeppelin IERC20/SafeERC20/ReentrancyGuard/Math, Gate 4A V2 types and hashes, frozen Gate 4B adapters and hostile mocks.

**Repository:** `https://github.com/hux-gif/SignalVault/`

**Required baseline:** `5551e68d0c00fbcf435e289d7dc03b64e4802a8f`

**Design authority:** `docs/superpowers/specs/2026-07-14-strategy-router-v2-design.md`

## Global Constraints

- Work only on `signalvault-final` in `D:\xhy.worktrees\signalvault-final`.
- Preserve `main` and `gate4b-upshift-adapters-v2`; do not force-push either branch.
- Do not modify `src/StrategyRouter.sol`, `src/SignalVault.sol`, `src/IntentVerifier.sol`, P0 types, P0 adapters, or P0 tests.
- Do not modify the frozen Gate 4B interfaces or adapters.
- V2 contracts are independent deployments and do not reuse deployed P0 addresses.
- Every production behavior starts with a focused failing test whose failure is caused by the absent behavior.
- Do not weaken an assertion, expected revert, delta check, or mutation test to make a test green.
- All runtime state-changing Router selectors are `onlyVault` and `nonReentrant`.
- Configuration is one-time, becomes permanently frozen at Vault bind, and has no replacement selector.
- Coston2 enables only Upshift and Idle; Firelight and SparkDEX weights must be zero.
- Unsupported weights revert and are never redirected.
- Net-liquidation value controls allocation, loss, and withdrawal; gross value is telemetry only.
- The live Upshift preview is authoritative; never hardcode the observed 50 BPS fee.
- Runtime asset amounts use token smallest units without assuming six decimals in arithmetic.
- Every BPS denominator is exactly `10_000`.
- Use `Math.mulDiv` for products that can overflow and declare every rounding direction.
- Candidate refinement is limited to one initial candidate plus one refinement.
- Gate 4B `availableLiquidity` retains its independent 64-preview maximum.
- No unlimited approval is permitted.
- Every temporary Router-to-adapter approval is exact and zero after reachable success.
- Every external state-changing call is reconciled with Router, adapter, Vault, underlying, or position-token balance deltas as applicable.
- No arbitrary receiver, arbitrary call, or `delegatecall` is permitted.
- No real private key, `.env`, deployment credential, or Coston2 wallet secret may be read, logged, staged, or committed.
- Every task ends with focused GREEN, relevant full regression, complete diff review, mutation or sensitivity evidence, and an independent review gate.
- Do not begin SignalVaultV2, deployment, Anvil E2E, Coston2 broadcast, frontend, FTSO, FCC, or TEE work in this plan.

## Frozen dependency check before Task 1

Run from the final worktree:

```powershell
git status --short
git branch --show-current
git rev-parse HEAD
git merge-base --is-ancestor 5551e68d0c00fbcf435e289d7dc03b64e4802a8f HEAD
git diff --exit-code 5551e68d0c00fbcf435e289d7dc03b64e4802a8f -- `
  src/v2/interfaces/IStrategyAdapterV2.sol `
  src/v2/interfaces/IStrategyRecoveryV2.sol `
  src/v2/interfaces/IUpshiftVaultV2.sol `
  src/v2/adapters/IdleAdapterV2.sol `
  src/v2/adapters/UpshiftAdapterV2.sol
```

Require a clean worktree, branch `signalvault-final`, an ancestor check exit code of `0`, and no frozen-file diff. Stop on any mismatch.

## Task dependency matrix

| Task | Depends on | Production output | Focused certification | Commit message |
|---|---|---|---|---|
| 1 | Gate 4A hashes and Gate 4B ABI | Interface, constructor, one-time binding, risk/config hashes | configuration suite | `feat: configure strategy router v2` |
| 2 | Task 1 | net/gross/liquidity/allocation views | accounting suite | `feat: add router v2 accounting views` |
| 3 | Tasks 1–2 | shared strict plan computation | planning suite | `feat: plan differential rebalance v2` |
| 4 | Task 3 | direct-buffer and Idle deposit execution | execution Idle cases | `feat: execute idle router deltas v2` |
| 5 | Task 4 | Upshift increase/decrease execution | execution Upshift cases | `feat: execute upshift router deltas v2` |
| 6 | Task 5 | loss, limits, tolerance, interval | risk suite | `feat: enforce router v2 economic limits` |
| 7 | Tasks 2 and 5 | exact waterfall and full normal close | withdrawal suite | `feat: add router v2 vault withdrawals` |
| 8 | Tasks 1, 2, and 7 | paused LP recovery and recovered state | recovery suite | `feat: add router v2 position recovery` |
| 9 | Tasks 1–8 | Router-seam adversarial hardening | security suite | `test: harden strategy router v2 boundary` |
| 10 | Tasks 1–9 | complete real-adapter mock integration and evidence map | integration/full regression | `docs: certify strategy router v2` |

No task may begin before the previous task's independent review reports no unresolved Critical or Important finding.

---

## Task 1: StrategyRouterV2 Interface and Constructor Invariants

### Files

- Create: `src/v2/interfaces/IStrategyRouterV2.sol`
- Create: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Configuration.t.sol`
- Create: `test/v2/mocks/RouterBoundVaultMockV2.sol`
- Create: `test/v2/mocks/RouterBindingAdapterMockV2.sol`

### Interfaces consumed

- `AllocationV2`, `RebalanceLimitsV2`, and `RiskConfigurationV2` from `src/v2/types/SignalVaultTypesV2.sol`.
- `SignalVaultHashesV2.computeRiskConfigurationHash` and `computeRouterConfigHash`.
- Frozen `IStrategyAdapterV2` for asset and position identity.
- Existing concrete adapter public `router()` getters through a local `IRouterBoundAdapterV2` check interface.
- `IRouterBoundVaultV2.vaultOwner()` from the new test mock and future SignalVaultV2.

The narrow binding checks are exactly:

```solidity
interface IRouterBoundAdapterV2 {
    function router() external view returns (address);
}

interface IRouterBoundVaultV2 {
    function vaultOwner() external view returns (address);
}
```

### Interface produced

`IStrategyRouterV2` defines the exact enums, structs, getters, preview, rebalance, withdrawal, recovery, and pause selectors frozen in the design. The concrete contract additionally produces one-time `configureAdapters`, `configureRisk`, and `bindVault` selectors.

### Steps

- [ ] **Write the focused failing configuration test.**

```solidity
function testBindFreezesExactIdentitiesAndConfigHash() external {
    router.configureAdapters(address(upshift), address(idle));
    router.configureRisk(validRisk());
    RouterBoundVaultMockV2 vault = new RouterBoundVaultMockV2(owner);
    router.bindVault(address(vault));

    bytes32 expectedRisk = SignalVaultHashesV2.computeRiskConfigurationHash(validRisk());
    bytes32 expectedConfig = SignalVaultHashesV2.computeRouterConfigHash(
        block.chainid,
        address(vault),
        address(router),
        address(asset),
        address(upshift),
        address(idle),
        router.capabilityProfile(),
        expectedRisk,
        1
    );

    assertEq(router.riskConfigurationHash(), expectedRisk);
    assertEq(router.routerConfigHash(), expectedConfig);
    assertTrue(router.configurationFrozen());
}
```

Add concrete tests for zero asset, zero prospective owner, unauthorized configuration, zero/duplicate adapters, wrong adapter asset, wrong adapter Router binding, adapter ordering, configuration repetition, risk before/after boundaries `0`, `10_000`, and `10_001`, `allocationToleranceBps > minimumAllocationChangeBps`, bind before both configurations, zero Vault, Vault owner mismatch, second bind, and every post-bind mutation.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Configuration.t.sol -vvv
```

Expected failure: compilation fails because `IStrategyRouterV2`, `StrategyRouterV2`, and the configuration mocks do not exist. An environment or dependency failure does not count as RED.

- [ ] **Implement the minimal interface and one-time configuration.**

Use constructor `(IERC20 asset_, address vaultOwner_)`. Store both as immutable. `configureAdapters` is callable only by `vaultOwner`, stores unique nonzero adapter addresses, requires each `asset()` to equal the Router asset, requires each existing public `router()` getter to equal `address(this)`, and requires Idle `positionToken()` to equal the underlying. `configureRisk` validates all BPS values and stores exactly one `RiskConfigurationV2`. `bindVault` verifies both configurations, requires `vault.vaultOwner() == vaultOwner`, stores Vault once, computes both Gate 4A hashes in frozen field order, and permanently closes every configuration selector.

Define `capabilityProfile()` as `keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1")` and `routerConfigVersion()` as `1`. Do not set any token approval.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Configuration.t.sol -vvv
```

Expected result: every configuration and hash test passes.

- [ ] **Run Task 1 sensitivity checks.**

Temporarily remove the adapter `router()` equality check and require `testRejectsAdapterBoundToAnotherRouter` to fail. Restore it. Temporarily swap Upshift and Idle arguments in `computeRouterConfigHash` and require `testBindFreezesExactIdentitiesAndConfigHash` to fail. Restore the exact field order. Do not commit either mutation.

- [ ] **Run Task 1 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/ResultHashV2.t.sol -vvv
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe build
```

- [ ] **Review the complete Task 1 diff.**

Require: no frozen file changed; no P0 file changed; no approval exists; every config identity is frozen; the deployment cycle remains Router → adapters → Vault → bind; all interface types and errors are defined; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 1 review gate.**

An independent reviewer compares the diff against the design and Gate 4A hash field order. Resolve every Critical or Important finding and rerun the affected GREEN and regression commands before proceeding.

- [ ] **Commit Task 1.**

```powershell
git add -- `
  src/v2/interfaces/IStrategyRouterV2.sol `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Configuration.t.sol `
  test/v2/mocks/RouterBoundVaultMockV2.sol `
  test/v2/mocks/RouterBindingAdapterMockV2.sol
git commit -m "feat: configure strategy router v2"
```

---

## Task 2: NAV and Allocation Views

### Files

- Modify: `src/v2/StrategyRouterV2.sol`
- Modify: `src/v2/interfaces/IStrategyRouterV2.sol` only if the Task 1 implementation omitted a documented return name; no selector may change
- Create: `test/v2/StrategyRouterV2Accounting.t.sol`
- Create: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`

### Interfaces consumed

- Adapter `totalAssets`, `grossAssets`, `availableLiquidity`, `positionShares`, and `positionToken`.
- Underlying `balanceOf` for Router and Upshift-adapter direct underlying.

### Interface produced

- `totalAssets`, `grossAssets`, `availableLiquidity`, `allocation`, and `strategyState`.
- Instrumented adapter setters `setPositionValues(uint256 net,uint256 gross,uint256 liquidity,uint256 shares)`, `setStatus(bool deposits,bool withdrawals)`, `setPreviewReverts(bool)`, `setDepositPreview(uint256 assets,uint256 shares,uint256 immediateNet)`, `setRedeemPreview(uint256 shares,uint256 gross,uint256 net)`, `setDepositExecution(uint256 routerDebit,uint256 adapterCredit,uint256 sharesMinted,uint256 returnedShares)`, and `setWithdrawalExecution(uint256 adapterDebit,uint256 routerCredit,uint256 returnedAssets)`.
- Instrumented adapter getters `depositCallCount`, `withdrawLiquidCallCount`, `redeemCallCount`, `redeemAllCallCount`, `stateChangingCallCount`, `previewDepositCallCount`, `previewRedeemCallCount`, `lastDepositAssets`, `lastDepositMinSharesOut`, `lastWithdrawLiquidAssets`, `lastRedeemShares`, and `lastRedeemMinAssetsOut`, plus `resetCallCounters()`.

### Steps

- [ ] **Write the focused failing accounting test.**

```solidity
function testNetGrossAndDirectBufferUseDistinctUnits() external {
    asset.mint(address(router), 5);
    idle.setPositionValues(20, 20, 20, 20);
    asset.mint(address(upshift), 7);
    upshift.setPositionValues(95, 99, 95, 10_000);

    AllocationSnapshotV2 memory snapshot = router.allocation();
    assertEq(router.totalAssets(), 5 + 20 + 7 + 95);
    assertEq(router.grossAssets(), 5 + 20 + 7 + 99);
    assertEq(snapshot.routerDirectAssets, 5);
    assertEq(snapshot.upshiftDirectAssets, 7);
    assertEq(snapshot.upshiftPositionNetAssets, 95);
    assertEq(snapshot.upshiftPositionShares, 10_000);
}
```

Add tests for zero NAV, Router donation, Idle donation, Upshift direct donation, recovered-state direct accounting, adapter total below observed direct balance, net/gross separation, liquidity without double counting, protocol shares never added as assets, unavailable status, preview revert fail-closed behavior, and `type(uint256).max` Idle status never being added as an asset value.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Accounting.t.sol -vvv
```

Expected failure: accounting selectors are absent or still revert from Task 1 stubs.

- [ ] **Implement minimal accounting views.**

Calculate Router direct from `asset.balanceOf(address(this))`. Calculate Upshift direct from `asset.balanceOf(upshiftAdapter)`. Require adapter-reported net and gross totals to be at least that direct amount before subtracting it into position-only values. Use net values for `totalAssets`, gross values only for `grossAssets`, and adapter `availableLiquidity` for liquidity. In recovered state, do not call Upshift normal views; count only observed direct underlying. `allocation()` returns zero BPS when total net NAV is zero and otherwise uses `Math.mulDiv(positionValue, 10_000, totalNetNAV)` with floor rounding.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Accounting.t.sol -vvv
```

- [ ] **Run Task 2 sensitivity checks.**

Temporarily add `positionShares()` to net NAV and require `testPositionSharesAreNotUnderlyingAssets` to fail. Restore the code. Temporarily omit Upshift direct underlying and require `testUpshiftDirectDonationIsCountedOnce` to fail. Restore the exact formula.

- [ ] **Run Task 2 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv
```

- [ ] **Review the complete Task 2 diff.**

Require: gross is never consumed by net accounting; direct underlying appears exactly once; recovered-state views never call disabled Upshift operations; no state mutation was added; every subtraction has a checked ordering; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 2 review gate.**

An independent reviewer traces every accounting term to an observed token balance or frozen adapter view. Resolve every Critical or Important finding and rerun all Task 2 commands.

- [ ] **Commit Task 2.**

```powershell
git add -- `
  src/v2/interfaces/IStrategyRouterV2.sol `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Accounting.t.sol `
  test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "feat: add router v2 accounting views"
```

---

## Task 3: Strict Differential Rebalance Plan Computation

### Files

- Modify: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Planning.t.sol`
- Modify: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`

### Interfaces consumed

- Task 2 `AllocationSnapshotV2`.
- Adapter composed `previewDeposit`, share-based `previewRedeem`, `availableLiquidity`, and status.
- Frozen `AllocationV2` and `RebalanceLimitsV2`.

### Interface produced

- `previewRebalance(target, limits)`.
- One shared internal `_computeRebalancePlan(target, limits)` used later by `rebalance`.
- Instrumented deterministic preview curves and per-selector call counters.

### Steps

- [ ] **Write the focused failing planning test.**

```solidity
function testDirectBufferSatisfiesIdleDeficitWithoutUpshiftRedemption() external {
    asset.mint(address(router), 20);
    idle.setPositionValues(30, 30, 30, 30);
    upshift.setPositionValues(50, 50, 50, 50);

    RebalancePlanV2 memory plan = router.previewRebalance(
        AllocationV2({upshiftBps: 5_000, firelightBps: 0, sparkdexBps: 0, idleBps: 5_000}),
        validLimits()
    );

    assertTrue(plan.feasible);
    assertEq(plan.idleDepositAssets, 20);
    assertEq(plan.upshiftSharesToRedeem, 0);
    assertEq(plan.targetIdleAssets + plan.targetUpshiftAssets, plan.projectedTotalAssetsAfter);
}
```

Add tests for exact no-op, initial two-deposit buffer allocation, unsupported weights, invalid signed limits, change below minimum, cooldown blocker, Upshift unavailable, recovered target, increase candidate, decrease candidate, only one refinement, zero preview, candidate above held shares, solver nonconvergence, strict liquidity deficit, projected post-NAV fee reserve, target remainder, six-decimal smallest amounts, and values near `uint256` multiplication limits.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Planning.t.sol -vvv
```

Expected failure: `previewRebalance` or shared plan computation has no behavior.

- [ ] **Implement the bounded plan computation.**

Validate `firelightBps == 0`, `sparkdexBps == 0`, and the two supported weights sum to `10_000`. Validate each signed maximum is no greater than its frozen maximum. Exclude Router and adapter direct underlying from realized adapter target balances while retaining them in NAV and available funding. Apply direct buffer to deficits before any strategy withdrawal. Compute targets from projected post-execution net NAV and assign division remainder to Upshift.

For decreases, estimate shares with `Math.mulDiv(heldShares, requiredNetReduction, currentPositionNet, Math.Rounding.Ceil)`, preview candidate output and remaining shares, and allow one proportional refinement. For increases, call composed `previewDeposit` for the initial candidate and one refinement, recomputing projected post-NAV and target each time. Return a named `RebalanceBlockerV2` rather than a partial plan. Make every loop bound a literal or constant equal to `2`.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Planning.t.sol -vvv
```

- [ ] **Run Task 3 sensitivity checks.**

Temporarily exclude Router direct assets from deficit funding and require `testDirectBufferSatisfiesIdleDeficitWithoutUpshiftRedemption` to fail. Restore it. Temporarily return `feasible = true` after the first nonconvergent candidate and require `testNonconvergentSecondCandidateIsInfeasible` to fail. Restore strict feasibility.

- [ ] **Run Task 3 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe build
```

- [ ] **Review the complete Task 3 diff.**

Require: preview and future execution have one plan function; target sum equals projected post-NAV; direct buffer is first; no best-effort flag exists; every loop is bounded; no multiplication can overflow; no state mutation occurs in preview; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 3 review gate.**

An independent reviewer manually recomputes at least one increase, one decrease, the direct-buffer example, and one rounding edge from test inputs. Resolve every Critical or Important finding and rerun Task 3.

- [ ] **Commit Task 3.**

```powershell
git add -- `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Planning.t.sol `
  test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "feat: plan differential rebalance v2"
```

---

## Task 4: Idle-Side Differential Execution

### Files

- Modify: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Execution.t.sol`
- Modify: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`

### Interfaces consumed

- Task 3 `RebalancePlanV2`.
- Idle adapter `withdrawLiquid`, `deposit`, direct one-to-one previews, and actual underlying balance.
- Underlying allowance and balance interfaces.

### Interface produced

- `rebalance(executionId, target, limits, fundingAssets)` with initial direct-buffer/Idle execution.
- Internal exact `_depositIdle` and `_withdrawIdle` helpers used through the Router's external interface.

### Steps

- [ ] **Write the focused failing Idle execution test.**

```solidity
function testDirectBufferMovesOnlyIntoIdleAndLeavesNoAllowance() external {
    seedPositions({routerDirect: 20, idleNet: 30, upshiftNet: 50});
    vm.prank(vault);
    router.rebalance(EXECUTION_ID, halfAndHalf(), validLimits(), 20);

    assertEq(idle.lastDepositAssets(), 20);
    assertEq(idle.depositCallCount(), 1);
    assertEq(idle.withdrawCallCount(), 0);
    assertEq(upshift.stateChangingCallCount(), 0);
    assertEq(asset.allowance(address(router), address(idle)), 0);
}
```

Add tests for 100% Idle initial allocation, exact temporary approval, funding declaration no greater than entry balance, existing Router donation not misreported as funding, Idle under-receipt, Idle over-report, Idle over-debit, protocol revert rollback, no-op zero calls, and direct-buffer movement that makes no Upshift call.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Execution.t.sol --match-test 'test.*(Idle|DirectBuffer|Funding).*' -vvv
```

Expected failure: `rebalance` has no state-changing execution path.

- [ ] **Implement minimal Idle-side execution.**

Recompute the plan inside `rebalance`; reject an infeasible plan before mutation. Require Router entry underlying to be at least `fundingAssets`. For Idle deposit, force-approve exactly the plan amount, call `idle.deposit(assets, assets)`, reset approval to zero, require allowance zero, require Router debit equals assets, require Idle underlying increase equals assets, and require returned shares equal the measured increase. For Idle withdrawal, call only the plan amount and require returned output and Router credit equal that amount. Do not add Upshift mutation beyond zero-call validation in this task.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Execution.t.sol --match-test 'test.*(Idle|DirectBuffer|Funding).*' -vvv
```

- [ ] **Run Task 4 sensitivity checks.**

Temporarily trust the Idle return without checking Router credit and require `testIdleOverReportWithoutTransferReverts` to fail. Restore the check. Temporarily leave the Idle allowance nonzero and require `testDirectBufferMovesOnlyIntoIdleAndLeavesNoAllowance` to fail. Restore cleanup.

- [ ] **Run Task 4 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/IdleAdapterV2.t.sol -vvv
```

- [ ] **Review the complete Task 4 diff.**

Require: exact approvals; Router and adapter delta checks; no Upshift full unwind; no arbitrary receiver; no cooldown update before final postconditions; no frozen adapter change; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 4 review gate.**

An independent reviewer traces every Idle asset movement and verifies rollback on each failure. Resolve every Critical or Important finding and rerun Task 4.

- [ ] **Commit Task 4.**

```powershell
git add -- `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Execution.t.sol `
  test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "feat: execute idle router deltas v2"
```

---

## Task 5: Upshift-Side Differential Execution

### Files

- Modify: `src/v2/StrategyRouterV2.sol`
- Modify: `test/v2/StrategyRouterV2Execution.t.sol`
- Modify: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`

### Interfaces consumed

- Upshift adapter `previewDeposit`, `previewRedeem`, `withdrawLiquid`, `deposit`, `redeem`, `positionShares`, `totalAssets`, and `availableLiquidity`.
- Task 4 exact approval and delta helpers.

### Interface produced

- Complete strict differential `rebalance` for Upshift increase and decrease.
- Per-operation preview-derived `minSharesOut` and `minAssetsOut`.

### Steps

- [ ] **Write the focused failing Upshift execution test.**

```solidity
function testUpshiftDecreaseRedeemsOnlyPlannedSharesAndDepositsDeltaToIdle() external {
    seedAllocation({idleNet: 20, upshiftNet: 80, upshiftShares: 80});
    uint256 sharesBefore = upshift.positionShares();

    vm.prank(vault);
    router.rebalance(EXECUTION_ID, target70Idle30Upshift(), validLimits(), 0);

    assertEq(upshift.redeemCallCount(), 1);
    assertLt(upshift.lastRedeemShares(), sharesBefore);
    assertEq(upshift.depositCallCount(), 0);
    assertEq(idle.depositCallCount(), 1);
    assertWithinTolerance(router.allocation(), 7_000, 3_000);
}
```

Add tests for Upshift increase moving only the delta, Idle withdrawal before Upshift deposit, Upshift direct sweep before LP redemption, no full unwind, two deposit candidates maximum, four protocol previews maximum, fee changes `0/25/50/100/1_000`, share rounding, min-share boundary, min-asset boundary, under-delivery, over-report, share-delta mismatch, Router debit mismatch, allowance cleanup, no LP allowance, paused protocol, zero liquidity, binding drift, preview revert, zero-net position, and atomic failure after one refinement.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Execution.t.sol --match-test 'test.*(Upshift|Fee|Preview|Binding).*' -vvv
```

Expected failure: Upshift plan fields are not executed.

- [ ] **Implement minimal Upshift-side execution.**

Execute only the recomputed final plan. Sweep the plan's Upshift direct amount with `withdrawLiquid` and reconcile Router credit. For increase, withdraw only the required Idle deficit, force-approve UpshiftAdapter for the exact final candidate, call `deposit(candidateAssets, previewDerivedMinShares)`, reset allowance, and reconcile Router debit plus actual position-share increase. For decrease, call `redeem(candidateShares, previewDerivedMinAssets)`, reconcile Router credit and actual share decrease, then deposit only final Idle deficit. Never call `redeemAll` during ordinary rebalance. Re-read the final position and net NAV after mutation; do not infer them solely by subtracting preview output.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Execution.t.sol -vvv
```

- [ ] **Run Task 5 sensitivity checks.**

Temporarily replace partial Upshift redemption with `redeemAll(0)` and require `testUpshiftDecreaseRedeemsOnlyPlannedSharesAndDepositsDeltaToIdle` to fail. Restore differential redemption. Temporarily pass zero as `minAssetsOut` and require `testUpshiftRedeemUsesPreviewDerivedMinimum` to fail. Restore the signed preview minimum.

- [ ] **Run Task 5 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv
```

- [ ] **Review the complete Task 5 diff.**

Require: one strategic withdrawal side; no unnecessary full unwind; direct buffer precedes strategy withdrawal; no more than two candidates; every adapter call has Router and position reconciliation; live fee only; exact approval zero afterward; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 5 review gate.**

An independent reviewer compares preview values, call minimums, actual deltas, retained shares, and post-target values for both directions. Resolve every Critical or Important finding and rerun Task 5.

- [ ] **Commit Task 5.**

```powershell
git add -- `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Execution.t.sol `
  test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "feat: execute upshift router deltas v2"
```

---

## Task 6: Loss Accounting and Minimum Rebalance Interval

### Files

- Modify: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Risk.t.sol`
- Modify: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`

### Interfaces consumed

- Frozen `RiskConfigurationV2` and signed `RebalanceLimitsV2`.
- Task 5 measured previews, outputs, allocation, and post-NAV.

### Interface produced

- Preview-deviation, minimum-post-NAV, maximum-loss, allocation-tolerance, minimum-change, and cooldown enforcement.
- `lastRebalanceTimestamp` update after successful nonzero movement only.

### Steps

- [ ] **Write the focused failing risk test.**

```solidity
function testLossBoundaryUsesPreNetNavAndTenThousandDenominator() external {
    seedNetNav(1_000_000);
    configureExecutionLoss(10_000);
    RebalanceLimitsV2 memory limits = validLimits();
    limits.maximumRebalanceLossBps = 100;

    vm.prank(vault);
    router.rebalance(EXECUTION_ID, changedTarget(), limits, 0);
    assertEq(router.totalAssets(), 990_000);

    configureExecutionLoss(10_001);
    vm.prank(vault);
    vm.expectRevert(StrategyRouterV2.RebalanceLossExceeded.selector);
    router.rebalance(OTHER_EXECUTION_ID, changedTarget(), limits, 0);
}
```

Add boundary tests below/at/above for all three signed BPS limits, `minimumPostNAV`, `preNAV == 0`, cooldown first execution, exact earliest timestamp, one second early, no-op timestamp, below-minimum-change revert, withdrawals bypassing interval, recovery bypassing interval, preview deviation per call, allocation tolerance per strategy, fee/rounding loss, and full-width `Math.mulDiv` inputs.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Risk.t.sol -vvv
```

Expected failure: economic postconditions and timestamp rules are absent or incomplete.

- [ ] **Implement exact economic controls.**

Enforce signed maxima no greater than frozen maxima before mutation. For each adapter call, compute adverse deviation as `Math.mulDiv(max(preview-actual,0), 10_000, max(preview,1))`. After all calls, require `postNAV >= minimumPostNAV`; compute actual loss only when `postNAV < preNAV`; compute maximum loss with floor `Math.mulDiv(preNAV, signedLossBps, 10_000)`; enforce Idle and Upshift target deviations independently against post-NAV. Require `block.timestamp >= lastRebalanceTimestamp + minimumRebalanceInterval` for nonzero movement and update the timestamp only after every postcondition passes.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Risk.t.sol -vvv
```

- [ ] **Run Task 6 sensitivity checks.**

Temporarily reverse one signed-to-frozen inequality and require its above-frozen test to fail. Restore it. Temporarily calculate loss against gross NAV and require `testLossUsesNetNavNotGrossTelemetry` to fail. Restore net loss accounting.

- [ ] **Run Task 6 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/ResultHashV2.t.sol -vvv
```

- [ ] **Review the complete Task 6 diff.**

Require: every unit and denominator matches the design; comparison directions are stricter; no overflow-prone product exists; cooldown excludes withdrawal/recovery; timestamp writes occur after final checks; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 6 review gate.**

An independent reviewer recomputes each boundary case and checks every signed/frozen inequality direction. Resolve every Critical or Important finding and rerun Task 6.

- [ ] **Commit Task 6.**

```powershell
git add -- `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Risk.t.sol `
  test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "feat: enforce router v2 economic limits"
```

---

## Task 7: Vault Withdrawal Path

### Files

- Modify: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Withdrawal.t.sol`
- Modify: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`

### Interfaces consumed

- `withdrawLiquid`, `previewRedeem`, `redeem`, `redeemAll`, `availableLiquidity`, and exact token balances.
- Bound immutable-in-practice Vault receiver.

### Interface produced

- `withdrawToVault(uint256 assets)` exact waterfall.
- `withdrawAllToVault()` normal full close.

### Steps

- [ ] **Write the focused failing withdrawal test.**

```solidity
function testWithdrawalUsesFeeFreeTiersBeforeFinalUpshiftDeficit() external {
    seedRouterDirect(10);
    seedIdle(20);
    seedUpshiftDirect(5);
    seedUpshiftPosition({net: 100, shares: 100});
    uint256 vaultBefore = asset.balanceOf(vault);

    vm.prank(vault);
    uint256 delivered = router.withdrawToVault(40);

    assertEq(delivered, 40);
    assertEq(asset.balanceOf(vault) - vaultBefore, 40);
    assertEq(upshift.lastRedeemShares(), 5);
    assertEq(upshift.redeemCallCount(), 1);
}
```

Add Router-only, Idle-only, Upshift-direct-only, final LP deficit, over-redemption retained, insufficient aggregate liquidity, paused fee-free success, paused LP-required revert, zero limit, preview revert, zero-net position, two-candidate share bound, exact Vault credit, Router over-debit, adapter under-delivery, full close, full-close dust, residual share rejection, residual underlying rejection, and no cooldown impact.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Withdrawal.t.sol -vvv
```

Expected failure: withdrawal selectors are absent or have no waterfall behavior.

- [ ] **Implement exact withdrawal and full close.**

Precheck aggregate immediate liquidity. Consume Router direct, Idle `withdrawLiquid`, Upshift direct `withdrawLiquid`, and only then LP redemption. Estimate LP shares with a proportional ceil candidate and one refinement; require preview net covers the deficit and remains within live available liquidity; derive the call minimum from frozen preview-deviation BPS. Reconcile each Router credit. Transfer exactly requested assets to the bound Vault, then require Router debit and Vault credit equal the requested amount. Retain over-redemption as Router direct.

For full close, call Idle `redeemAll`, call Upshift `redeemAll` only when its position shares are nonzero, derive its minimum from live preview, require final normal adapter underlying and shares are zero, and transfer every Router underlying unit to the Vault with exact deltas.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Withdrawal.t.sol -vvv
```

- [ ] **Run Task 7 sensitivity checks.**

Temporarily redeem Upshift before Idle and require `testWithdrawalUsesFeeFreeTiersBeforeFinalUpshiftDeficit` to fail. Restore the waterfall. Temporarily omit the Vault credit check and require `testVaultUnderReceiptRevertsAtomically` to fail. Restore exact receiver reconciliation.

- [ ] **Run Task 7 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv
```

- [ ] **Review the complete Task 7 diff.**

Require: fixed receiver; exact payment; fee-free order; LP only for deficit; no owner-level slippage interpretation; preview-derived protocol minimum; full close proves zero normal recoverable assets; interval untouched; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 7 review gate.**

An independent reviewer traces partial and full flows through every balance before/after pair. Resolve every Critical or Important finding and rerun Task 7.

- [ ] **Commit Task 7.**

```powershell
git add -- `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Withdrawal.t.sol `
  test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "feat: add router v2 vault withdrawals"
```

---

## Task 8: Upshift Recovery Integration

### Files

- Modify: `src/v2/StrategyRouterV2.sol`
- Create: `test/v2/StrategyRouterV2Recovery.t.sol`
- Modify: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`

### Interfaces consumed

- Frozen `IStrategyRecoveryV2.recoverPosition(vault)`.
- Adapter `positionToken`, `positionShares`, `withdrawLiquid`, and direct underlying balance.

### Interface produced

- `setExecutionPaused`.
- `recoverAdapterPosition` with Vault-fixed receiver.
- Permanent `UpshiftRecovered` accounting and execution behavior.

### Steps

- [ ] **Write the focused failing recovery test.**

```solidity
function testPausedRecoveryTransfersExactLpToVaultAndPermanentlyDisablesTarget() external {
    seedUpshiftPosition({net: 100, shares: 100});
    vm.startPrank(vault);
    router.setExecutionPaused(true);
    uint256 recovered = router.recoverAdapterPosition();
    vm.stopPrank();

    assertEq(recovered, 100);
    assertEq(positionToken.balanceOf(vault), 100);
    assertEq(uint256(router.strategyState()), uint256(RouterStateV2.UpshiftRecovered));

    vm.prank(vault);
    vm.expectRevert(StrategyRouterV2.RecoveredTargetForbidden.selector);
    router.rebalance(EXECUTION_ID, halfAndHalf(), validLimits(), 0);
}
```

Add onlyVault pause, onlyVault recovery, recovery requires pause, zero position, fixed receiver, adapter/receiver LP deltas, adapter over-report, receiver under-credit, second recovery, paused preview failure, binding getter failure, direct underlying after recovery, recovered-state net/gross/liquidity, recovered-state withdrawal, no protocol call after recovery, cooldown bypass, event fields, and LP donation after recovery documented as non-recoverable.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Recovery.t.sol -vvv
```

Expected failure: pause/recovery selectors and recovered-state accounting are absent.

- [ ] **Implement minimal recovery state.**

Allow the bound Vault to set local execution pause. Require pause, non-recovered state, and nonzero LP shares before recovery. Snapshot adapter and Vault position-token balances, call `recoverPosition(vault)`, require both exact deltas and return equality, then set `upshiftRecovered` permanently. In recovered accounting, read only underlying direct balance at the Upshift adapter. Permit `withdrawLiquid` for that direct balance. Reject every rebalance target and every normal Upshift call after recovery. Do not add a second receiver or rescue selector.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Recovery.t.sol -vvv
```

- [ ] **Run Task 8 sensitivity checks.**

Temporarily pass `msg.sender` instead of the stored Vault to `recoverPosition` and require `testRecoveryReceiverIsAlwaysBoundVault` to fail. Restore the fixed receiver. Temporarily allow a nonzero Upshift target after recovery and require the focused recovered-target test to fail. Restore permanent rejection.

- [ ] **Run Task 8 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/UpshiftAdapterV2Security.t.sol -vvv
```

- [ ] **Review the complete Task 8 diff.**

Require: recovery is paused, Vault-only, receiver-fixed, delta-measured, single-use, and not reported as underlying; direct underlying remains withdrawable; no recovered normal protocol call exists; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 8 review gate.**

An independent reviewer follows state transitions and verifies no path restores Upshift capability or chooses another receiver. Resolve every Critical or Important finding and rerun Task 8.

- [ ] **Commit Task 8.**

```powershell
git add -- `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Recovery.t.sol `
  test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "feat: add router v2 position recovery"
```

---

## Task 9: Adversarial Router Boundary Security

### Files

- Modify: `src/v2/StrategyRouterV2.sol` only for a demonstrated Router-boundary defect
- Create: `test/v2/StrategyRouterV2Security.t.sol`
- Create: `test/v2/mocks/ReentrantRouterAssetV2.sol`
- Modify: `test/v2/mocks/InstrumentedStrategyAdapterV2.sol`
- Reuse without modification: all Gate 4B adversarial mocks

### Interfaces consumed

- Full Router runtime interface.
- Existing malicious adapter, skimming token, adversarial debit token, false-return token, reentrant token, execution protocol mock, and reentrant protocol mock.

### Interface produced

- No new production selector.
- Router-seam threat coverage proving lower-layer checks are not trusted as a substitute for Router reconciliation.

### Steps

- [ ] **Write the focused failing adversarial test.**

```solidity
function testAdapterOverReportWithoutRouterCreditRevertsAtomically() external {
    malicious.setReportedValue(100);
    bytes32 stateBefore = snapshotStateHash();

    vm.prank(vault);
    vm.expectRevert(StrategyRouterV2.AdapterDeltaMismatch.selector);
    router.withdrawToVault(100);

    assertEq(snapshotStateHash(), stateBefore);
}
```

Add non-Vault rebalance/withdraw/pause/recovery, underlying callback, adapter callback, protocol callback, false-return transfer, Router over-debit, Router under-debit, Vault over-credit, Vault under-credit, malicious total/gross/liquidity, deposit fake shares, redemption fake assets, binding drift, paused status, preview revert, zero liquidity, zero-net position, reentrant recovery, arbitrary selector probe, arbitrary receiver probe, and no-`delegatecall` bytecode scan.

Map each threat explicitly:

| Threat | Adapter layer | Router layer |
|---|---|---|
| fee-on-transfer/skimming | adapter input/output deltas | Router debit/credit and Vault credit |
| over-debit/receiver over-credit | adapter detects its local side | Router independently detects its side |
| false return | SafeERC20 in adapter | SafeERC20 and measured Router/Vault deltas |
| malicious adapter over-report | not prevented by malicious test adapter | return-versus-balance reconciliation |
| callback/reentrancy | adapter guard | Router guard and Vault-only identity |
| binding drift | Upshift adapter checks live bindings | Router state and post-operation deltas |
| pause/zero liquidity/preview revert | adapter fails closed | plan infeasible or exact withdrawal revert |
| recovered adapter | adapter disables normal operations | Router forbids targets and protocol calls |

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Security.t.sol -vvv
```

Expected failure: at least one Router-boundary adversarial case demonstrates a missing Router guard; a test that fails only because its mock is malformed does not count.

- [ ] **Implement only the demonstrated Router-boundary fixes.**

Add no new selector. Preserve the design formulas. Reconcile the missing Router-side delta, callback state, access check, or final postcondition identified by RED. If all planned production guards already reject a threat, keep the passing test as coverage and do not add redundant production code.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Security.t.sol -vvv
```

- [ ] **Run Task 9 mutations.**

Perform separate compilable mutations removing `onlyVault`, removing `nonReentrant`, trusting an adapter return without Router delta, permitting an arbitrary recovery receiver, and skipping post-NAV loss. For each mutation record the exact named test that fails, then restore the branch to the reviewed source before the next mutation. Commit no mutation.

- [ ] **Run Task 9 regressions.**

```powershell
D:\xhy\tools\foundry\forge.exe fmt --check
D:\xhy\tools\foundry\forge.exe build
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test -vvv
```

- [ ] **Review the complete Task 9 diff.**

Require: every threat crosses the Router interface; no test relies only on a self-reporting mock; no security assertion was weakened; no new production authority exists; all mutations were restored; `git diff --check` exits `0`.

- [ ] **Pass the independent Task 9 review gate.**

An independent security reviewer inspects production source and all Router tests, reproduces the critical mutations, and reports Critical/Important/Minor findings. Resolve every Critical or Important finding and rerun all Task 9 commands.

- [ ] **Commit Task 9.**

```powershell
git add -- `
  src/v2/StrategyRouterV2.sol `
  test/v2/StrategyRouterV2Security.t.sol `
  test/v2/mocks/ReentrantRouterAssetV2.sol `
  test/v2/mocks/InstrumentedStrategyAdapterV2.sol
git commit -m "test: harden strategy router v2 boundary"
```

If no production fix was required, omit `src/v2/StrategyRouterV2.sol` from staging.

---

## Task 10: Full Integration and Documentation

### Files

- Create: `test/v2/StrategyRouterV2Integration.t.sol`
- Create: `docs/superpowers/coverage/2026-07-14-strategy-router-v2.json`
- Modify: `README.md`
- Modify: `src/v2/StrategyRouterV2.sol` only for a defect first reproduced by the integration RED test

### Interfaces consumed

- Final Router interface and implementation.
- Real `IdleAdapterV2` and `UpshiftAdapterV2` production contracts.
- `FeeAwareUpshiftVaultMock`, `ExecutionUpshiftVaultMock`, and actual ERC-20/LP balances.

### Interface produced

- No new production selector.
- One canonical Router-only integration suite and a requirement-to-test evidence manifest.
- Accurate public repository status without claiming SignalVaultV2 or Coston2 V2 deployment.

### Steps

- [ ] **Write the canonical integration test with an intentional final RED assertion.**

```solidity
function testCanonicalRouterLifecycleThroughRealAdapters() external {
    deployRouterAndRealAdapters();
    bindConfiguration();
    fundRouter(1_000_000);
    executeInitialAllocation(5_000, 5_000);
    executeUpshiftIncrease(6_000, 4_000);
    executeUpshiftDecrease(4_000, 6_000);
    withdrawPartialToVault();
    withdrawAllToVault();
    assertFinalReconciliation();
    fail("RED: replace with final lifecycle evidence assertions");
}
```

The final assertions must cover frozen config hash, initial direct-buffer allocation, exact no-op zero calls, strict increase, strict decrease, dynamic fee change, paused fee-free withdrawal, partial withdrawal, full withdrawal, final zero recoverable underlying, zero LP shares, zero Router-to-adapter allowances, no LP allowance, and privacy-safe event fields.

- [ ] **Run the exact RED command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Integration.t.sol -vvv
```

Expected failure: the lifecycle reaches the intentional final RED assertion. Any earlier failure must be diagnosed and fixed with its own focused regression before removing the assertion.

- [ ] **Replace the intentional assertion with exact lifecycle evidence checks.**

Use production Router and production adapters, not an adapter self-reporting substitute. Assert transaction-equivalent state at every phase, compare preview plan to execution event, and prove final balances and allowances. A production fix is permitted only after the integration test isolates a defect not already covered by focused suites.

- [ ] **Create the exact coverage manifest.**

The JSON contains one entry for every numbered security invariant and every state-matrix row in the design. Each entry names a concrete Foundry file and test function. All integer evidence values are decimal strings. The manifest status is `complete` only when every referenced symbol exists and the full Router suite passes.

- [ ] **Update the public README status.**

Mark StrategyRouterV2 implemented and locally verified only after all tests pass. Keep SignalVaultV2, V2 deployment, Anvil V2 E2E, and Coston2 V2 deployment as not started or not deployed. Preserve the testnet, unaudited, no-real-funds warnings and the recovered-adapter LP donation limitation.

- [ ] **Run the exact GREEN command.**

```powershell
D:\xhy\tools\foundry\forge.exe test --match-path test/v2/StrategyRouterV2Integration.t.sol -vvv
```

- [ ] **Run final focused and full verification from a clean build.**

```powershell
npm test
npm run typecheck
D:\xhy\tools\foundry\forge.exe clean
D:\xhy\tools\foundry\forge.exe fmt --check
D:\xhy\tools\foundry\forge.exe build
D:\xhy\tools\foundry\forge.exe build --sizes
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test -vvv
npm test --workspace local-signer
npm run typecheck --workspace local-signer
```

Record every exit code and exact Vitest/Foundry test count.

- [ ] **Audit scope and secrets.**

```powershell
git diff --exit-code 5551e68d0c00fbcf435e289d7dc03b64e4802a8f -- `
  src/v2/interfaces/IStrategyAdapterV2.sol `
  src/v2/interfaces/IStrategyRecoveryV2.sol `
  src/v2/interfaces/IUpshiftVaultV2.sol `
  src/v2/adapters/IdleAdapterV2.sol `
  src/v2/adapters/UpshiftAdapterV2.sol
git diff --check
git status --short
git ls-files | Select-String -Pattern '(^|/|\\)\.env($|\.)|private[-_]?key|secret' -CaseSensitive:$false
```

Require no frozen dependency diff, no P0 source/test diff, no `.env` or secret, and only the plan-authorized Router files.

- [ ] **Pass the final independent Router branch review gate.**

The reviewer compares the complete branch against baseline `5551e68`, the design, this ten-task plan, every task commit, and all mutation evidence. The gate passes only with no unresolved Critical or Important finding and fresh reproduction of the Router-focused and full Foundry suites.

- [ ] **Commit Task 10.**

```powershell
git add -- `
  test/v2/StrategyRouterV2Integration.t.sol `
  docs/superpowers/coverage/2026-07-14-strategy-router-v2.json `
  README.md
git commit -m "docs: certify strategy router v2"
```

If the integration RED test required a reviewed production fix, stage `src/v2/StrategyRouterV2.sol` in the same commit and explain the exact focused regression in the review record.

## Final implementation completion gate

The Router implementation is complete only when:

1. all ten task commits exist in order;
2. each task has preserved RED, GREEN, sensitivity/mutation, regression, and independent review evidence;
3. the final ABI matches the design without an extra selector;
4. every loop bound is explicit;
5. every BPS field has unit, denominator, comparison direction, and enforcement point;
6. every external mutation has before/after balance reconciliation;
7. Gate 4B frozen dependencies have zero diff from `5551e68`;
8. P0 source and tests have zero semantic diff;
9. all focused and full commands exit `0`;
10. no secret, deployment record, frontend, FTSO, FCC, or TEE change is present.

After this gate, stop. SignalVaultV2 remains a separately authorized next module.
