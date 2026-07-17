# SignalVault

> SignalVault reveals execution, but hides intent.

SignalVault turns a private XRP risk mandate into verifiable FXRP DeFi execution
on Flare. A user commits to a private risk mandate without publishing the
plaintext intent. An allocation signer produces a constrained EIP-712 result.
The onchain verifier validates identity, configuration, limits and replay
protection. The blockchain proves the resulting execution.

**Status:** active development · testnet-focused · not audited

**Live Coston2 evidence dashboard:** https://hux-gif.github.io/SignalVault/

**Demo video:** recorded locally; public upload remains a user-owned action

**Final verification:** https://github.com/hux-gif/SignalVault/actions/runs/29501160815

**Frontend deployment:** https://github.com/hux-gif/SignalVault/actions/runs/29501161290

### Live deployment

- SignalVaultV2: `0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898`
- StrategyRouterV2: `0x1d64CE2a9293F248a7298135932bE9674d39a764`
- IntentVerifierV2: `0x2C7b2a5620fbf25a65c81257F16b8437f5Af492a`
- IdleAdapterV2: `0xD0Ee1664e21aE9529f6cCCf94A70C29C7396fFD8`
- UpshiftAdapterV2: `0x6bF0f5f7e9595171246C888F9AC10c830e1D81Db`

Verified transactions: [Deposit](https://coston2-explorer.flare.network/tx/0x245f207e77f19c3246e84c1df7f1e33794af124263ceffe07850832008376d79) · [Commitment](https://coston2-explorer.flare.network/tx/0x8424df2d4833dd07521c529654b3df54a77291fbcd8141cf77fc31d253dcdd27) · [Rebalance](https://coston2-explorer.flare.network/tx/0xe38ed07e2f77a03b29cc6ba57bc09cfbc2e18f8eda43a7819510f2b019ec2d23) · [Withdrawal](https://coston2-explorer.flare.network/tx/0xe550cd5bde1ae67f15e1ae29f16eaeefe08a1410d18dde9a889a7872d790d1ba)

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

### V1/P0 baseline

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
| Foundry tests            | P0 behavior plus V2 verifier, adapter and StrategyRouterV2 suites   |
| Anvil integration        | `local-signer` end-to-end against a local Anvil node                |
| Coston2 Upshift scripts  | Read-only probes plus one real round trip against the live protocol |

### Implemented on `main`

The reviewed Adapter V2 foundation and the complete StrategyRouterV2 are
implemented on the public default branch:

- `IStrategyAdapterV2` frozen adapter interface
- `IStrategyRecoveryV2` emergency recovery interface
- `IUpshiftVaultV2` protocol-native ABI
- Fee-aware Upshift vault mock
- `IdleAdapterV2`
- `UpshiftAdapterV2`
- `StrategyRouterV2` with configuration freeze, accounting, planning, execution, withdrawal, recovery and security suites
- `SignalVaultV2` with personal share accounting and authenticated V2 execution
- `FTSOv2Reader` with freshness validation
- FCC-compatible Mode B local signer boundary (simulated attestation, not hardware TEE)
- three-screen frontend presentation
- Canonical integration test using real adapters and the production Router

The V2 system is deployed on Coston2 with a verified FXRP/Upshift product E2E.
The frontend is a live evidence dashboard with wallet and network verification,
published through GitHub Pages.

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

### Implemented on the Gate 4B feature branch

- dynamic fee-aware accounting
- direct underlying accounting
- exact allowance cleanup
- balance-delta reconciliation
- paused / illiquid fail-closed behavior

### In progress / designed

- independent V2 Adapter / Router / Vault deployment on Coston2
- wallet-connected frontend and live E2E evidence
- migration from Mode B operator signing to real FCC attestation

---

## Current status

| Component                          | Status                                       |
| ---------------------------------- | -------------------------------------------- |
| P0 personal vault                  | Completed                                    |
| Local signer boundary              | Completed                                    |
| EIP-712 V2 verifier and fixture    | Completed                                    |
| Gate 4B Tasks 1–6                  | Complete, reviewed and frozen                |
| Gate 4B full-branch rereview       | Passed                                       |
| IdleAdapterV2                      | Deployed on Coston2                           |
| UpshiftAdapterV2                   | Deployed on Coston2                           |
| StrategyRouterV2 Tasks 1–10        | Complete, reviewed and locally verified      |
| StrategyRouterV2 integration suite | 4 tests passing with real adapters          |
| SignalVaultV2                       | Implemented; final review tracked in CI      |
| V2 Anvil E2E                        | Script implemented; Coston2 live E2E verified |
| SignalVault V2 Coston2 deployment   | Deployed; addresses in deployments/coston2-v2.json |
| FCC Mode B                          | Local simulated attestation; not hardware TEE |
| Frontend evidence views             | Live RPC dashboard on GitHub Pages            |

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
Coston2 (chainId 114): deployed; see `deployments/coston2-v2.json`.
```

---

## Local development

### Install

Clone with pinned Solidity dependencies:

```bash
git clone --branch main --recurse-submodules https://github.com/hux-gif/SignalVault.git
```

For an existing clone:

```bash
git submodule update --init --recursive
```

Install the JavaScript workspace from the lockfile:

```bash
npm ci
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
forge test -vvv
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
npm run verify:upshift-limit:coston2:pinned
```

The fixed read-only evidence command uses Coston2 block `32788892` and requires
no wallet or private key. It deterministically regenerates
`reports/upshift-withdrawal-limit-semantics.json`; the expected SHA-256 is
`7E72A91F7F9C8B1BFC13D4F3B47B39F726880C3F5A213E547BEE3EC7A1CF6C3A`.
No write transaction is broadcast. The report intentionally retains
`UNRESOLVED` withdrawal-limit semantics and an `INSUFFICIENT_EVIDENCE` adapter
assessment.

The smoke/economics commands include the separately invoked historical testnet
round trip and require a locally configured `COSTON2_PRIVATE_KEY`. Never commit
that value.

---

## Testing

Current reproducible baseline:

```text
JavaScript/TypeScript: 207 passed (109 local-signer, 31 frontend, 67 integration)
Foundry: complete suite passed in clean-checkout CI
Typecheck: pass
Frontend build: pass
Forge fmt/build/build --sizes/test/lint: pass
```

Canonical verification: https://github.com/hux-gif/SignalVault/actions/runs/29501160815

Frontend deployment: https://github.com/hux-gif/SignalVault/actions/runs/29501161290

An exact Foundry count is intentionally not quoted until authenticated workflow
log export is stored with the repository. This retires older conflicting counts.

---

## Repository layout

```text
src/                          Solidity contracts (P0)
src/v2/                       V2 verifier, adapters and StrategyRouterV2
src/adapters/                 P0 strategy adapters
src/interfaces/               P0 router and adapter interfaces
test/                         Foundry tests (P0)
test/v2/                      Foundry tests (V2 verifier, adapters and Router)
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

### Implemented mitigations (Gate 4B)

The following Router-level mitigations are now implemented and locally verified:

- protocol fee changes: live preview reads, no hardcoded 50 BPS
- protocol pause: NAV views continue to value a valid position while protocol
  liquidity and redemption execution are disabled; invalid nonzero position
  previews still fail closed
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
Hardware-backed FCC execution and remote attestation
Independent security audit
Flare mainnet/FAssets production readiness
Pilot-user validation and operational monitoring
Broader adapters only after security review and demonstrated demand
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
- SignalVault V2 is deployed to Coston2 with one recorded live E2E flow
- unsupported strategies remain disabled
- after `positionRecovered` becomes true, recovery cannot be invoked again;
  LP tokens sent to that adapter afterward may be permanently locked, so Router
  and operational flows must never send new LP tokens to a recovered adapter

---

## License

SignalVault is licensed under the [MIT License](LICENSE).
