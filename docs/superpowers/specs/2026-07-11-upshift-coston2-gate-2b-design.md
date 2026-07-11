# Upshift Coston2 Gate 2B Design

## Status model

Gate 2A is complete: Coston2 chain ID, FTestXRP, Upshift vault, LP token,
bytecode, asset binding, decimals, and protocol-native ABI were independently
verified. Gate 2B performs exactly one minimal live deposit and instant
redemption. Absence of standard ERC-4626 vault methods is recorded as an
interface fact, not a failure condition.

The report has four terminal statuses: `preflight_failed`, `deposit_failed`,
`deposit_confirmed_redemption_failed`, and `success`. `success` requires a
confirmed deposit, nonzero shares, confirmed instant redemption, nonzero asset
return, reconciled balances, and zero allowances for every token used.

## Protocol interface and preflight

The script uses `asset()`, `lpTokenAddress()`, `previewDeposit(address,uint256)`,
`deposit(address,uint256,address)`, `previewRedemption(uint256,bool)`,
`instantRedeem(uint256,address)`, `withdrawalsPaused()`,
`maxWithdrawalAmount()`, and `instantRedemptionFee()`. LP metadata and supply
come from the LP ERC-20. Direct FTestXRP held by the vault is reported only as a
direct balance and is never treated as NAV.

All network, address, bytecode, metadata, pause, preview, and withdrawal-limit
checks run before the private key is parsed. The amount selection starts at one
FTestXRP base unit and increases by powers of ten until both deposit and instant
redemption previews are nonzero, while remaining within the configured upper
bound and `maxWithdrawalAmount`.

## Transaction lifecycle

After read-only preflight, the wallet must have enough FTestXRP and C2FLR. The
script approves exactly the selected asset amount, confirms and re-reads the
allowance, deposits, and measures shares from the LP balance delta. It records a
confirmed transaction hash immediately after its receipt succeeds.

Before redemption it refreshes pause, fee, limit, and redemption preview data.
It first simulates `instantRedeem` without LP approval. Only an allowance-related
simulation failure permits an exact LP approval; other failures stop without
guessing. Actual returned FTestXRP is the wallet balance delta because
`instantRedeem` returns no Solidity value.

## Reconciliation and cleanup

Bigint-safe calculations distinguish deposit share deviation, redemption
preview deviation, explicit reported fee, rounding, absolute round-trip loss,
and round-trip loss BPS. Confirmed transaction data is never overwritten by a
later failure.

After any transaction-stage outcome, nonzero FTestXRP and LP allowances are
reset to zero and re-read. Cleanup failure prevents `success`. No private key or
complete environment is logged or committed.

## Scope boundary

This work does not modify SignalVault, StrategyRouter, IntentVerifier,
adapters, frontend, TEE code, or Coston2 deployment files. It does not design
Router economics or implement an UpshiftAdapter.

