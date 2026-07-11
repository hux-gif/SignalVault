# SignalVault Gate 3: Fee-Aware Upshift Router Economics

**Status:** Proposed for review

**Date:** 2026-07-11

**Author:** `hux-gif`

**Repository baseline:** `main` at `8380d1e`
**Scope:** Economic model and interfaces only; no implementation is authorized by this document

## 1. Purpose and verified facts

This specification replaces the current mock-oriented Router economics with a design suitable for a synchronous, single-owner SignalVault backed by the real Coston2 Upshift vault.

Gate 2C established the following facts:

- `instantRedemptionFee()` returned `50` with denominator `10_000`, meaning 50 BPS (0.5%).
- `previewRedemption(shares, true)` returned both gross and after-fee assets.
- The tested `instantRedeem` output exactly matched the after-fee preview.
- Deposit and redemption conversion can each lose approximately one smallest unit to integer rounding.
- `instantRedeem` returns no Solidity value, so output must be measured from underlying-asset balance deltas.
- Upshift LP-token approval was not required in the verified flow.
- Underlying and LP allowances were zero after the verified round trip.
- The vault is a proxy. Its fee and behavior may change; 50 BPS is an observation, not a constant for SignalVault.
- A proxy's direct underlying balance is not its NAV and must not be used as the position valuation.

The [Flare Developer Hub instant-redeem guide](https://dev.flare.network/fxrp/upshift/instant-redeem) independently documents that instant redemption burns LP shares, returns underlying immediately subject to a fee, and that `previewRedemption` exposes before-fee and after-fee amounts. The live Gate 2C report, rather than the guide's illustrative output, is authoritative for the measured Coston2 value of 50 BPS.

The current contracts conflict with production economics in three important ways:

1. `StrategyRouter.rebalance` fully withdraws all adapters and redeposits all assets. A small allocation change therefore charges the Upshift exit fee on the whole Upshift position.
2. `withdrawProRata` touches every adapter even when fee-free liquidity is sufficient.
3. `IStrategyAdapter.previewRedeem` has no explicit gross/net semantics and the mock 1:1 behavior hides exit costs.

This document defines the replacement model. It deliberately does not select final numeric risk limits; those values require review before deployment.

## 2. Overall architecture decision

### 2.1 Alternatives

#### Approach 1: Preserve full unwind and redeposit

Every accepted allocation first redeems all positions, then deposits the resulting assets at the new weights.

This is simple and deterministic with 1:1 mocks, but it is rejected. If Upshift is 50% of NAV, a rebalance can charge about 25 Vault-level BPS even when its target changes only from 50% to 51%. It also creates unnecessary protocol calls, increases upgrade and pause exposure, and makes signer churn economically destructive.

#### Approach 2: Differential rebalance using gross NAV

Only position deltas move, but Upshift is valued before its immediate exit fee.

This reduces churn but is rejected for share accounting. SignalVault promises synchronous underlying-asset withdrawals. Gross NAV can report and mint against assets that cannot be realized immediately. An exiting owner would then receive less than the accounting value, or later deposits would subsidize the fee. Gross value remains useful only as non-accounting telemetry.

#### Approach 3: Differential rebalance using net-liquidation NAV

Only overweight deltas are redeemed, only underweight deltas are funded, and Upshift is valued at its current immediately redeemable after-fee amount.

This is the selected approach. It aligns deposit pricing, withdrawal pricing, loss limits, and Router targets with the same fee-adjusted unit: FTestXRP smallest units after protocol fees. When the protocol is unpaused this is immediately realizable; while withdrawals are paused it is a marked liquidation value, not a promise that the whole position is immediately liquid. `availableLiquidity()` is the separate capacity measure. A separate gross view preserves observability without contaminating share accounting.

### 2.2 Selected model

The production model is:

```text
net-liquidation NAV
+ liquidity-first withdrawals
+ differential rebalancing
+ protocol previews on every operation
+ post-operation balance-delta reconciliation
+ one-time risk limits
+ an honest Coston2 Upshift/Idle capability profile
```

All asset amounts are unsigned integers in the underlying asset's smallest unit. All BPS values use denominator `10_000`. Arithmetic must use full-width multiplication/division helpers or ordering that cannot overflow; TypeScript tooling must use `bigint` and serialize integers as decimal strings.

## 3. NAV accounting

### 3.1 Alternatives and decision

- **A. Gross Upshift value:** rejected for accounting because it ignores the cost of synchronous liquidation.
- **B. Net Upshift value only:** economically correct but loses useful protocol telemetry.
- **C. Dual view:** selected. `totalAssets()` is net liquidation value, while `grossAssets()` is informational only.

For SignalVault:

```text
SignalVault.totalAssets =
    underlying balance held by SignalVault
  + StrategyRouter.totalAssets
```

For StrategyRouter:

```text
StrategyRouter.totalAssets =
    underlying balance held directly by Router
  + IdleAdapter.totalAssets
  + UpshiftAdapter.totalAssets
```

For UpshiftAdapter:

```text
UpshiftAdapter.totalAssets =
    previewRedemption(positionShares, true).assetsAfterFee
```

When `positionShares() == 0`, `totalAssets()`, `grossAssets()`, `availableLiquidity()`, and `previewRedeem(0)` return zero locally without calling Upshift. This permits an empty Vault to price its first deposit even if the protocol rejects a zero-share preview. For nonzero position shares, zero gross output, net output greater than gross, or otherwise inconsistent preview data fails closed; it is not treated as an empty position.

`grossAssets()` uses the same held shares but returns `assetsBeforeFee`. No state-changing or share-accounting path may substitute gross assets for net assets.

The SignalVault balance and Router balance appear exactly once. Adapter `totalAssets()` values only the assets and position tokens held by that adapter; it must not include Router or SignalVault balances.

At rebalance entry, SignalVault pushes its exact current underlying balance to Router before calling `rebalance`; transaction atomicity covers both actions. SignalVault measures Router underlying before and after the transfer, requires the increase to equal `fundingAssets`, and passes that measured value to `rebalance`. Router independently snapshots its entry balance, requires it to be at least `fundingAssets`, and includes the funding amount in its event/reconciliation record. Existing Router liquid and direct donations are still counted once as fee-free Idle value, but are never reported as new Vault funding. Router does not pull SignalVault's balance and SignalVault does not grant Router an unlimited allowance. This explicitly replaces the current constructor-level unlimited Vault-to-Router approval. After the push, the same assets have moved from the Vault term to the Router/Idle term, so combined pre-NAV and weights are unchanged. Withdrawals never invoke this funding step.

### 3.2 Deposit share minting

Before transferring a deposit, SignalVault snapshots net `totalAssets()` and total share supply. Shares are minted using the existing proportional rule:

```text
if supply == 0: mintedShares = depositedAssets
otherwise:      mintedShares = floor(depositedAssets * supply / netAssetsBefore)
```

The transfer occurs after the snapshot. A zero result reverts.

When a later rebalance moves deposited liquid into Upshift, the position's immediately redeemable net value may be below the deposited amount. That loss is recognized immediately in net NAV and must fit `maximumRebalanceLossBps`; it is not hidden until withdrawal and is not charged to a later depositor.

### 3.3 Partial withdrawal

Before burning shares:

```text
assetsOwed = floor(netAssetsBefore * sharesToBurn / supplyBefore)
```

The Vault sources exactly that amount through the liquidity waterfall in Section 4. If the last adapter redemption produces more than the deficit because shares are discrete, the excess remains Router liquid and therefore remains in NAV for the unburned shares. A partial withdrawal cannot transfer more than `assetsOwed`.

The owner supplies a Vault-level `minAssetsOut`. The transaction reverts if `assetsOwed < minAssetsOut` or if the waterfall cannot make `assetsOwed` available atomically.

### 3.4 Full withdrawal and dust

When `sharesToBurn == supplyBefore`, the operation is a full withdrawal:

1. consume Vault liquid;
2. ask the Router to return all Router liquid;
3. withdraw all Idle assets;
4. redeem all Upshift position shares;
5. sweep any asset dust created by integer conversion back to SignalVault;
6. burn all shares and transfer the complete resulting underlying balance to the owner.

When Upshift `positionShares() > 0`, normal full withdrawal is available only if Upshift is unpaused, previewable, and its live withdrawal limit permits all held shares to be redeemed in that transaction. Otherwise it reverts before burning shares. When the Upshift position is zero, a pause does not block a full withdrawal funded entirely by Vault/Router/Idle liquidity. The successful postcondition is zero SignalVault share supply, zero recoverable underlying in SignalVault/Router/adapters, and zero Upshift position shares. Intermediate calculations may tolerate a one-smallest-unit rounding remainder, but every recoverable underlying unit is swept to the owner; no underlying dust may become ownerless after supply reaches zero. If a non-underlying protocol position cannot be redeemed, normal full withdrawal reverts and the explicit emergency-recovery path must be used.

### 3.5 Fee recognition and rounding

Upshift's live preview, rather than a locally calculated 50 BPS constant, is the source of truth. The following are tracked separately in events and tests:

```text
protocol fee = previewedGrossAssets - previewedNetAssets

deposit share remainder =
    (depositedAssets * supplyBefore) mod netAssetsBefore
    // reported in numerator units, never subtracted from LP shares

previewed round-trip conversion loss =
    depositedUnderlying - previewRedeem(previewDeposit(depositedUnderlying)).grossAssets
    // both operands are underlying smallest units

redemption execution deviation =
    max(previewedNetUnderlying - actualUnderlyingReceived, 0)
```

All divisions round down unless a formula explicitly says `ceilDiv`. A one-smallest-unit difference is not automatically ignored: it must fall within the operation's documented rounding bound and the configured BPS tolerance.

### 3.6 Pauses and preview failure

`withdrawalsPaused()` does not by itself change the fee-adjusted marked valuation if `previewRedemption` still returns a trustworthy value; it changes immediate liquidity to zero. Consequently, all deposits and all rebalances stop while withdrawals are paused. Withdrawals fully covered by Vault/Router/Idle liquidity may continue because this is a personal single-owner Vault; they cannot consume the illiquid Upshift mark or transfer more than the owner's marked net share value.

If `previewRedemption` reverts, SignalVault cannot safely price deposits, shares, or ordinary withdrawals. Net `totalAssets()` must fail closed by reverting; it must not use stale or gross data. Deposits and rebalances also revert. Recovery is limited to the explicit owner emergency path described in Section 9.

## 4. Withdrawal model

### 4.1 Alternatives and decision

- **A. Current pro-rata withdrawal:** rejected because it pays Upshift fees even when fee-free assets can satisfy the withdrawal.
- **B. Liquidity-first waterfall:** selected.
- **C. Always unwind all strategies:** rejected for partial withdrawals because it maximizes fees and churn. It is used only for a full withdrawal.

The selected order is:

```text
SignalVault liquid
→ StrategyRouter liquid
→ IdleAdapter
→ Upshift only for the remaining deficit
```

SignalVault is personal and has one immutable owner; there is no multi-user first-mover allocation problem. Cost minimization for that owner is therefore preferable to pro-rata strategy liquidation.

### 4.2 Normal partial withdrawal algorithm

```text
netNAV       = vault.totalAssets() before any transfer or burn
assetsOwed   = floor(netNAV * shares / supply)
require assetsOwed >= ownerMinAssetsOut

useFromVault = min(vaultUnderlyingBalance, assetsOwed)
deficit      = assetsOwed - useFromVault

if deficit > 0:
    routerReturned = router.withdrawAssets(deficit)
    require routerReturned == measured increase in Vault underlying balance
    require routerReturned == deficit

burn shares
transfer exactly assetsOwed to owner
```

`withdrawAssets` first uses Router liquid, then Idle, then Upshift. If an Upshift share redemption returns more underlying than the exact deficit, Router transfers only the requested amount and retains the excess as Router liquid. If available immediate liquidity is insufficient, the whole normal withdrawal reverts.

The function is non-reentrant. Revert atomicity restores the burn and all protocol calls if any postcondition fails.

### 4.3 Upshift instant-liquidity limit

`availableLiquidity()` for Upshift is zero when withdrawals are paused. Otherwise it is the maximum after-fee amount redeemable from the adapter's held shares without exceeding the live `maxWithdrawalAmount()` gross-asset constraint. Computing it may require a preview-bounded share search; it must not assume that the limit is denominated in shares.

Normal withdrawal never requests more than `availableLiquidity()`. If the waterfall total is below `assetsOwed`, it reverts before destructive state is committed.

## 5. Differential rebalance

### 5.1 Target definition

Current and target position values are measured in net underlying assets. Targets are defined against post-operation net NAV, because moving assets into Upshift can immediately lower net-liquidation NAV.

For Coston2 P0:

```text
targetUpshift = floor(postNAV * upshiftBps / 10_000)
targetIdle    = postNAV - targetUpshift
```

Router liquid is transient execution liquidity, not a target strategy. Any residual Router liquid after rebalance counts with Idle for allocation-tolerance purposes unless it is below the defined dust bound.

### 5.2 Candidate execution

The Router snapshots:

```text
preNAV
current Upshift net assets
current Idle net assets
current position shares
protocol capability and pause state
```

It computes allocation turnover as:

```text
turnoverBps = floor(sum(abs(currentStrategyBps - targetStrategyBps)) / 2)
```

For two strategies this equals the absolute Upshift-weight change. If the change is below `minimumAllocationChangeBps`, no adapter call occurs.

### 5.3 Reducing an overweight Upshift position

The Router redeems only enough shares to put Upshift within `allocationToleranceBps` of its target; it never redeems the whole position merely because allocation changed.

Three calculation choices were considered:

1. **One-step proportional approximation:** cheap but can undershoot due to non-linear previews, fee rounding, or a changed vault exchange rate.
2. **Bounded preview iteration:** starts with a proportional ceiling estimate and refines it with at most two scaling passes.
3. **Full exact solver:** binary-searches or otherwise solves every discontinuity exactly, adding gas and failure surface without a P0 economic benefit.

P0 selects bounded preview iteration. It is simpler than a full solver while the final tolerance and post-NAV checks make approximation safe.

```text
requiredNet = currentUpshiftNet - provisionalTargetUpshift
heldShares  = adapter.positionShares()

candidateShares = ceilDiv(heldShares * requiredNet, currentUpshiftNet)
candidateShares = min(candidateShares, heldShares)

repeat at most twice:
    (gross, net) = adapter.previewRedeem(candidateShares)
    if net is within allocation tolerance of requiredNet:
        break
    if net < requiredNet:
        candidateShares = min(
            heldShares,
            ceilDiv(candidateShares * requiredNet, max(net, 1))
        )
    else:
        candidateShares = max(
            1,
            floor(candidateShares * requiredNet / net)
        )

require previewed net does not exceed live instant-liquidity capacity
minOut = floor(previewedNet * (10_000 - maximumPreviewDeviationBps) / 10_000)
actual = adapter.redeem(candidateShares, minOut)
```

The post-operation allocation check, not the approximation, is authoritative. If the position is outside tolerance or loss exceeds its budget, the entire transaction reverts.

### 5.4 Increasing an underweight Upshift position

The Router must account for the immediate exit-fee reserve on newly acquired shares. Depositing `x` underlying does not add `x` to net Upshift value.

For a candidate deposit:

```text
(previewShares, previewNetAdded) = adapter.previewDeposit(x)
postUpshift = currentUpshiftNet + previewNetAdded
postIdle    = currentIdleAndLiquid - x
postNAV     = postUpshift + postIdle
target      = floor(postNAV * upshiftBps / 10_000)
```

P0 again uses at most two proportional scaling passes to find `x` such that `postUpshift` is within allocation tolerance of `target`. The candidate is capped by available fee-free liquid. A zero-share or zero-net preview reverts. The Router derives `minSharesOut` from the preview and executes only the final candidate.

After deposit, the adapter reports actual shares from its LP-token balance delta. Router recomputes the adapter's net value from the actual position, then applies preview-deviation, post-NAV loss, and allocation-tolerance checks. No fee value is hardcoded.

### 5.5 Rebalance pseudocode

```text
function rebalance(resultHash, allocation, signedLimits, fundingAssets):
    require capability profile permits allocation
    require allocation sum == 10_000
    require cooldown elapsed
    require Router entry underlying balance >= fundingAssets

    pre = snapshotNetState()
    require previews and asset bindings are healthy

    turnover = allocationTurnover(pre, allocation)
    if turnover < minimumAllocationChangeBps:
        emit RebalanceSkipped(...)
        return pre.nav

    if Upshift is overweight beyond tolerance:
        shares = boundedSharesForRequiredNet(...)
        redeem only shares using preview-derived minAssetsOut

    if Upshift is underweight beyond tolerance:
        assets = boundedAssetsForTargetNet(...)
        deposit only assets using preview-derived minSharesOut

    move remaining execution liquid to Idle

    post = snapshotNetState()
    require adverse preview deviations are within limit
    require navLossBps(pre.nav, post.nav) <= maximumRebalanceLossBps
    require each enabled strategy is within allocationToleranceBps

    lastSuccessfulRebalance = block.timestamp
    emit Rebalanced(pre, post, allocation, turnover, realizedLoss)
    return post.nav
```

Existing position shares that remain inside the target are never deposited again and never double-counted.

## 6. Adapter interface v2

The adapter owns protocol position tokens. Router bookkeeping is not the source of truth; `positionShares()` reads the adapter's actual LP-token balance.

```solidity
interface IStrategyAdapterV2 {
    function asset() external view returns (address);
    function positionToken() external view returns (address);
    function positionShares() external view returns (uint256);

    /// Fee-adjusted marked underlying; immediately realizable when withdrawals are enabled.
    function totalAssets() external view returns (uint256 netAssets);

    /// Nominal underlying before instant-exit fees; informational only.
    function grossAssets() external view returns (uint256 grossAssets_);

    /// Maximum net underlying immediately redeemable under live protocol limits.
    function availableLiquidity() external view returns (uint256 netAssets);

    /// Explicit live state used to distinguish pause/limit conditions from a zero position.
    function protocolStatus()
        external
        view
        returns (
            bool depositsEnabled,
            bool withdrawalsEnabled,
            uint256 maxGrossWithdrawal,
            uint256 rawInstantRedemptionFee
        );

    /// Shares expected from depositing assets and their immediate net value.
    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares, uint256 immediateNetValue);

    /// Underlying before and after live exit fees for a share amount.
    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 grossAssets_, uint256 netAssets);

    function deposit(uint256 assets, uint256 minSharesOut)
        external
        returns (uint256 sharesReceived);

    function redeem(uint256 shares, uint256 minAssetsOut)
        external
        returns (uint256 assetsReceived);

    function redeemAll(uint256 minAssetsOut)
        external
        returns (uint256 assetsReceived);
}
```

`positionToken()` is required for binding checks and emergency recovery. `protocolStatus()` is required because zero available liquidity alone cannot distinguish a pause, a live limit, and an empty position. Capability-profile membership remains Router configuration rather than an adapter claim. `name()` and `riskScore()` are not required for safe execution and are excluded from this economic interface; they may live in an optional metadata interface.

### 6.1 Measurement and reconciliation

- `deposit` measures the adapter LP-token balance before and after the protocol call and returns the exact positive delta.
- `redeem` measures the adapter underlying balance before and after `instantRedeem` because that protocol function has no return value.
- The adapter transfers the measured underlying to Router and Router independently measures its own balance delta. The returned value, adapter delta, and Router delta must agree.
- `redeemAll` uses the actual `positionShares()` value, not a Router-maintained estimate.
- A zero unexpected delta reverts.

### 6.2 Allowance lifecycle

Only the underlying approval required for deposit is created. The adapter safely overwrites/reset-to-zero as required by the token, approves exactly the deposit amount, calls Upshift, then resets the allowance to zero and verifies it. No unlimited approval is allowed.

The verified Upshift redemption path does not require LP approval, so the adapter must not invent one. If a future implementation requires a different approval flow, the exact-allowance and measured-output guards cause normal operation to fail until that behavior is explicitly reviewed.

### 6.3 Access control and reentrancy

All state-changing adapter methods are `onlyRouter` and non-reentrant. The Router address, underlying asset, Upshift proxy, and expected LP token are fixed during one-time adapter initialization. Tokens cannot be rescued through the normal execution interface.

### 6.4 Proxy assumptions

The proxy address is stable but its implementation and configuration are not assumed stable. Every accounting view and every state-changing operation verifies every property that is observable through the verified protocol ABI before returning or mutating:

- live underlying asset equals the pinned asset;
- live LP-token address equals the pinned LP token;
- protocol previews and fee views are internally consistent.

Gate 2C did not verify an on-chain implementation-address getter. An EIP-1967 proxy's implementation storage cannot be read by another Solidity contract merely by knowing the slot, and `extcodehash(proxy)` does not change when only the implementation changes. The design therefore must not claim an on-chain implementation-code-hash guarantee unless Gate 4 first proves a callable introspection surface.

P0 uses two layers instead:

1. on-chain fail-closed checks for pinned asset/LP bindings, live pause/limit state, preview consistency, actual balance deltas, maximum deviation, and maximum loss; and
2. an off-chain Coston2 upgrade monitor that reads the proxy implementation slot and instructs the sole owner to pause SignalVault execution on any change.

An implementation change is never an excuse to hardcode the old fee. If the implementation changes but all observable behavior remains within the signed and one-time bounds, the on-chain transaction cannot distinguish that fact and may continue until the owner pause lands. If any observable binding or economic behavior violates a bound, that transaction reverts atomically. A changed underlying or LP token always requires a new adapter.

The later implementation therefore needs an owner-controlled `executionPaused` circuit breaker at the Vault/Router boundary. Pausing immediately blocks deposits and rebalances that can add protocol exposure. It does not bypass NAV pricing and does not block an ordinary withdrawal that can still be valued and fully paid by the liquidity waterfall. Unpausing after a proxy upgrade is a deliberate owner transaction following review and emits the observed old/new implementation identifiers supplied by the monitor; those identifiers are audit evidence, not an on-chain proof.

## 7. Router interface v2

`withdrawProRata(userShares, totalVaultShares)` is removed. Strategy proportions are an implementation concern and must not be derived from Vault share proportions.

```solidity
struct RebalanceLimits {
    uint256 minimumPostNAV;
    uint16 maximumRebalanceLossBps;
    uint16 maximumPreviewDeviationBps;
    uint16 allocationToleranceBps;
}

struct RiskConfiguration {
    uint64 minimumRebalanceInterval;
    uint16 minimumAllocationChangeBps;
    uint16 maximumRebalanceLossBps;
    uint16 maximumPreviewDeviationBps;
    uint16 allocationToleranceBps;
}

interface IStrategyRouterV2 {
    function asset() external view returns (address);
    function vault() external view returns (address);
    function riskConfigured() external view returns (bool);
    function riskConfigurationFrozen() external view returns (bool);
    function riskConfiguration() external view returns (RiskConfiguration memory);
    function totalAssets() external view returns (uint256 netAssets);
    function grossAssets() external view returns (uint256 grossAssets_);
    function executionPaused() external view returns (bool);
    function depositsEnabled() external view returns (bool);

    /// Returns and transfers exactly `assets` to SignalVault or reverts.
    function withdrawAssets(uint256 assets)
        external
        returns (uint256 assetsOut);

    /// Liquidates every position and transfers all resulting underlying.
    function withdrawAll()
        external
        returns (uint256 assetsOut);

    function rebalance(
        bytes32 resultHash,
        Allocation calldata allocation,
        RebalanceLimits calldata limits,
        uint256 fundingAssets
    ) external returns (uint256 postNetAssets);
}
```

All state-changing functions are callable only by SignalVault. SignalVault checks `depositsEnabled()` before minting; it is false when local execution is paused, an enabled protocol reports deposits or withdrawals unavailable, or an observable binding check fails. `withdrawAssets` returns exactly the requested amount on success. Adapter over-redemption stays as Router liquid. `withdrawAll` returns the measured total transferred to SignalVault. Owner slippage protection is enforced once, at the Vault's final combined output, while each Router protocol call independently uses its preview-derived internal minimum.

Rebalance limits cannot be supplied as unauthenticated caller preferences. The `resultHash`, allocation, capability profile, and limits come from one verified result and the limits are constrained to be no weaker than the Router's one-time risk configuration. The existing result `deadline` remains the only deadline; it is not duplicated inside `RebalanceLimits`.

The exact signed-message extension is:

```solidity
struct TEEResultV2 {
    address user;
    address vault;
    bytes32 intentCommitment;
    bytes32 capabilityProfile;
    Allocation allocation;
    uint256 nonce;
    uint256 deadline;
    uint256 ftsoPriceTimestamp;
    uint256 chainId;
    RebalanceLimits limits;
    bytes32 resultHash;
}
```

The flattened EIP-712 type string is:

```text
TEEResultV2(address user,address vault,bytes32 intentCommitment,bytes32 capabilityProfile,uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,uint256 minimumPostNAV,uint16 maximumRebalanceLossBps,uint16 maximumPreviewDeviationBps,uint16 allocationToleranceBps,bytes32 resultHash)
```

`resultHash` is `keccak256(abi.encode(...))` over every preceding field in exactly that order, excluding the type hash and excluding `resultHash` itself. The EIP-712 struct hash uses the same order, prefixed by `TEERESULT_V2_TYPEHASH` and including the already-computed `resultHash` last. SignalVault recomputes both, verifies signature/profile/limits/replay protection, measures and pushes its exact liquid underlying to Router, then calls `router.rebalance(resultHash, allocation, limits, fundingAssets)`. `fundingAssets` is measured runtime state and is intentionally not signed; it cannot alter the authenticated weights or weaken limits. The Coston2 profile identifier is `keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1")`.

The exact Vault-facing economic surface is:

```solidity
interface ISignalVaultEconomicV2 {
    function totalAssets() external view returns (uint256 netAssets);
    function grossAssets() external view returns (uint256 grossAssets_);

    function deposit(uint256 assets) external returns (uint256 shares);

    function withdraw(uint256 shares, uint256 minAssetsOut)
        external
        returns (uint256 assetsOut);

    function withdrawAll(uint256 minAssetsOut)
        external
        returns (uint256 assetsOut);
}
```

`withdraw` uses the partial waterfall when `shares < totalSupply()` and transfers exactly the precomputed `assetsOwed`. When `shares == totalSupply()`, it uses `router.withdrawAll()`, reconciles Router's return with the Vault balance delta, sweeps the complete Vault underlying balance, checks the owner's `minAssetsOut` against that final combined amount, then burns all shares. `withdrawAll` is an owner-only convenience for the same full branch using the owner's entire share balance. The Router never interprets the owner-level minimum.

Recommended events are:

```solidity
event AssetsWithdrawn(
    uint256 requestedAssets,
    uint256 routerLiquidUsed,
    uint256 idleAssetsUsed,
    uint256 upshiftSharesRedeemed,
    uint256 upshiftAssetsReceived
);

event RebalanceSkipped(
    bytes32 indexed resultHash,
    uint256 turnoverBps,
    uint256 minimumTurnoverBps
);

event Rebalanced(
    bytes32 indexed resultHash,
    uint256 preNAV,
    uint256 postNAV,
    uint256 fundingAssets,
    uint256 turnoverBps,
    uint256 realizedLossBps,
    uint256 upshiftSharesBefore,
    uint256 upshiftSharesAfter
);
```

Adapter deposit/redeem events must include requested input, previewed output, actual output, and the live raw fee value for auditability.

## 8. Loss and churn controls

All five controls use BPS denominator `10_000` where applicable. For P0, the immutable prospective `vaultOwner` configures them once, then `bindVault` freezes the configuration. Binding requires `riskConfigured == true`, requires the bound Vault's immutable owner to equal that same address, and permanently disables the configuration setter. Getters and a `RiskConfigurationFrozen` event make the state auditable. A new Router is required to change the frozen limits. Signed per-rebalance limits may be stricter but never weaker.

Every BPS field must be in `[0, 10_000]`; production deployment must choose a nonzero cooldown, loss limit, deviation limit, and allocation tolerance. P0 additionally requires `allocationToleranceBps <= minimumAllocationChangeBps`, so an allocation considered materially different cannot be skipped solely because the postcondition tolerance is wider. No fixed ordering is imposed between preview deviation and Vault-level loss: they have different denominators and are both enforced. `minimumPostNAV` is per-result and may be zero only when explicitly signed.

| Control | Exact measurement | Check point | Emergency behavior |
|---|---|---|---|
| `minimumRebalanceInterval` | Seconds since `lastSuccessfulRebalance`; no BPS denominator | Before any adapter call | Bypassed by withdrawals and explicit recovery, never by ordinary rebalance |
| `minimumAllocationChangeBps` | Half the sum of absolute current-to-target strategy weight changes, denominator 10,000 | Before any adapter call | Not applicable to withdrawals/recovery |
| `maximumRebalanceLossBps` | `floor(max(preNAV - postNAV, 0) * 10_000 / preNAV)` | After operations, before success | Not used by normal withdrawals; emergency recovery uses owner-provided `minAssetsOut` and an explicit emergency event |
| `maximumPreviewDeviationBps` | `floor(max(previewedNet - actualNet, 0) * 10_000 / max(previewedNet, 1))` for each external operation | Immediately after each measured protocol output | Cannot be bypassed by ordinary rebalance/withdrawal; explicit recovery may use a separately supplied minimum |
| `allocationToleranceBps` | For each enabled strategy, `floor(abs(actualNet - targetNet) * 10_000 / max(postNAV, 1))` | At successful rebalance postcondition | Not applicable to withdrawal/recovery |

Additional definitions:

- A rebalance at the same target is a no-op and makes no external protocol call.
- A below-threshold result is consumed for replay protection and emits `RebalanceSkipped`, but does not update `lastSuccessfulRebalance`; otherwise attackers could extend cooldown with no-op results.
- `minimumPostNAV` is a signed absolute floor and is checked in addition to the relative maximum loss.
- `preNAV == 0` permits only a zero-loss initial allocation path and avoids division.
- The live fee is always discovered through protocol views/previews. None of these controls assumes it is 50 BPS.
- The owner retains only circuit-breaker and explicit recovery authority after binding; it cannot change frozen economic limits or capability membership in place.

## 9. Paused, illiquid, and upgraded protocol behavior

| Condition | Deposit / rebalance | Normal withdrawal | Emergency recovery |
|---|---|---|---|
| `withdrawalsPaused() == true` | All deposits and rebalances revert; signed weights are never silently changed | Vault/Router/Idle-funded withdrawals succeed if preview still prices shares; any Upshift deficit reverts | Owner may withdraw available underlying or recover position tokens |
| `maxWithdrawalAmount()` below deficit | Rebalance reduction above the live limit reverts | Use waterfall; revert atomically if total immediate liquidity cannot meet `assetsOwed` | Owner may withdraw available liquid and explicitly recover remaining position tokens |
| `previewRedemption()` reverts | Revert and pause new Upshift exposure | Ordinary share pricing/withdrawal reverts; never use stale NAV | Owner-only recovery path; no fabricated asset value |
| Actual output below permitted preview deviation | Revert entire transaction | Revert entire transaction | Only explicit recovery with owner-specified minimum can use a wider bound |
| Proxy implementation changes | Off-chain monitor instructs owner pause; on-chain observable binding/economic checks remain mandatory | Fee-free sources may be used only if NAV preview remains trustworthy; otherwise revert | May recover position tokens after owner pause |
| Underlying or LP-token address changes | Permanently reject that adapter for normal operations; require a new adapter | Do not interact with changed binding | Recover the originally pinned tokens only |

The Router must not silently redirect an authenticated allocation when Upshift is unavailable. The signer must issue an allocation valid for the active capability profile.

Emergency recovery is a separate owner-only interface, not part of normal `IStrategyAdapterV2`. It may:

1. sweep already-held underlying;
2. attempt `redeemAll` with an explicit owner minimum;
3. if redemption is unavailable, transfer the adapter's pinned LP position tokens to an owner-selected receiver.

It bypasses cooldown, minimum allocation change, and target tolerance. It never bypasses owner authentication, reentrancy protection, pinned token identity, or balance-delta accounting. Returning LP tokens is explicitly reported as a non-underlying recovery and cannot be counted as a successful SignalVault asset withdrawal.

Recovery can be called only while `executionPaused == true`. The `minAssetsOut` value may be zero only on the distinctly named emergency selector and is emitted. If LP tokens are returned instead of underlying, the adapter is permanently marked recovered, ordinary accounting/rebalance remains disabled, and the owner may burn all remaining personal Vault shares only through an emergency close that records the LP-token amount and receiver. This path cannot be invoked as a cheaper ordinary rebalance or ordinary withdrawal.

## 10. Coston2 capability profile

### 10.1 Alternatives

- **A. Keep four strategies and move unsupported weights to Idle:** avoids a type change but silently changes the signed intent and can collapse distinct risk profiles into the same execution.
- **B. Use a Coston2-specific Upshift/Idle profile:** selected. It makes available capabilities explicit and keeps product claims honest.
- **C. Run mock Firelight and SparkDEX adapters on Coston2:** rejected because testnet execution would appear to use integrations that have not been verified.

### 10.2 Selected P0 representation

Coston2 has exactly two enabled economic destinations:

```text
Upshift: verified real integration
Idle:    underlying held without protocol exposure
```

The existing four-field `Allocation` may remain as the wire representation during migration only if the Coston2 capability validator requires `firelightBps == 0`, `sparkdexBps == 0`, and `upshiftBps + idleBps == 10_000`. Unsupported weights are rejected, never remapped. The local signer must eventually produce a Coston2-specific two-strategy semantic profile, and the profile/capability identifier must be included in the canonical signed result before deployment.

Local Anvil tests may retain mock four-strategy profiles, but their network and UI labels must say mock. No Coston2 deployment may route user assets to those mocks.

## 11. Security invariants

The later implementation must enforce and test all of the following:

1. `SignalVault.totalAssets()` is fee-adjusted marked liquidation value; gross Upshift value never prices shares, and `availableLiquidity()` separately expresses immediate capacity.
2. Every asset amount is in the pinned underlying's smallest unit; every BPS value has denominator `10_000`.
3. Post-NAV cannot fall below both the signed minimum and the relative loss budget.
4. Each adverse actual-versus-preview deviation is within `maximumPreviewDeviationBps`.
5. Adapter return values equal measured adapter deltas and measured Router deltas.
6. Adapter-reported position shares equal its actual LP-token balance.
7. Existing strategy assets are neither double-deposited nor double-counted during rebalance.
8. A partial withdrawal transfers no more than the owner's net share value.
9. A normal withdrawal is atomic: it either pays exactly `assetsOwed` or reverts.
10. Fee-free liquidity is exhausted before any Upshift redemption.
11. Upshift redemption touches no more shares than needed within the configured allocation tolerance.
12. Full withdrawal redeems all position shares and leaves zero recoverable underlying after sweeping intermediate rounding remainders.
13. Underlying allowances are exact, safely overwritten, and zero after each call.
14. No LP allowance is created unless a separately reviewed implementation requires it.
15. Unsupported Coston2 strategy weights cannot route funds to mocks or be silently moved.
16. Only SignalVault can mutate Router state, only Router can mutate adapters, and only the immutable owner can authorize Vault execution or emergency recovery.
17. Reentrancy cannot observe or create an inconsistent share/NAV state.
18. Proxy, asset, and LP-token binding changes fail closed.
19. No-op and below-threshold allocations make zero external protocol calls.
20. Full-width integer arithmetic cannot overflow, and every rounding direction is explicit.

## 12. Test specification for Gate 4 and later

### 12.1 NAV and share accounting

- Net NAV with a configurable real-fee mock: gross, explicit fee, and net are distinct.
- `grossAssets()` differs from `totalAssets()` without changing share pricing.
- Deposit after existing funds sit in Upshift mints from pre-deposit net NAV.
- A later Upshift deposit recognizes the exit-fee reserve immediately.
- Fee changes from 50 BPS to 0, 25, 100, and a high bounded value without code changes.
- Six-decimal rounding for 0, 1, 10, 100, 10,000, and 100,000 smallest units.
- Zero supply, zero NAV, zero preview shares, zero preview net, and zero-value strategy branches.
- A zero-share position short-circuits locally, while a nonzero position with zero or inconsistent redemption output fails closed.
- Preview failure makes net accounting fail closed.

### 12.2 Differential rebalance

- Upshift increase deposits only the computed delta; existing position shares remain untouched.
- Upshift decrease redeems only the computed shares; retained shares equal the postcondition.
- Increased Upshift target accounts for immediate net exit value rather than deposited gross assets.
- Bounded calculation converges within two refinements or reverts without state change.
- Solver oscillation, a zero candidate, a candidate above held shares, and failure to converge after two refinements each revert atomically.
- Exact unchanged allocation makes no adapter calls.
- Below-threshold change makes no adapter calls and does not advance cooldown.
- Cooldown rejects a qualifying early rebalance.
- Maximum loss rejects and atomically rolls back a fee-heavy rebalance.
- Absolute `minimumPostNAV` rejects even when the relative limit would pass.
- Preview deviation just below, at, and above the configured boundary.
- Allocation deviation just below, at, and above tolerance.
- Big values near `uint256` multiplication boundaries use full-precision arithmetic.
- Malicious adapter attempts to over-report shares/assets, under-transfer assets, reuse assets, or reenter.

### 12.3 Withdrawal waterfall

- Vault liquid alone satisfies withdrawal with zero Router/adapter calls.
- Router liquid is used before Idle.
- Idle is used before Upshift.
- Upshift redeems only the final deficit.
- Partial withdrawal transfers exactly the floor-valued net share amount; over-redemption remains Router liquid.
- Full withdrawal redeems all position shares and leaves zero recoverable underlying after sweeping every intermediate rounding remainder.
- Full withdrawal with nonzero Upshift shares reverts before burning when Upshift is paused, the live maximum is too low, preview reverts, or recoverable dust cannot be swept.
- Full withdrawal with zero Upshift shares succeeds from Vault/Router/Idle even when Upshift withdrawals are paused.
- Paused Upshift still permits withdrawals fully covered by earlier waterfall tiers.
- Paused Upshift rejects a withdrawal requiring Upshift.
- `maxWithdrawalAmount` below the remaining deficit causes an atomic revert.
- Gross-limit-to-net-available conversion respects fee and share rounding.
- Owner `minAssetsOut` below, equal to, and above `assetsOwed`.
- Redemption with no Solidity return is reconciled by balance deltas.

### 12.4 Protocol and proxy changes

- Live fee change is reflected by preview and NAV without redeployment.
- `withdrawalsPaused` toggles available liquidity and blocks new exposure.
- Simulated proxy implementation change triggers the off-chain alert and owner pause workflow.
- While an observed upgrade is paused, `totalAssets`, deposit minting, partial withdrawal, and full withdrawal each follow their specified fail-closed/fee-free-liquidity behavior.
- Proxy behavior change simulation returns a misleading preview and is caught by actual-delta tolerance.
- Unexpected underlying address change fails closed.
- Unexpected LP-token address change fails closed.
- A reverted preview never falls back to direct vault balance.
- Emergency underlying sweep, attempted redemption, and LP-position recovery each enforce owner access and emit distinct events.
- After LP-position recovery, ordinary NAV/rebalance stays disabled and emergency share close records position token, amount, and receiver.

### 12.5 Access, allowance, and integration

- Non-Vault callers cannot mutate Router; non-Router callers cannot mutate adapters.
- Reentrancy attempts from underlying, LP token, and protocol callbacks revert.
- Deposit allowance equals the exact amount and is zero afterward, including failure paths.
- Redemption creates no LP allowance in the verified Upshift version.
- Coston2 profile accepts only Upshift/Idle summing to 10,000.
- Any nonzero Firelight/SparkDEX Coston2 weight reverts and never touches a mock.
- Signed limits cannot be loosened by the transaction submitter.
- Every `TEEResultV2` field, including capability profile and each limit, has a one-field mutation test across Solidity and TypeScript; canonical hash, TypeHash, replay, and golden fixture remain byte-identical.
- Replay-protected below-threshold results cannot later be executed as qualifying changes.
- End-to-end local tests compare event previews, actual deltas, Router net accounting, and Vault net accounting.
- Vault-to-Router funding verifies both balance deltas, passes the measured `fundingAssets`, creates no Vault allowance, distinguishes old/donated Router liquid, counts every value once as Idle during target calculation, and rolls back on rebalance failure.
- Direct donations to Vault, Router, IdleAdapter, and UpshiftAdapter are counted once; zero-supply and full-close handling cannot strand donated underlying.
- Risk configuration tests cover caller authority, one-time initialization, freeze-on-bind, every BPS value at 0/10,000/10,001, tolerance-versus-minimum-change conflicts, and an owner mismatch between Router and Vault.

## 13. Explicit non-goals and next decision

This specification does not implement or authorize:

- `UpshiftAdapter` or any contract change;
- Router, Vault, interface, or test changes;
- local-signer/EIP-712 changes;
- Coston2 deployment;
- frontend, FTSO, TEE, or GCP work;
- final production values for any risk limit.

After this document is reviewed and approved, Gate 4 may produce a separate implementation plan. That plan must resolve the precise EIP-712 extension, off-chain proxy-upgrade monitor and owner-pause mechanics, emergency-recovery interface, and reviewed numeric P0 limits before code is written.
