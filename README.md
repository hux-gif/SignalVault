# SignalVault

> SignalVault reveals execution, but hides intent.

SignalVault turns a private XRP risk mandate into verifiable FXRP DeFi execution
on Flare. A user commits to a private risk mandate without publishing the
plaintext intent. An allocation signer produces a constrained EIP-712 result.
The onchain verifier validates identity, configuration, limits and replay
protection. The blockchain proves the resulting execution.

**Status:** active development · testnet-focused · not audited

---

## The problem

A conventional automated vault publishes enough state to make the user's intent
visible: risk thresholds, target allocation, timing preferences, drawdown
boundaries, yield expectations and rebalance intent. Once that mandate is
public, the user's strategy can be front-run, copied, or socially pressured.

SignalVault does not hide final transactions or aggregate strategy weights.
It hides the plaintext mandate that produced them.

---

## How it works

```text
Private XRP risk mandate
        ↓
Salted commitment
        ↓
Allocation signer
        ↓
EIP-712 V2 result
        ↓
Onchain verifier
        ↓
FXRP strategy execution
        ↓
Public execution evidence
```

Intent remains hidden.
Execution becomes verifiable.

---

## Privacy boundary

| Private / offchain              | Public / onchain             |
| -------------------------------- | ---------------------------- |
| plaintext intent                 | commitment                   |
| salt                             | allocation weights           |
| policy internals                 | nonce and deadline           |
| signer private key               | risk limits                  |
| uncommitted preferences          | routerConfigHash              |
| confidential-compute internals   | transactions and positions   |

Aggregate allocation weights are public; they are not in the private column.

---

## Architecture

### Implemented on `main`

| Component                | Role                                                                 |
| ------------------------ | ------------------------------------------------------------------- |
| Personal SignalVault      | Per-user FXRP vault with non-transferable shares and owner boundary |
| IntentVerifier           | EIP-712 V1 signature, field, nonce, deadline, chain and vault checks |
| IntentVerifierV2         | EIP-712 V2 signed schema with routerConfigHash and capability profile |
| StrategyRouter (P0)      | Owner-configured adapter routing with vault-only mutation surface    |
| Adapter boundary (P0)    | `IStrategyAdapter` consumed by MockStrategyAdapter and IdleAdapter  |
| local-signer             | Node HTTP service that signs allocation results from private intent |
| salted commitment        | `computeIntentCommitment` binds user, salt, nonce and chainId       |
| resultHash               | Canonical EIP-712 result hash for onchain replay protection          |
| golden fixtures          | Cross-language V1/V2 fixtures pinned to deterministic Anvil state   |
| Foundry tests            | P0 contract behavior and V2 verifier fixtures                       |
| Anvil integration        | `local-signer` end-to-end against a local Anvil node                |
| Coston2 Upshift scripts  | Read-only probes plus one real round trip against the live protocol |

### In progress on the `gate4b-upshift-adapters-v2` feature branch

Adapter V2 foundations completed on a reviewed feature branch; integration is
still in progress. The following are not on `main` yet:

- `IStrategyAdapterV2` frozen adapter interface
- `IStrategyRecoveryV2` emergency recovery interface
- `IUpshiftVaultV2` protocol-native ABI
- Fee-aware Upshift vault mock
- `IdleAdapterV2`
- `UpshiftAdapterV2`
- `StrategyRouterV2`
- `SignalVaultV2`
- V2 deployment and Anvil E2E

---

## Security model

### Implemented

- immutable personal owner boundary
- owner-only vault actions
- nontransferable shares
- salted intent commitment
- strict nonce / replay protection
- canonical resultHash
- deadline enforcement
- EIP-712 V2 domain separation
- chain binding
- Vault binding
- routerConfigHash binding
- capability profile binding
- V1/V2 signature isolation
- unsafe JSON number rejection in the local signer
- no plaintext intent onchain
- no production private key in the repository

### In progress / designed

- net-liquidation NAV
- liquidity-first withdrawals
- differential rebalancing
- dynamic fee-aware accounting
- direct underlying accounting
- exact allowance cleanup
- balance-delta reconciliation
- paused / illiquid fail-closed behavior
- independent V2 Adapter / Router / Vault deployment

---

## Current status

| Component                          | Status                                       |
| ---------------------------------- | -------------------------------------------- |
| P0 personal vault                  | Completed                                    |
| Local signer boundary              | Completed                                    |
| EIP-712 V2 verifier and fixture    | Completed                                    |
| Gate 4B Adapter V2 foundations     | Reviewed feature branch, pending integration |
| IdleAdapterV2                      | Not started                                  |
| UpshiftAdapterV2                   | Not started                                  |
| StrategyRouterV2                   | Not started                                  |
| SignalVaultV2                       | Not started                                  |
| V2 Anvil E2E                        | Not started                                  |
| SignalVault V2 Coston2 deployment   | Not deployed                                 |
| Live FCC integration               | Not integrated                               |
| Frontend evidence views             | Planned                                      |

---

## Verified Upshift observations

Independent Coston2 probes recorded the following testnet facts:

```text
Network: Flare Coston2
Chain ID: 114
instantRedemptionFee observation: 50 / 10,000
observed nominal fee: 0.5%
```

### Gate 2 economics calibration

| Input minimum units | Observed total loss |
| ------------------: | ------------------: |
|                  10 |                   1 |
|                 100 |                   1 |
|               1,000 |                   5 |
|              10,000 |                  50 |
|             100,000 |                 500 |
|           1,000,000 |               5,000 |

At 10,000 minimum units, the observed result was:

```text
shares        = 9,965
gross assets  = 9,999
net assets    = 9,950
total loss    = 50 minimum units
```

These are historical testnet observations.
Protocol fees, implementations and proxy configuration can change.
Production accounting therefore uses live previews instead of a hardcoded fee.

---

## Coston2 addresses

### External protocol contracts

These are Flare-maintained Coston2 contracts probed by the integration scripts.
They are not SignalVault deployments.

```text
Chain ID:             114
FTestXRP:             0x0b6A3645c240605887a5532109323A3E12273dc7
Upshift vault:        0x24c1a47cD5e8473b64EAB2a94515a196E10C7C81
Upshift LP token:     0xe084F7328DDaB082a139b880782dCC424d20a1DB
```

### SignalVault deployments

```text
Anvil (chainId 31337): recorded in deployments/anvil.json for local E2E only.
Coston2 (chainId 114):  not deployed yet.
```

---

## Local development

### Install

```bash
npm install
```

### TypeScript tests and type checks

```bash
npm test
npm run typecheck
```

The workspace tests can also be run individually:

```bash
npm test --workspace local-signer
npm run typecheck --workspace local-signer
npm test --workspace integration
npm run typecheck --workspace integration
```

### Foundry (Solidity)

```bash
forge build
forge test
forge fmt --check
```

> Windows note: this repository was developed with a bundled Foundry binary at
> `tools/foundry/forge.exe`. The standard `forge` command works once Foundry is
> installed; the bundled path is not required.

### Anvil end-to-end

```bash
npm run e2e:anvil --workspace local-signer
```

### Coston2 read-only probes

```bash
npm run upshift:smoke:coston2 --workspace integration
npm run upshift:economics:coston2 --workspace integration
```

The Coston2 commands require a locally configured `COSTON2_PRIVATE_KEY` for the
single real round trip; the preview sweep is private-key-free.

---

## Testing

Baseline on `main` (commit `81809db`):

```text
Vitest:   118 passed (96 local-signer, 22 integration)
Foundry:   79 passed
Typecheck: pass
Forge fmt: clean
Forge build: clean
```

All commands exit with code 0.

---

## Repository layout

```text
src/                          Solidity contracts (P0)
src/v2/                       V2 verifier, types and hashes
src/adapters/                 P0 strategy adapters
src/interfaces/               P0 router and adapter interfaces
test/                         Foundry tests (P0)
test/v2/                      Foundry tests (V2 verifier fixtures)
local-signer/                 Node HTTP allocation signer
fixtures/                     Cross-language golden fixtures
script/                       Foundry deployment scripts
integration/                  Coston2 Upshift probes and reports
deployments/                 Anvil and Coston2 deployment records
docs/superpowers/specs/      Design specifications
docs/superpowers/plans/      Task-by-task implementation plans
reports/                      Coston2 verification reports
```

---

## Threat and failure boundaries

### Implemented mitigations

- signer compromise: trusted signer is revocable via `setTrustedSigner`
- stale signatures: deadline field is enforced onchain
- replay: canonical resultHash is recorded as executed
- incorrect router configuration: immutable router binding on the vault

### Planned mitigations (Gate 4B / 4C)

- protocol fee changes: live preview reads, no hardcoded 50 BPS
- protocol pause: fail-closed accounting when `withdrawalsPaused` is true
- proxy / implementation change: binding verification around protocol calls
- preview / execution deviation: `maximumPreviewDeviationBps` signed limit
- low-liquidity withdrawal: conservative `availableLiquidity` with 64-call bound
- malicious or non-standard ERC-20 behavior: balance-delta reconciliation, no
  trusted return value from `instantRedeem`

---

## Roadmap

```text
Gate 4B — fee-aware Adapter V2
Gate 4C — differential RouterV2 and net-NAV SignalVaultV2
Gate 4D — V2 deployment, HTTP signer integration and Anvil E2E
Coston2 V2 execution evidence
Confidential Space spike
FCC migration when publicly available
Frontend private/public evidence views
```

---

## Limitations

- testnet-focused
- not audited
- no mainnet deployment
- do not use real funds
- not financial advice
- confidential compute is not live FCC
- protocol fees / configurations may change
- SignalVault V2 is not yet deployed
- unsupported strategies remain disabled

---

## License

License information has not yet been added.
