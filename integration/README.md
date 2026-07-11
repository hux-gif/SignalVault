# Coston2 Upshift smoke test

This standalone integration probes the officially documented Coston2 FTestXRP
and Upshift vault directly. It does not import or deploy SignalVault,
StrategyRouter, adapters, or the local signer.

## Verified interface

Flare's current Coston2 reference documents FTestXRP at
`0x0b6A3645c240605887a5532109323A3E12273dc7`. Flare's Upshift deposit and
instant-redemption guides document the vault at
`0x24c1a47cD5e8473b64EAB2a94515a196E10C7C81`.

The exact `ITokenizedVault` interface in Flare's starter repository is not a
standard ERC-4626 surface. Deposits use
`deposit(address assetIn,uint256 amountIn,address receiverAddr)`. Instant
redemption uses `instantRedeem(uint256 shares,address receiverAddr)` and returns
no Solidity value. Its preview is
`previewRedemption(uint256 shares,bool isInstant)`, which returns gross assets
and assets after the fee. Shares are held in the separate ERC-20 returned by
`lpTokenAddress()`.

The deployed vault currently reverts for standard `totalAssets()`,
`totalSupply()`, and `decimals()` calls. Their absence is an interface fact, not
a failure condition. The script reads decimals and total supply from the LP
ERC-20, uses protocol previews as quotes, and never treats the vault's direct
FTestXRP balance as NAV.

Gate 2A (protocol discovery and read-only verification) is complete. Gate 2B
selects the smallest base-unit amount with nonzero deposit and instant-redeem
previews, then performs one real round trip when a funded local key is present.

## Commands

Pure helper tests and type checking do not send transactions:

```powershell
npm run test --workspace integration
npm run typecheck --workspace integration
```

The live command always performs address, bytecode, chain, asset, LP metadata,
pause, limit, fee, and preview probes before parsing the private key:

```powershell
$env:COSTON2_PRIVATE_KEY = "<set locally; do not paste or commit>"
npm run upshift:smoke:coston2
```

When every mandatory preflight check passes, the transaction path uses an exact
approval, confirms deposit and `instantRedeem`, reconciles wallet balances, and
resets every allowance used to zero. LP approval is added only when a no-approval
simulation returns an explicit allowance-related failure. A report is written to
`reports/upshift-coston2-smoke.json` on either success or failure. The report is
never marked successful unless both protocol transactions confirm, balances
reconcile, returned assets are nonzero, and used allowances are verified zero.

Valid report statuses are `preflight_failed`, `deposit_failed`,
`deposit_confirmed_redemption_failed`, and `success`.

## Gate 2C economics calibration

The economics command performs a private-key-free preview sweep at 10, 100,
1,000, 10,000, 100,000, and 1,000,000 FTestXRP base units, proves the live fee
expression against every sample, and then selects either 0.01 or 0.1 FTestXRP
for one real calibration round trip:

```powershell
npm run upshift:economics:coston2
```

The script verifies the vault's EIP-1967 implementation binding to
`0x94c1851B1631769147B62f8370E851682361CEe2` and checks the implementation
runtime for `PUSH2 0x2710` at the recorded fee-path offsets. This runtime code
evidence determines the 10,000 denominator. The six live previews are
consistent with `net = gross - floor(gross * instantRedemptionFee / 10_000)`;
they are supporting observations, not a unique proof by themselves because
integer flooring can make nearby denominators observationally equivalent.
Flare's official guide confirms that the second
`previewRedemption(shares, true)` value is the after-fee amount.

Results are written to `reports/upshift-coston2-economics.json`. Direct vault
token balances are not used as NAV or share-price inputs.

## Official sources

- <https://dev.flare.network/fassets/reference>
- <https://dev.flare.network/fxrp/upshift/deposit>
- <https://dev.flare.network/fxrp/upshift/instant-redeem>
- <https://github.com/flare-foundation/flare-hardhat-starter/blob/1ce4e8cafb9159a8944a2c85dc2bd3614e4ab7bb/contracts/upshift/ITokenizedVault.sol>
