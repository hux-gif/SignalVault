# Gate 4B Upshift Adapters V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement independently deployed IdleAdapterV2 and fee-aware UpshiftAdapterV2 with conservative liquidity, exact approvals, and measured balance-delta reconciliation.

**Architecture:** A V2 adapter interface separates net accounting, gross telemetry, direct liquidity, preview composition, and state-changing execution. UpshiftAdapterV2 owns LP shares and underlying, validates live protocol bindings on every view/mutation, and never relies on a protocol return value for actual assets received.

**Tech Stack:** Solidity 0.8.27, Foundry, OpenZeppelin SafeERC20/ReentrancyGuard/Math, protocol-native Upshift ABI, TypeScript/Vitest for read-only live-semantics evidence.

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

## Frozen Adapter ABI

`src/v2/interfaces/IStrategyAdapterV2.sol` exposes exactly:

```solidity
interface IStrategyAdapterV2 {
    function asset() external view returns (address);
    function positionToken() external view returns (address);
    function positionShares() external view returns (uint256);
    function totalAssets() external view returns (uint256 netAssets);
    function grossAssets() external view returns (uint256 grossAssets_);
    function availableLiquidity() external view returns (uint256 netAssets);
    function protocolStatus() external view returns (
        bool depositsEnabled,
        bool withdrawalsEnabled,
        uint256 maxWithdrawalReferenceAmount,
        uint256 rawInstantRedemptionFee
    );
    function previewDeposit(uint256 assets)
        external view returns (uint256 shares, uint256 immediateNetValue);
    function previewRedeem(uint256 shares)
        external view returns (uint256 grossAssets_, uint256 netAssets);
    function withdrawLiquid(uint256 assets) external returns (uint256 assetsReceived);
    function deposit(uint256 assets, uint256 minSharesOut)
        external returns (uint256 sharesReceived);
    function redeem(uint256 shares, uint256 minAssetsOut)
        external returns (uint256 assetsReceived);
    function redeemAll(uint256 minAssetsOut)
        external returns (uint256 assetsReceived);
}
```

Emergency LP transfer is isolated in `IStrategyRecoveryV2.recoverPosition(address receiver) returns (uint256 sharesRecovered)` and is never callable through the normal adapter interface.

### Task 1: Adapter and Upshift Protocol Interfaces with Fee-Aware Mock

**Files:**
- Create: `src/v2/interfaces/IStrategyAdapterV2.sol`
- Create: `src/v2/interfaces/IStrategyRecoveryV2.sol`
- Create: `src/v2/interfaces/IUpshiftVaultV2.sol`
- Create: `test/v2/mocks/FeeAwareUpshiftVaultMock.sol`
- Create: `test/v2/mocks/MockLPTokenV2.sol`
- Create: `test/v2/UpshiftProtocolMockV2.t.sol`

**Interfaces:**
- Consumes: ERC-20 `asset`, LP-token balances, and the Gate 2 verified protocol-native ABI.
- Produces: the frozen adapter ABI above and `IUpshiftVaultV2` functions `asset`, `lpTokenAddress`, `previewDeposit`, `deposit`, `previewRedemption`, `instantRedeem`, `instantRedemptionFee`, `withdrawalsPaused`, and `maxWithdrawalAmount`.

- [ ] **Step 1: Write a failing configurable-protocol test.**

```solidity
function testMockAppliesDynamicFeeAndNoReturnInstantRedeem() external {
    protocol.setInstantFee(50);
    (uint256 shares,) = protocol.previewDeposit(address(asset), 10_000);
    (uint256 gross, uint256 net) = protocol.previewRedemption(shares, true);
    assertEq(net, gross - Math.mulDiv(gross, 50, 10_000));
    protocol.setInstantFee(100);
    (, uint256 changedNet) = protocol.previewRedemption(shares, true);
    assertLt(changedNet, net);
}
```

The mock also exposes setters for pause, reference-asset limit, asset address, LP-token address, preview inconsistency, deposit share rate, under-transfer, and reentrant callback. It counts `previewDeposit` and `previewRedemption` calls.

Add a table-driven fee test for raw fee values `0`, `25`, `50`, `100`, and `1_000`, always using floor `Math.mulDiv(gross, fee, 10_000)` and never a compiled 50-BPS constant.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/UpshiftProtocolMockV2.t.sol -vvv`

Expected: FAIL because V2 interfaces and mock contracts are absent.

- [ ] **Step 3: Implement the protocol surface and mock.**

Use the exact native signatures:

```solidity
function previewDeposit(address assetIn, uint256 amountIn)
    external view returns (uint256 shares, uint256 amountInReferenceTokens);
function deposit(address assetIn, uint256 amountIn, address receiverAddr)
    external returns (uint256 shares);
function previewRedemption(uint256 shares, bool isInstant)
    external view returns (uint256 assetsAmount, uint256 assetsAfterFee);
function instantRedeem(uint256 shares, address receiverAddr) external;
```

The mock fee formula is `net = gross - Math.mulDiv(gross, rawFee, 10_000)` with floor rounding. The mock's limit mode can reject by gross, net, or a separate internal reference amount so conservative adapter tests do not assume live semantics.

- [ ] **Step 4: Run GREEN and baseline build.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/UpshiftProtocolMockV2.t.sol -vvv`

Expected: all mock behavior tests PASS.

Run: `D:\xhy\tools\foundry\forge.exe build`

Expected: V2 interfaces compile without modifying P0.

- [ ] **Step 5: Review and commit Task 1.**

Review checklist: compare every native signature with integration ABI; keep fee configurable; ensure instant redemption has no return; expose call counters; ensure limit modes are explicit and loops absent.

```powershell
git diff --check
git add src/v2/interfaces test/v2/mocks/FeeAwareUpshiftVaultMock.sol test/v2/mocks/MockLPTokenV2.sol test/v2/UpshiftProtocolMockV2.t.sol
git commit -m "feat: define strategy adapter v2 interface"
```

Request independent review and resolve every Critical or Important finding before Task 2.

### Task 2: IdleAdapterV2

**Files:**
- Create: `src/v2/adapters/IdleAdapterV2.sol`
- Create: `test/v2/IdleAdapterV2.t.sol`

**Interfaces:**
- Consumes: `IStrategyAdapterV2`, IERC20, SafeERC20, immutable Router address.
- Produces: a one-to-one, only-Router adapter where direct underlying is position value and no external protocol approval exists.

- [ ] **Step 1: Write failing Idle tests.**

```solidity
function testIdleViewsAndLiquidWithdrawalAreOneToOne() external {
    asset.mint(address(idle), 100);
    assertEq(idle.totalAssets(), 100);
    assertEq(idle.grossAssets(), 100);
    assertEq(idle.availableLiquidity(), 100);
    vm.prank(router);
    assertEq(idle.withdrawLiquid(40), 40);
    assertEq(asset.balanceOf(router), 40);
}

function testNonRouterCannotMutateIdle() external {
    vm.expectRevert(IdleAdapterV2.OnlyRouter.selector);
    idle.withdrawLiquid(1);
}
```

Add zero-amount, exact deposit pull, `redeem`, `redeemAll`, final zero balance, and reentrancy cases.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/IdleAdapterV2.t.sol -vvv`

Expected: FAIL because `IdleAdapterV2` is missing.

- [ ] **Step 3: Implement minimal one-to-one behavior.**

`positionToken()` returns the underlying; `positionShares()` returns its balance; all three asset views return the same direct balance; `previewDeposit(assets)` returns `(assets, assets)`; `previewRedeem(shares)` returns `(shares, shares)`. Every state mutation is `onlyRouter`, non-reentrant, measures Router receipt, and reverts on zero or insufficient amounts. `redeemAll` transfers the complete direct balance.

- [ ] **Step 4: Run GREEN and adapter-interface regression.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/IdleAdapterV2.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/UpshiftProtocolMockV2.t.sol -vvv`

Expected: both suites PASS.

- [ ] **Step 5: Review and commit Task 2.**

Review checklist: only Router mutates; zero values revert; no approval is created; all views include donations once; returned value equals Router balance delta; full withdrawal leaves zero.

```powershell
git diff --check
git add src/v2/adapters/IdleAdapterV2.sol test/v2/IdleAdapterV2.t.sol
git commit -m "feat: add idle adapter v2"
```

Request independent review and resolve every Critical or Important finding before Task 3.

### Task 3: UpshiftAdapterV2 Accounting, Composed Preview, and Liquidity Search

**Files:**
- Create: `src/v2/adapters/UpshiftAdapterV2.sol`
- Create: `test/v2/UpshiftAdapterV2Accounting.t.sol`
- Create: `test/v2/UpshiftAdapterV2Liquidity.t.sol`

**Interfaces:**
- Consumes: frozen adapter/protocol interfaces, pinned asset/proxy/LP token, mock call counters.
- Produces: all V2 views, composed `previewDeposit`, conservative `availableLiquidity`, and a maximum 64-call share search.

- [ ] **Step 1: Write failing accounting and preview tests.**

```solidity
function testTotalGrossAndLiquidityIncludeDirectUnderlyingOnce() external {
    asset.mint(address(adapter), 7);
    seedPosition(10_000);
    (uint256 gross, uint256 net) = adapter.previewRedeem(adapter.positionShares());
    assertEq(adapter.totalAssets(), 7 + net);
    assertEq(adapter.grossAssets(), 7 + gross);
    assertEq(adapter.availableLiquidity(), 7 + net);
}

function testPreviewDepositComposesBothProtocolPreviews() external view {
    (uint256 shares, uint256 immediateNet) = adapter.previewDeposit(10_000);
    (uint256 expectedShares,) = protocol.previewDeposit(address(asset), 10_000);
    (, uint256 expectedNet) = protocol.previewRedemption(expectedShares, true);
    assertEq(shares, expectedShares);
    assertEq(immediateNet, expectedNet);
}
```

Add failures for zero shares/reference/gross/net, `net > gross`, `net > referenceAmount`, changed asset/LP binding, pause, gross limit equality/+1, net equality/+1, zero limit, and a per-operation call-count assertion `previewCallsAfter - previewCallsBefore <= 64` after resetting or snapshotting the mock counter.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/UpshiftAdapterV2*.t.sol' -vvv`

Expected: FAIL because UpshiftAdapterV2 views are absent.

- [ ] **Step 3: Implement views and bounded search.**

For nonzero held shares, call `previewRedemption(shares,true)` and require `gross > 0`, `net > 0`, and `net <= gross`; any preview revert fails closed. `previewDeposit(assets)` calls native `previewDeposit(asset,assets)`, then `previewRedemption(expectedShares,true)`, requires all approved relations, and returns `(shares, net)`. For zero held shares, position preview short-circuits while direct underlying remains included. `protocolStatus` reads the live raw fee, pause, and reference-asset limit; `depositsEnabled` and `withdrawalsEnabled` are false while paused or bindings are inconsistent.

`availableLiquidity` returns direct underlying plus a position lower bound. While paused or limit is zero, the position component is zero. Otherwise perform no more than 64 binary-search iterations over `[0, heldShares]`; a candidate is safe only when both `gross <= limit` and `net <= limit`. Return the greatest safe lower bound observed, not an assumed exact maximum.

- [ ] **Step 4: Run GREEN and call-bound regression.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/UpshiftAdapterV2*.t.sol' -vvv`

Expected: accounting, composed-preview, binding, boundary, and call-count tests PASS.

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/IdleAdapterV2.t.sol -vvv`

Expected: Idle V2 remains PASS.

- [ ] **Step 5: Review and commit Task 3.**

Review checklist: direct balance counted once; native second deposit-preview output never returned as net; gross and net both constrain liquidity; per-operation search delta cannot exceed 64 regardless of prior calls; zero-share path makes no protocol preview; binding changes fail closed.

```powershell
git diff --check
git add src/v2/adapters/UpshiftAdapterV2.sol test/v2/UpshiftAdapterV2Accounting.t.sol test/v2/UpshiftAdapterV2Liquidity.t.sol
git commit -m "feat: add upshift adapter v2 views"
```

Request independent review and resolve every Critical or Important finding before Task 4.

### Task 4: UpshiftAdapterV2 State-Changing Execution

**Files:**
- Modify: `src/v2/adapters/UpshiftAdapterV2.sol`
- Create: `test/v2/UpshiftAdapterV2Execution.t.sol`

**Interfaces:**
- Consumes: Task 3 previews and pinned balances.
- Produces: exact `withdrawLiquid`, `deposit`, `redeem`, and `redeemAll` with three-level reconciliation.

- [ ] **Step 1: Write failing execution tests.**

```solidity
function testDepositUsesExactAllowanceAndMeasuresLpDelta() external {
    fundRouterAndApproveAdapter(10_000);
    vm.prank(router);
    uint256 shares = adapter.deposit(10_000, 9_000);
    assertEq(shares, lp.balanceOf(address(adapter)));
    assertEq(asset.allowance(address(adapter), address(protocol)), 0);
    assertEq(asset.allowance(router, address(adapter)), 0);
}

function testInstantRedeemMeasuresNoReturnBalanceDelta() external {
    seedPosition(10_000);
    uint256 routerBefore = asset.balanceOf(router);
    vm.prank(router);
    uint256 received = adapter.redeem(adapter.positionShares(), 1);
    assertEq(asset.balanceOf(router) - routerBefore, received);
    assertEq(lp.allowance(address(adapter), address(protocol)), 0);
}
```

Add tests for direct donation `withdrawLiquid`, under-transfer, over-report, preview deviation enforced by `minAssetsOut`, paused redemption, exact full recovery, one-unit dust, and zero balances after `redeemAll`.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/UpshiftAdapterV2Execution.t.sol -vvv`

Expected: FAIL because state-changing methods are unimplemented or revert.

- [ ] **Step 3: Implement measured execution.**

`deposit` pulls exactly `assets` from Router, verifies the adapter asset delta, force-approves the protocol for exactly `assets`, executes deposit, resets protocol allowance to zero, and returns the positive LP balance delta after checking `minSharesOut`. `redeem` snapshots direct underlying, executes no-return `instantRedeem`, computes only `after - before`, checks `minAssetsOut`, transfers that exact delta, and requires the Router delta to match. No LP approval is created. `withdrawLiquid` transfers exact pre-existing direct underlying. `redeemAll` transfers all direct underlying plus measured redemption output and requires final underlying and LP balances to be zero.

- [ ] **Step 4: Run GREEN and full adapter regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/UpshiftAdapterV2Execution.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv`

Expected: all V2 adapter tests PASS; allowances and reconciliations are asserted.

- [ ] **Step 5: Review and commit Task 4.**

Review checklist: every external mutation has before/after balances; no protocol return is trusted as actual output; exact approvals end at zero; no LP approval; direct donation is recoverable; `redeemAll` cannot succeed with recoverable dust.

```powershell
git diff --check
git add src/v2/adapters/UpshiftAdapterV2.sol test/v2/UpshiftAdapterV2Execution.t.sol
git commit -m "feat: add upshift adapter v2 execution"
```

Request independent review and resolve every Critical or Important finding before Task 5.

### Task 5: Adapter Security and Emergency Position Recovery

**Files:**
- Create: `test/v2/mocks/MaliciousStrategyAdapterV2.sol`
- Create: `test/v2/mocks/ReentrantUpshiftVaultMock.sol`
- Create: `test/v2/UpshiftAdapterV2Security.t.sol`
- Modify: `src/v2/adapters/UpshiftAdapterV2.sol`
- Modify: `src/v2/adapters/IdleAdapterV2.sol`

**Interfaces:**
- Consumes: `IStrategyRecoveryV2`, adapter only-Router rules, mock callback hooks.
- Produces: reentrancy resistance, hostile-output rejection, and Router-only LP-token recovery primitive.

- [ ] **Step 1: Write failing security tests.**

```solidity
function testProtocolCannotReenterDeposit() external {
    protocol.armReentry(address(adapter), abi.encodeCall(adapter.deposit, (1, 1)));
    vm.prank(router);
    vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    adapter.deposit(100, 1);
}

function testRecoverPositionIsRouterOnlyAndTransfersExactShares() external {
    seedPosition(10_000);
    vm.prank(attacker);
    vm.expectRevert(UpshiftAdapterV2.OnlyRouter.selector);
    adapter.recoverPosition(owner);
    vm.prank(router);
    assertEq(adapter.recoverPosition(owner), lp.balanceOf(owner));
}
```

Add malicious under-transfer, fake share return, changing binding during call, callback from asset/LP/protocol, zero receiver, and post-recovery disabled-normal-operation cases.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/UpshiftAdapterV2Security.t.sol -vvv`

Expected: FAIL because recovery state and hostile mocks are absent.

- [ ] **Step 3: Implement minimal hardening.**

Guard all state-changing methods with `nonReentrant` and `onlyRouter`. `recoverPosition` rejects zero receiver, snapshots adapter and receiver LP balances, transfers the entire pinned LP balance, requires both deltas to equal the returned `sharesRecovered`, sets `positionRecovered = true`, and emits token/amount/receiver. After recovery, deposit/redeem/rebalance-facing methods revert; direct underlying remains sweepable through the Router's emergency flow. Binding checks run immediately before and after protocol calls.

- [ ] **Step 4: Run GREEN and all adapter regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/UpshiftAdapterV2Security.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test -vvv`

Expected: security tests, all V2 adapters, and P0 Foundry tests PASS.

- [ ] **Step 5: Review and commit Task 5.**

Review checklist: recovery is Router-only; recovery cannot masquerade as underlying withdrawal; reentrancy covers token and protocol callbacks; binding is checked around calls; hostile returns cannot defeat balance reconciliation.

```powershell
git diff --check
git add src/v2/adapters test/v2/mocks/MaliciousStrategyAdapterV2.sol test/v2/mocks/ReentrantUpshiftVaultMock.sol test/v2/UpshiftAdapterV2Security.t.sol
git commit -m "test: harden strategy adapters v2"
```

Request independent review and resolve every Critical or Important finding before Task 6.

### Task 6: Read-Only Live Withdrawal-Limit Semantics Evidence

**Files:**
- Create: `integration/upshift-withdrawal-limit-semantics.ts`
- Create: `integration/upshift-withdrawal-limit-semantics.test.ts`
- Modify: `integration/package.json`
- Modify: `package.json`
- Create at command runtime: `reports/upshift-withdrawal-limit-semantics.json`

**Interfaces:**
- Consumes: Coston2 read-only RPC, verified proxy/implementation addresses, `maxWithdrawalAmount`, deposit/redemption previews.
- Produces: `npm run verify:upshift-limit:coston2`, a bigint-safe evidence report, and no state-changing RPC method.

- [ ] **Step 1: Write failing pure evidence-classification tests.**

```ts
it.each([
  [100n, 99n, 100n, true],
  [101n, 99n, 100n, false],
  [100n, 101n, 100n, false],
])("applies conservative gross/net bounds", (gross, net, limit, expected) => {
  expect(isConservativelyWithinLimit(gross, net, limit)).toBe(expected);
});
```

- [ ] **Step 2: Run RED.**

Run: `npm test --workspace integration -- --run upshift-withdrawal-limit-semantics.test.ts`

Expected: FAIL because the evidence module is absent.

- [ ] **Step 3: Implement a read-only verifier.**

The module forbids wallet-client imports, reads chain/addresses/implementation slot/code/status, records whether verified code or public source proves comparison semantics, and evaluates exact synthetic boundary classifications. Report status is `verified_gross`, `verified_net`, `verified_other`, or `unverified_conservative`; absence of proof must produce `unverified_conservative` and cannot relax Adapter V2.

- [ ] **Step 4: Run GREEN and the explicit read-only command.**

Run: `npm test --workspace integration -- --run upshift-withdrawal-limit-semantics.test.ts`

Run: `npm run verify:upshift-limit:coston2`

Expected: unit tests PASS; live command exits 0 with a report and broadcasts no transaction. A result other than verified evidence leaves the conservative adapter rule unchanged.

- [ ] **Step 5: Review and commit Task 6.**

Review checklist: no private-key parsing; no wallet client; no write RPC; report integers are strings; evidence boundary is explicit; adapter relaxation is absent unless proof and a separately reviewed specification change exist.

```powershell
git diff --check
git add integration/upshift-withdrawal-limit-semantics.ts integration/upshift-withdrawal-limit-semantics.test.ts integration/package.json package.json reports/upshift-withdrawal-limit-semantics.json
git commit -m "test: verify upshift withdrawal limit semantics"
```

Request independent review and resolve every Critical or Important finding.

## Gate 4B Completion Verification

Run fresh:

```powershell
D:\xhy\tools\foundry\forge.exe fmt --check
D:\xhy\tools\foundry\forge.exe build
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test -vvv
npm test --workspace integration
npm run typecheck --workspace integration
```

Require all loops bounded, every adapter mutation balance-reconciled, final reachable allowances zero, P0 unchanged, and no unresolved Critical or Important review issue. Stop before RouterV2, SignalVaultV2, deployment, frontend, or TEE work.
