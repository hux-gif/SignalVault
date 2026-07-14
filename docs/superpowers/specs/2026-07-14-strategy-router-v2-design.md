# StrategyRouterV2 Differential Execution Design

**Status:** Frozen for implementation planning; production implementation is not authorized by this document

**Date:** 2026-07-14

**Author:** `hux-gif`

**Repository:** `https://github.com/hux-gif/SignalVault/`

**Baseline:** `gate4b-upshift-adapters-v2` at `5551e68d0c00fbcf435e289d7dc03b64e4802a8f`

**Product statement:** SignalVault — Private intent. Verifiable FXRP execution.

## 1. Context

Gate 4A froze the V2 authenticated allocation schema and configuration hashes. Gate 4B froze and independently reviewed the V2 strategy interfaces and the Idle and Upshift adapters. The next production module is `StrategyRouterV2`, the asset-execution module shared by both product evidence chains:

```text
FXRP -> SignalVaultV2 -> StrategyRouterV2 -> IdleAdapterV2 / UpshiftAdapterV2

Private intent -> authenticated allocation result -> SignalVaultV2
               -> the same StrategyRouterV2 -> verifiable FXRP execution
```

The Router is a deep module. Its interface exposes allocation intent, exact withdrawal, recovery, and auditable views. Differential math, protocol sequencing, balance reconciliation, loss enforcement, cooldown, and recovery state remain inside the implementation. SignalVaultV2 owns authorization, private-intent state, replay protection, nonce, deadline, commitment, and signer verification.

The current P0 Router is not a safe economic base for the final product. It withdraws every adapter position before every allocation and performs pro-rata withdrawal. With Upshift instant-redemption fees, that creates avoidable loss and breaks the desired relationship between an authenticated target and its execution.

## 2. Goals

StrategyRouterV2 must:

1. manage one underlying asset, one Vault, one IdleAdapterV2, and one UpshiftAdapterV2;
2. price execution with net-liquidation value while exposing gross telemetry separately;
3. execute strict differential allocation without unnecessary full unwind;
4. use Router and adapter direct underlying before charging an Upshift redemption fee;
5. reject infeasible targets instead of partially executing them;
6. reconcile every asset and position-token mutation with measured balance deltas;
7. enforce authenticated loss, preview-deviation, tolerance, and frozen-risk limits;
8. provide exact, liquidity-first Vault withdrawals with no arbitrary receiver;
9. isolate emergency LP-position recovery from ordinary underlying withdrawal;
10. emit execution evidence without exposing private intent.

## 3. Non-goals

This design does not add:

- arbitrary adapters or strategy replacement;
- multi-asset routing;
- permissionless strategy plugins;
- Firelight or SparkDEX execution;
- DEX aggregation or arbitrary calls;
- governance-controlled `delegatecall`;
- intent commitment, FCC verification, FTSO policy, nonce, deadline, or user authorization;
- SignalVaultV2 implementation;
- Coston2 deployment, frontend, confidential-compute, or TEE implementation.

## 4. Existing frozen dependencies

The following files are frozen reviewed dependencies:

```text
src/v2/interfaces/IStrategyAdapterV2.sol
src/v2/interfaces/IStrategyRecoveryV2.sol
src/v2/interfaces/IUpshiftVaultV2.sol
src/v2/adapters/IdleAdapterV2.sol
src/v2/adapters/UpshiftAdapterV2.sol
```

The Router consumes the exact `IStrategyAdapterV2` methods:

```solidity
asset()
positionToken()
positionShares()
totalAssets()
grossAssets()
availableLiquidity()
protocolStatus()
previewDeposit(uint256)
previewRedeem(uint256)
withdrawLiquid(uint256)
deposit(uint256,uint256)
redeem(uint256,uint256)
redeemAll(uint256)
```

Emergency recovery consumes only:

```solidity
IStrategyRecoveryV2.recoverPosition(address receiver)
```

The exact frozen behavior relevant to the Router is:

- both adapters pin an immutable Router caller;
- both adapters pull deposits from that Router with exact transfer reconciliation;
- Idle is one-to-one and has no external protocol approval;
- Upshift net assets include direct underlying plus after-fee LP value;
- Upshift gross assets include direct underlying plus before-fee LP value;
- Upshift available liquidity includes direct underlying plus a conservative LP lower bound;
- Upshift `previewDeposit` composes protocol deposit and redemption previews;
- Upshift `redeem` accepts LP shares, not a requested underlying amount;
- Upshift `redeemAll` is the only normal full-position close;
- Upshift recovery permanently disables normal protocol operations but leaves direct underlying sweepable;
- the verified protocol redemption creates no LP allowance;
- the live withdrawal-limit comparison remains unresolved, so the adapter conservatively requires both preview gross and preview net to be within the live reference-asset limit.

### 4.1 Deployment-cycle consequence

`IdleAdapterV2` and `UpshiftAdapterV2` require the Router address in their constructors. SignalVaultV2 requires the Router address, while the Router configuration hash must eventually bind the Vault and both adapters. Therefore Vault and adapter addresses cannot all be Solidity `immutable` constructor arguments of StrategyRouterV2 without an address-preimage cycle.

The selected deployable resolution is:

1. deploy Router with immutable asset and immutable prospective Vault owner;
2. deploy both adapters with the Router address;
3. configure both adapter addresses exactly once;
4. configure risk exactly once;
5. deploy SignalVaultV2 with the Router address;
6. bind the Vault exactly once and permanently freeze configuration hashes.

The Vault and adapter references are logically immutable after binding even though they occupy storage rather than Solidity immutable bytecode slots. No runtime selector can replace them.

### 4.2 Existing-code reuse map

| Classification | Existing files | RouterV2 decision |
|---|---|---|
| Reuse directly | `src/v2/types/SignalVaultTypesV2.sol`, `src/v2/libraries/SignalVaultHashesV2.sol`, `src/v2/IntentVerifierV2.sol` | Consume the frozen allocation, signed limits, risk configuration, capability profile, and config-hash definitions without redefining signed fields. |
| Reuse as frozen dependencies | `src/v2/interfaces/IStrategyAdapterV2.sol`, `src/v2/interfaces/IStrategyRecoveryV2.sol`, `src/v2/interfaces/IUpshiftVaultV2.sol`, `src/v2/adapters/IdleAdapterV2.sol`, `src/v2/adapters/UpshiftAdapterV2.sol` | Call their exact reviewed interfaces; do not change their source or ABI. |
| Reuse for tests | Gate 4B fee-aware, execution, malicious-adapter, skimming-token, adversarial-debit, false-return, reentrant, and LP-token mocks | Extend Router boundary coverage while preserving all existing Adapter tests. |
| Supersede without modifying | `src/StrategyRouter.sol`, `src/interfaces/IStrategyRouter.sol` | Preserve as the P0 baseline; new execution lives under `src/v2/`. |
| Preserve outside Router scope | `src/SignalVault.sol`, `src/IntentVerifier.sol`, P0 adapters, P0 types, P0 tests, local-signer, integration scripts, and deployment scripts | No change in the RouterV2 design or implementation tasks. |
| Missing final-product modules | `src/v2/StrategyRouterV2.sol`, `src/v2/interfaces/IStrategyRouterV2.sol`, focused RouterV2 tests, Router-specific instrumented mocks | Create through the ten-task implementation plan after explicit Task 1 authorization. |

## 5. Comparison of approaches

### 5.1 A. Full unwind and full redeposit

Every allocation redeems all positions and deposits all returned assets at the new weights.

Advantages:

- simple bookkeeping;
- deterministic under one-to-one mocks.

Rejected because:

- unchanged Upshift exposure pays another instant-redemption fee;
- protocol calls and proxy-upgrade exposure are maximized;
- small signed changes can create whole-position loss;
- an unavailable Upshift position blocks unrelated fee-free allocation work.

### 5.2 B. Best-effort partial rebalance

The Router moves as much as current liquidity allows and accepts a position between the old and signed targets.

Advantages:

- more transactions return successfully during protocol illiquidity;
- fewer target-feasibility reverts.

Rejected because:

- authenticated target and actual position diverge;
- downstream execution evidence becomes ambiguous;
- a caller cannot distinguish a completed allocation from a partial fallback by transaction success alone;
- silent strategy substitution would undermine the Coston2 capability profile.

### 5.3 C. Strict differential rebalance

The Router computes the exact necessary direction, uses direct liquidity first, withdraws only the overweight delta, deposits only the underweight delta, and atomically rejects any plan that cannot meet the signed target within tolerance.

Selected because it:

- minimizes fee-bearing turnover;
- preserves authenticated-target semantics;
- keeps failure explicit;
- supports future FCC-authenticated allocation evidence;
- is fully expressible through the frozen Adapter V2 interface.

## 6. Selected architecture

StrategyRouterV2 has these fixed economic identities:

```text
underlying asset: immutable constructor value
prospective Vault owner: immutable constructor value
IdleAdapterV2: configured once, frozen at Vault bind
UpshiftAdapterV2: configured once, frozen at Vault bind
SignalVaultV2: bound once, frozen at Vault bind
capability profile: SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1
Router config version: 1
```

All state-changing production selectors are `onlyVault` and `nonReentrant`. Pre-bind configuration is callable only by the immutable prospective Vault owner. Binding permanently disables configuration.

The Router does not expose an arbitrary-call selector, an arbitrary receiver, an adapter array, or a strategy replacement function.

## 7. Trust boundaries

### 7.1 SignalVaultV2 is trusted for authorization, not accounting claims

SignalVaultV2 verifies the signed result, user, commitment, replay state, nonce, deadline, chain, capability profile, Router configuration hash, and signed risk strengths. It pushes funding to the Router and calls the Router. The Router still independently validates allocation shape, risk-strength directions, funding presence, token deltas, adapter outputs, post-NAV, and post-allocation tolerance.

### 7.2 Adapters are constrained dependencies

The frozen adapters enforce their own protocol bindings and deltas. The Router nevertheless measures its own balances around every adapter mutation. An adapter return value is evidence to reconcile, never the sole accounting source.

### 7.3 Tokens and Upshift are adversarial execution dependencies

The underlying, LP token, callbacks, protocol pause, fee, reference limit, binding getters, and previews can fail or change. Ordinary execution fails closed. Recovery is separately named and cannot report LP tokens as underlying assets.

## 8. State model

```solidity
enum RouterStateV2 {
    Operational,
    UpshiftUnavailable,
    UpshiftRecovered
}
```

`Operational` means local execution is not paused, adapter configuration is frozen, the Upshift adapter is not recovered, and its live status reports deposits and withdrawals enabled with valid bindings.

`UpshiftUnavailable` means the Router is locally paused or the non-recovered Upshift adapter reports unavailable status or cannot supply required preview/status data. This state is reversible only by restoring live conditions and unpausing through SignalVaultV2 authorization.

`UpshiftRecovered` is permanent after successful LP-position recovery. Normal Upshift valuation, deposits, redemptions, and rebalance targets are disabled. Direct underlying held by the recovered adapter remains withdrawable through `withdrawLiquid` and is counted from the underlying token balance directly.

The Router stores `executionPaused` and `upshiftRecovered`. `strategyState()` derives the live unavailable state with `try/catch` around protocol status. Accounting functions continue only when they can obtain trustworthy values. They revert on an unpriceable nonzero position rather than fabricating NAV.

## 9. Final ABI proposal

The new interface is `src/v2/interfaces/IStrategyRouterV2.sol`. It consumes the already-frozen `AllocationV2`, `RebalanceLimitsV2`, and `RiskConfigurationV2` types.

```solidity
interface IStrategyRouterV2 {
    function asset() external view returns (address);
    function vaultOwner() external view returns (address);
    function vault() external view returns (address);
    function idleAdapter() external view returns (address);
    function upshiftAdapter() external view returns (address);

    function capabilityProfile() external pure returns (bytes32);
    function routerConfigVersion() external pure returns (uint256);
    function riskConfiguration() external view returns (RiskConfigurationV2 memory);
    function riskConfigurationHash() external view returns (bytes32);
    function routerConfigHash() external view returns (bytes32);
    function configurationFrozen() external view returns (bool);

    function executionPaused() external view returns (bool);
    function upshiftRecovered() external view returns (bool);
    function strategyState() external view returns (RouterStateV2);
    function lastRebalanceTimestamp() external view returns (uint256);

    function totalAssets() external view returns (uint256 netAssets);
    function grossAssets() external view returns (uint256 grossAssets_);
    function availableLiquidity() external view returns (uint256 liquidAssets);
    function allocation() external view returns (AllocationSnapshotV2 memory snapshot);

    function previewRebalance(
        AllocationV2 calldata target,
        RebalanceLimitsV2 calldata limits
    ) external view returns (RebalancePlanV2 memory plan);

    function rebalance(
        bytes32 executionId,
        AllocationV2 calldata target,
        RebalanceLimitsV2 calldata limits,
        uint256 fundingAssets
    ) external returns (uint256 totalAssetsAfter);

    function withdrawToVault(uint256 assets) external returns (uint256 assetsDelivered);
    function withdrawAllToVault() external returns (uint256 assetsDelivered);
    function recoverAdapterPosition() external returns (uint256 sharesRecovered);
    function setExecutionPaused(bool paused) external;
}
```

Pre-bind configuration is intentionally outside the runtime interface but is part of the concrete contract:

```solidity
configureAdapters(address upshiftAdapter_, address idleAdapter_)
configureRisk(RiskConfigurationV2 calldata riskConfiguration_)
bindVault(address vault_)
```

The Router validates the concrete adapters' existing public `router()` getters through a narrow local binding-check interface. This does not modify the frozen adapter interface.

`withdrawAllToVault()` is retained because `withdrawToVault(totalAssets())` cannot prove zero LP dust across discrete share conversion. The full selector invokes both adapters' reviewed `redeemAll` behavior and asserts final recoverable balances are zero.

## 10. NAV definitions

Let:

```text
R = underlying held directly by Router
I = IdleAdapterV2.totalAssets()
D = underlying held directly by UpshiftAdapterV2
Pnet = UpshiftAdapterV2.totalAssets() - D
Pgross = UpshiftAdapterV2.grossAssets() - D
```

Then:

```text
net NAV   = R + I + D + Pnet
gross NAV = R + I + D + Pgross
```

The subtraction is valid only after requiring each adapter-reported total to be at least its observed direct underlying. A violation reverts.

After recovery, Upshift normal views intentionally revert. Router accounting becomes:

```text
net NAV after recovery   = R + I + D
gross NAV after recovery = R + I + D
```

Recovered LP tokens are transferred to the Vault and are not represented as underlying NAV. SignalVaultV2 must record them as non-underlying emergency output.

Protocol position shares are never added to underlying amounts. Gross value is telemetry and never prices shares, withdrawal obligations, targets, loss, or slippage.

## 11. Allocation mathematics

Every BPS denominator is exactly `10_000`.

The Coston2 allocation validator requires:

```text
firelightBps == 0
sparkdexBps == 0
upshiftBps + idleBps == 10_000
```

Unsupported weights revert and are never moved to Idle.

Targets are based on projected post-execution net NAV because moving liquid underlying into Upshift can immediately recognize an exit-fee reserve:

```text
targetIdle = floor(projectedPostNetNAV * idleBps / 10_000)
targetUpshift = projectedPostNetNAV - targetIdle
```

This remainder rule guarantees:

```text
targetIdle + targetUpshift == projectedPostNetNAV
```

All products use OpenZeppelin `Math.mulDiv`. Ceil operations use `Math.mulDiv(..., Math.Rounding.Ceil)` or an explicitly proven `ceilDiv` that cannot overflow.

`minimumAllocationChangeBps` remains part of the frozen Gate 4A risk type. In this strict design it is an execution floor, not a silent skip permission. A nonzero target change below the floor makes the plan infeasible with `ChangeBelowMinimum` and `rebalance` reverts. An exactly satisfied target is a zero-call no-op and emits `AllocationSkipped` without advancing cooldown.

## 12. Direct-buffer semantics

Router direct underlying and Upshift-adapter direct underlying are execution buffer, not a third target strategy and not protocol exposure.

They are included in total NAV but excluded from the realized IdleAdapter and Upshift-position target balances. A qualifying plan assigns buffer to target deficits before withdrawing either strategy.

Example:

```text
Router direct = 20
IdleAdapter = 30
Upshift position net = 50
Target = 50 Idle / 50 Upshift
```

The Router deposits the direct 20 into Idle. It does not redeem Upshift.

For a qualifying rebalance, Upshift direct underlying is swept with `withdrawLiquid` before strategy movement. This sweep changes custody but not NAV. An exact no-op with no target deficit makes zero external calls. A direct donation creates a target deficit and is therefore allocatable on the next qualifying execution.

Normally a target transition has at most one strategic withdrawal and one strategic deposit. The sole two-deposit case is an initial or donation-funded allocation where both adapters are below target and direct buffer funds both deficits; that case performs no strategic withdrawal. Ordinary execution never performs both Idle redemption and Upshift LP redemption in one rebalance.

## 13. Differential rebalance algorithm

The public preview and execution call the same internal `_computeRebalancePlan(target, limits)` function. Preview uses current onchain balances. SignalVaultV2 must push funding before calling `rebalance`; `fundingAssets` is reconciliation evidence and does not change allocation math.

```solidity
enum RebalanceBlockerV2 {
    None,
    ConfigurationNotFrozen,
    ExecutionPaused,
    InvalidAllocation,
    InvalidSignedLimits,
    ChangeBelowMinimum,
    CooldownActive,
    UpshiftUnavailable,
    InsufficientLiquidity,
    ZeroPreview,
    SolverDidNotConverge,
    PreviewOutsideTolerance,
    RecoveredTargetForbidden
}
```

```solidity
struct AllocationSnapshotV2 {
    uint256 totalNetAssets;
    uint256 totalGrossAssets;
    uint256 routerDirectAssets;
    uint256 idleAssets;
    uint256 upshiftDirectAssets;
    uint256 upshiftPositionNetAssets;
    uint256 upshiftPositionGrossAssets;
    uint256 upshiftPositionShares;
    uint16 idleBps;
    uint16 upshiftBps;
}
```

```solidity
struct RebalancePlanV2 {
    uint256 totalAssetsBefore;
    uint256 projectedTotalAssetsAfter;
    uint256 routerAssetsBefore;
    uint256 idleAssetsBefore;
    uint256 upshiftDirectAssetsBefore;
    uint256 upshiftPositionAssetsBefore;
    uint256 targetIdleAssets;
    uint256 targetUpshiftAssets;
    uint256 idleWithdrawAssets;
    uint256 upshiftLiquidWithdrawAssets;
    uint256 upshiftSharesToRedeem;
    uint256 previewedUpshiftAssetsOut;
    uint256 upshiftMinAssetsOut;
    uint256 idleDepositAssets;
    uint256 upshiftDepositAssets;
    uint256 previewedUpshiftSharesOut;
    uint256 previewedUpshiftNetAdded;
    uint256 requiredProtocolLiquidity;
    bool feasible;
    RebalanceBlockerV2 blocker;
}
```

The plan algorithm is:

1. validate frozen configuration, target, signed limits, state, and cooldown;
2. snapshot Router direct, Idle assets, Upshift direct, LP shares, position net, position gross, and total net NAV;
3. derive target direction from adapter positions, excluding direct buffer;
4. apply direct buffer to target deficits first;
5. if Upshift is overweight, estimate only the shares needed to reduce its net position;
6. if Upshift is underweight, estimate only the underlying needed to add immediate net position value;
7. permit one initial candidate and at most one proportional refinement;
8. reject a candidate outside target tolerance or immediate liquidity;
9. derive per-call minimum output from the final live preview and signed preview-deviation BPS;
10. execute the frozen plan order;
11. reconcile every Router, adapter, and position-token delta;
12. recompute post-NAV, target tolerance, signed minimum NAV, and loss;
13. update cooldown only after a successful nonzero allocation movement;
14. emit canonical execution evidence.

For an Upshift decrease, the initial candidate is:

```text
requiredNetReduction = currentUpshiftNet - provisionalTargetUpshift

candidateShares = ceil(
    heldShares * requiredNetReduction / currentUpshiftNet
)
```

The Router previews the candidate shares and the remaining shares. A single proportional refinement is allowed. The remaining-position preview, projected post-NAV, and final target must be within `allocationToleranceBps`; subtracting candidate output from whole-position value is not assumed to be exact.

For an Upshift increase, each candidate calls:

```text
(expectedShares, immediateNetAdded) = upshiftAdapter.previewDeposit(candidateAssets)
```

The projected state is:

```text
projectedUpshift = currentUpshiftPositionNet + immediateNetAdded
projectedPostNAV = currentNAV - candidateAssets + immediateNetAdded
projectedTargetUpshift = projectedPostNAV - floor(projectedPostNAV * idleBps / 10_000)
```

The initial estimate and one proportional refinement are the only candidate evaluations. Because the frozen adapter composes two protocol views per deposit preview, the increase solver causes at most four protocol preview calls. Failure to converge within the bound is infeasible.

## 14. Feasibility

`previewRebalance` returns `feasible = true` only when the exact frozen plan can meet the target within signed tolerance using currently available execution dependencies.

For an Upshift reduction:

```text
positionLiquidity = upshiftAdapter.availableLiquidity() - upshiftDirectAssets
requiredProtocolLiquidity = previewedUpshiftAssetsOut

requiredProtocolLiquidity <= positionLiquidity
```

The subtraction requires `availableLiquidity >= upshiftDirectAssets`.

For an Upshift increase, the candidate deposit must be no greater than Router buffer plus the exact Idle liquidity that can be withdrawn without touching Upshift.

An unavailable or recovered Upshift adapter makes every nonzero Upshift target plan infeasible. A recovered adapter also forbids a target equal to an old, now-unpriceable position. No plan silently remaps weight to Idle.

`rebalance` recomputes the plan at execution time and reverts `RebalanceInfeasible(blocker)` if `feasible` is false. It never executes a prefix of an infeasible plan.

## 15. Upshift fee model

No Router constant represents 50 BPS. Current fee configuration is observable telemetry; the authoritative values are the adapter's live composed previews and measured execution deltas.

Current Upshift position value is after-fee net value. A new deposit recognizes its immediate exit-value reserve through `previewDeposit`. A redemption uses `previewRedeem` for expected gross and net, then uses actual Router receipt for execution accounting.

The Router never treats protocol LP shares as underlying units and never derives NAV from the Upshift vault's direct underlying balance.

## 16. Slippage semantics

There is no Router-wide caller-selected `minAssetsOut` for rebalance. Every fee-bearing adapter call has its own meaningful minimum derived from its live preview:

```text
rebalance minimum = floor(
    previewedNet * (10_000 - signed.maximumPreviewDeviationBps) / 10_000
)
```

For Upshift deposit, `minSharesOut` is derived from expected LP shares with the same signed deviation denominator and floor direction. The Router then checks both its underlying debit and the adapter's actual share increase.

For ordinary withdrawal, the Router uses the frozen `maximumPreviewDeviationBps` because there is no signed rebalance result. Vault-level user slippage remains SignalVaultV2's responsibility. Router withdrawal either delivers the exact requested underlying amount or reverts.

Preview expected net, adapter minimum, adapter return, Router balance delta, and post-operation position value are separate recorded facts.

## 17. Loss accounting

For a qualifying rebalance:

```text
preNetAssets = totalAssets() before mutation
postNetAssets = totalAssets() after all mutation and reconciliation

maxLoss = floor(
    preNetAssets * signed.maximumRebalanceLossBps / 10_000
)
```

Success requires:

```text
postNetAssets >= limits.minimumPostNAV
postNetAssets + maxLoss >= preNetAssets
```

The addition is evaluated without overflow by comparing `preNetAssets - postNetAssets` only when `postNetAssets < preNetAssets`:

```text
actualLoss = max(preNetAssets - postNetAssets, 0)
actualLoss <= maxLoss
```

The Router independently requires signed limits to be no weaker than frozen configuration:

```text
signed.maximumRebalanceLossBps <= frozen.maximumRebalanceLossBps
signed.maximumPreviewDeviationBps <= frozen.maximumPreviewDeviationBps
signed.allocationToleranceBps <= frozen.allocationToleranceBps
```

Loss includes Upshift fee, integer conversion, adverse token behavior that survives lower-level checks, and adapter execution deviation. Any failed postcondition reverts the complete transaction atomically.

## 18. Rebalance interval

`minimumRebalanceInterval` is seconds. `lastRebalanceTimestamp == 0` permits the first qualifying rebalance immediately.

Every later qualifying rebalance requires:

```text
block.timestamp >= lastRebalanceTimestamp + minimumRebalanceInterval
```

The addition is checked for overflow. Exact no-op preview and execution make no adapter call and do not advance the timestamp. A target change below `minimumAllocationChangeBps` reverts and does not advance it.

The interval never blocks `withdrawToVault`, `withdrawAllToVault`, `setExecutionPaused`, or `recoverAdapterPosition`.

## 19. Withdraw-to-Vault

`withdrawToVault(uint256 assets)` is `onlyVault` and `nonReentrant`. The receiver is always the bound Vault and cannot be supplied by a caller.

The waterfall is:

```text
Router direct underlying
-> IdleAdapterV2 direct liquidity
-> UpshiftAdapterV2 direct underlying
-> Upshift LP redemption for the final deficit
```

Before any mutation, the Router checks aggregate immediate liquidity. If the final deficit requires Upshift LP redemption, it derives candidate shares with an initial proportional ceil estimate and at most one refinement. The preview must cover the deficit, remain within the adapter's conservative live liquidity, and produce a nonzero minimum. Discrete-share over-redemption remains Router direct underlying.

After sourcing assets, the Router transfers exactly the requested amount to the Vault and verifies:

```text
Router debit == assets
Vault credit == assets
returned assetsDelivered == assets
```

The withdrawal algorithm is separate from rebalance planning because its safety objective is exact payment, not target allocation. It shares arithmetic and delta helpers but not a combined state machine.

`withdrawAllToVault()` drains Router direct underlying, calls Idle `redeemAll`, calls Upshift `redeemAll` with a live preview-derived minimum when LP shares exist, verifies zero normal recoverable underlying and zero adapter position shares, then transfers the complete Router underlying balance to the Vault. It reverts before a successful share burn if full normal recovery is unavailable.

## 20. Recovery

`recoverAdapterPosition()` is `onlyVault`, `nonReentrant`, and requires `executionPaused == true`. It is not subject to rebalance cooldown.

The receiver is fixed to the bound Vault. The Router calls:

```solidity
IStrategyRecoveryV2(upshiftAdapter).recoverPosition(vault)
```

The Router measures the adapter LP decrease and Vault LP increase and requires both to equal the returned `sharesRecovered`. It then sets `upshiftRecovered = true` permanently and emits non-underlying recovery evidence.

After recovery:

- no normal rebalance can target Upshift;
- no Router selector can deposit into or redeem from Upshift;
- `withdrawToVault` can still sweep direct underlying from the recovered adapter;
- Router net/gross/liquidity views count only that direct underlying for the recovered adapter;
- recovered LP tokens are accounted by SignalVaultV2's emergency close, not Router NAV;
- no second Router recovery path exists.

LP tokens sent to the recovered adapter afterward may be permanently locked because the frozen adapter disables a second recovery. Router execution must never transfer LP tokens to an adapter.

## 21. Capability handling

The Router returns the fixed capability profile:

```solidity
keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1")
```

It consumes the four-field `AllocationV2` wire type to match Gate 4A authentication but accepts only Upshift and Idle. Firelight and SparkDEX must both be zero. Unsupported weights revert before token or adapter mutation.

`routerConfigHash` uses `SignalVaultHashesV2.computeRouterConfigHash` after Vault bind and includes chain, Vault, Router, asset, exact adapters, capability profile, frozen risk hash, and version `1`.

Recovery is a runtime capability reduction. It does not rewrite the frozen configuration hash or make an old signed Upshift target executable; execution rejects recovered-target allocations.

## 22. Rounding

Every division rounds down except:

- initial share estimates that must cover a required net withdrawal round up;
- explicit candidate refinements documented as ceil estimates.

The target remainder is assigned to Upshift through:

```text
targetIdle = floor(projectedPostNAV * idleBps / 10_000)
targetUpshift = projectedPostNAV - targetIdle
```

This choice preserves exact target sum and keeps one rounding rule across preview and execution. Deposit and redemption candidates use no more than two evaluations. Router dust may remain only when it cannot be allocated without exceeding target tolerance; the postcondition measures it explicitly and classifies it as execution buffer, not an adapter position.

## 23. Events

Events expose execution evidence and no private intent:

```solidity
event AllocationExecuted(
    bytes32 indexed executionId,
    uint16 idleBps,
    uint16 upshiftBps,
    uint256 totalAssetsBefore,
    uint256 totalAssetsAfter,
    uint256 lossAssets
);

event AllocationSkipped(
    bytes32 indexed executionId,
    uint16 idleBps,
    uint16 upshiftBps,
    uint256 totalAssets
);

event AssetsWithdrawnToVault(
    uint256 requestedAssets,
    uint256 deliveredAssets,
    uint256 routerDirectUsed,
    uint256 idleAssetsUsed,
    uint256 upshiftDirectUsed,
    uint256 upshiftSharesRedeemed,
    uint256 upshiftAssetsReceived
);

event AdapterPositionRecovered(
    address indexed positionToken,
    uint256 sharesRecovered,
    address indexed receiver
);

event ExecutionPauseUpdated(bool paused);
```

`executionId` is opaque to the Router. SignalVaultV2 maps an authenticated result hash to it. No plaintext intent, commitment preimage, risk narrative, FTSO policy, or confidential-compute payload is emitted.

## 24. Error taxonomy

The concrete contract defines and uses these errors:

```solidity
error ZeroAddress();
error UnauthorizedConfigurator();
error OnlyVault();
error ConfigurationAlreadySet();
error ConfigurationIncomplete();
error ConfigurationFrozen();
error AdapterAssetMismatch();
error AdapterRouterMismatch();
error DuplicateAdapter();
error VaultOwnerMismatch();
error InvalidBps();
error InvalidRiskConfiguration();
error InvalidAllocation();
error InvalidSignedLimits();
error ExecutionPaused();
error CooldownActive(uint256 earliestTimestamp);
error RebalanceInfeasible(RebalanceBlockerV2 blocker);
error FundingMismatch(uint256 declaredFunding, uint256 availableFunding);
error PreviewDeviationExceeded();
error AllocationToleranceExceeded();
error MinimumPostNAVNotMet(uint256 minimum, uint256 actual);
error RebalanceLossExceeded(uint256 maximumLoss, uint256 actualLoss);
error InsufficientLiquidity(uint256 requested, uint256 available);
error AssetDeltaMismatch();
error AdapterDeltaMismatch();
error AllowanceNotCleared();
error RecoveryRequiresPause();
error PositionAlreadyRecovered();
error RecoveredTargetForbidden();
error ResidualAssets();
error ResidualPosition();
```

External adapter errors may propagate when they identify the exact failed frozen dependency. Router-specific postconditions use the taxonomy above.

## 25. Security invariants

1. Every runtime state mutation is Vault-only.
2. Every runtime state mutation is non-reentrant.
3. No selector accepts an arbitrary asset receiver.
4. No selector accepts an arbitrary call target or calldata.
5. The Router performs no `delegatecall`.
6. Asset, Vault, and adapter identities cannot change after bind.
7. Adapter `router()` bindings equal the Router before freeze.
8. Net NAV, gross telemetry, available liquidity, and LP shares remain distinct units.
9. Direct donations to Router and adapters remain system NAV and are counted once.
10. Every Router token debit and credit is measured.
11. Every adapter return is reconciled with Router balance delta.
12. Every Upshift share mutation is reconciled with actual position-token balance.
13. Ordinary rebalance cannot full-unwind an unchanged position.
14. An infeasible target causes zero committed state change.
15. Unsupported weights cannot be redirected.
16. Preview and execution use the same planning function and rounding rules.
17. Every candidate loop is bounded to two evaluations; adapter liquidity search remains bounded to 64 previews inside the frozen adapter.
18. Post-rebalance NAV satisfies both absolute and relative signed bounds.
19. Signed limits cannot weaken frozen limits.
20. Cooldown applies only to successful nonzero rebalance movement.
21. Exact withdrawal pays the bound Vault or reverts atomically.
22. Fee-free tiers are exhausted before Upshift LP redemption.
23. Recovery cannot masquerade as underlying withdrawal.
24. No normal target can use a recovered adapter.
25. Preview cannot report feasible when a required dependency is unavailable.
26. Exact temporary allowances return to zero; no unlimited approval is created.
27. Coston2 never executes Firelight or SparkDEX weight.
28. Events do not disclose private intent.

## 26. State-transition matrix

| Operation | Operational | UpshiftUnavailable | UpshiftRecovered |
|---|---|---|---|
| `totalAssets` | Router + Idle + Upshift net | succeeds only if Upshift net preview remains trustworthy; otherwise reverts | Router + Idle + Upshift direct underlying |
| `grossAssets` | Router + Idle + Upshift gross | succeeds only if gross preview remains trustworthy; otherwise reverts | Router + Idle + Upshift direct underlying |
| `availableLiquidity` | full verified waterfall capacity | Router + Idle + Upshift direct underlying only | Router + Idle + Upshift direct underlying only |
| `previewRebalance` | exact plan or explicit blocker | `feasible = false` | zero-Upshift target remains forbidden; `feasible = false` |
| `rebalance` | executes strict plan | reverts | reverts |
| `withdrawToVault` | complete waterfall | succeeds through fee-free tiers; reverts if LP redemption is required | succeeds through Router, Idle, and recovered-adapter direct underlying |
| `withdrawAllToVault` | succeeds only if all normal positions close | reverts when nonzero Upshift LP cannot close | transfers only normal underlying; recovered LP stays with Vault emergency accounting |
| `recoverAdapterPosition` | requires pause, then transitions to recovered | allowed only while locally paused and LP exists | reverts permanently |
| `setExecutionPaused` | may transition to unavailable | may restore operational state after review | remains recovered regardless of pause flag |

## 27. Testing strategy

Tests are split by responsibility:

```text
test/v2/StrategyRouterV2Configuration.t.sol
test/v2/StrategyRouterV2Accounting.t.sol
test/v2/StrategyRouterV2Planning.t.sol
test/v2/StrategyRouterV2Execution.t.sol
test/v2/StrategyRouterV2Withdrawal.t.sol
test/v2/StrategyRouterV2Recovery.t.sol
test/v2/StrategyRouterV2Security.t.sol
```

Existing reusable mocks:

- `FeeAwareUpshiftVaultMock` for fee, pause, limit mode, and preview behavior;
- `ExecutionUpshiftVaultMock` for independent return/delta failures and callbacks;
- `MaliciousStrategyAdapterV2` for over-report without transfer;
- `SkimmingERC20V2` for under-receipt;
- `AdversarialDebitERC20V2` for over-debit, under-debit, and receiver over-credit;
- `FalseReturnERC20V2` for false-return transfer behavior;
- `ReentrantERC20V2` and `ReentrantUpshiftVaultMock` for callback attacks;
- `MockLPTokenV2` for position-balance measurement.

Router-focused instrumented adapters add deterministic net/gross/liquidity, preview curves, call counters, under-delivery, over-report, binding drift, and reentrant callbacks. Adapter-layer tests remain intact; Router tests independently prove the Router seam rather than trusting lower-layer coverage.

Mutation and sensitivity checks must remove or invert each critical guard: onlyVault, nonReentrant, direct-buffer priority, strict feasibility, final plan recomputation, Router balance checks, preview minimum, cooldown update rule, loss check, recovery receiver, and recovered-target rejection. Each mutation must cause a named focused test to fail.

## 28. Known limitations

- Strict target semantics can reject an economically reasonable partial improvement when full target liquidity is unavailable.
- The two-candidate solver can reject a target that a more expensive exact solver could find.
- `maxWithdrawalAmount` semantics remain unresolved; the frozen adapter's gross-and-net conservative restriction remains mandatory.
- Protocol view gas can be high because Upshift liquidity search is bounded at 64 preview calls.
- Runtime proxy implementation changes cannot be detected onchain through `extcodehash(proxy)`; observable binding, preview, delta, pause, and loss checks remain the onchain controls.
- After recovery, LP tokens sent back to the recovered adapter may be permanently locked because recovery is single-use.
- Router configuration is logically immutable after bind, not represented entirely with Solidity immutable variables, due the verified constructor-address cycle.

## 29. SignalVaultV2 integration boundary

SignalVaultV2 must:

1. authenticate `TEEResultV2` through IntentVerifierV2;
2. verify capability and `routerConfigHash` equality;
3. enforce commitment, nonce, deadline, chain, user, Vault, and replay rules;
4. reject signed risk limits weaker than Router frozen limits;
5. measure Vault and Router balances while pushing exact funding;
6. call `rebalance(result.resultHash, result.allocation, result.limits, fundingAssets)`;
7. price shares and withdrawals from net NAV;
8. call `withdrawToVault` only for the exact remaining user obligation;
9. call `withdrawAllToVault` before a normal full share burn;
10. authorize pause and recovery while recording recovered LP tokens as non-underlying emergency output.

The Router never reads or stores plaintext intent, ciphertext, salted commitment material, FTSO policy, signer identity, nonce, or deadline.

## 30. Hackathon value

This architecture produces two complementary proof chains in one public repository:

```text
real FXRP economics:
net NAV -> strict delta execution -> measured Upshift/Idle balances -> public events

private-intent authorization:
hidden mandate -> authenticated V2 result -> exact Router target -> the same public events
```

The result is a demonstrable claim rather than a slide-only architecture: private intent remains offchain, the authorized aggregate target is cryptographically bound, unnecessary fee-bearing turnover is prevented, and Coston2 execution can be verified from balances, receipts, config hashes, and privacy-safe events.

## Design self-review

- Frozen Adapter V2 function names and share-based redemption semantics were copied from baseline `5551e68`; no frozen ABI change is required.
- Adapter immutable Router binding and Vault/Router construction cycles are resolved by one-time configuration and permanent binding, with no replace selector.
- Preview and execution share `_computeRebalancePlan` and identical rounding.
- Direct Router and Upshift-adapter underlying are NAV and first-use buffer, not protocol exposure.
- Strict feasibility forbids partial success and silent unsupported-weight redirection.
- Increase and decrease candidates are bounded to two evaluations; the adapter retains its independent 64-preview liquidity bound.
- Net NAV, projected post-NAV targets, preview minimums, actual deltas, and final loss are separate quantities.
- Withdrawals use a dedicated exact-payment waterfall rather than rebalance semantics.
- Recovery has one receiver, one state transition, no cooldown, and no underlying-recovery mislabel.
- Every state, error, struct, event, unit, denominator, comparison direction, and rounding direction used by the design is defined.
- P0 Router, Vault, verifier, adapters, tests, and Gate 4B frozen files remain superseded or consumed without modification.
