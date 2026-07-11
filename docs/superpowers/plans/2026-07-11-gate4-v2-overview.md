# Gate 4 V2 Overview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coordinate four independently reviewable Gate 4 workstreams that produce a complete, locally verified SignalVault V2 without deploying it to Coston2.

**Architecture:** V2 is a parallel contract and signer stack rooted under new `v2` paths; P0 remains untouched. Work proceeds strictly from signed schema, to adapters, to Router/Vault economics, to deployment and E2E so every consumer depends only on an already-reviewed interface.

**Tech Stack:** Solidity 0.8.27, Foundry, OpenZeppelin Contracts, TypeScript 5.9, viem 2.x, Vitest 4.x, Node.js HTTP, Anvil.

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

## Dependency Order

```text
Gate 4A
V2 signed schema and cross-language fixture
        ↓
Gate 4B
Adapter V2 interfaces and implementations
        ↓
Gate 4C
RouterV2 and SignalVaultV2
        ↓
Gate 4D
Deployment, signer integration, Anvil E2E and Coston2 readiness
```

No workstream may start against an unreviewed upstream interface. A child plan is complete only after its focused tests, relevant regressions, independent review, and listed commits are present on `main`.

## Workstream Index

| Plan | Prerequisites | Outputs | Blocking review | Expected commit sequence | Exact completion tests |
|---|---|---|---|---|---|
| [Gate 4A](./2026-07-11-gate4a-v2-verifier-and-signer.md) | Approved design commit `4e8aaa8` | V2 Solidity/TypeScript types, hash library, verifier, signer codec, `fixtures/tee-result-v2.json` | Exact field order, EIP-712 domain `SignalVault`/`2`, config/result domain isolation, every-field mutation | `test: define signalvault v2 hashes` → `feat: add intent verifier v2` → `feat: add local signer v2 schema` → `test: add v2 cross-language fixture` | `forge test --match-path test/v2/ResultHashV2.t.sol -vvv`; `forge test --match-path test/v2/IntentVerifierV2.t.sol -vvv`; `forge test --match-path test/v2/SignerGoldenFixtureV2.t.sol -vvv`; `npm test --workspace local-signer`; `npm run typecheck --workspace local-signer` |
| [Gate 4B](./2026-07-11-gate4b-upshift-adapters-v2.md) | Gate 4A types and hashes merged | `IStrategyAdapterV2`, Upshift protocol interface, Idle/Upshift adapters, fee-aware and hostile mocks | Direct-underlying accounting, composed preview, 64-call bound, exact approvals, balance-delta reconciliation, binding/reentrancy | `feat: define strategy adapter v2 interface` → `feat: add idle adapter v2` → `feat: add upshift adapter v2 views` → `feat: add upshift adapter v2 execution` → `test: harden strategy adapters v2` → `test: verify upshift withdrawal limit semantics` | `forge test --match-path 'test/v2/*AdapterV2*.t.sol' -vvv`; `npm test --workspace integration`; `npm run typecheck --workspace integration`; `forge test -vvv`; `forge build`; `forge fmt --check` |
| [Gate 4C](./2026-07-11-gate4c-router-vault-economics-v2.md) | Gate 4A and Gate 4B merged and reviewed | `IStrategyRouterV2`, `StrategyRouterV2`, `SignalVaultV2`, economic/security tests | Frozen config/hash, waterfall, differential math, signed limits, pause/recovery, zero mock routing | `feat: configure strategy router v2` → `feat: add router v2 asset accounting` → `feat: add differential rebalance v2` → `feat: add signal vault v2 accounting` → `feat: bind signed execution and recovery v2` | `forge test --match-path 'test/v2/StrategyRouterV2*.t.sol' -vvv`; `forge test --match-path 'test/v2/SignalVaultV2*.t.sol' -vvv`; `forge test -vvv`; `forge build`; `forge fmt --check` |
| [Gate 4D](./2026-07-11-gate4d-deployment-and-e2e-v2.md) | Gates 4A–4C merged and reviewed | Deployment script, V2 signer HTTP integration, canonical Anvil E2E, read-only Coston2 readiness report/command | Constructor/bind order, on/offchain config parity, complete scenario evidence, no live default transaction | `feat: add signalvault v2 deployment` → `feat: expose local signer v2 allocate` → `test: add signalvault v2 anvil e2e` → `test: add coston2 v2 readiness probe` → `docs: certify gate 4 v2 readiness` | `forge test --match-path test/v2/DeploymentFlowV2.t.sol -vvv`; `npm test`; `npm run typecheck`; `npm run e2e:v2:anvil --workspace local-signer`; `npm run readiness:v2:coston2 --workspace integration`; full Foundry suite |

## Integration Contracts Between Plans

- Gate 4A owns `AllocationV2`, `RebalanceLimitsV2`, `RiskConfigurationV2`, `TEEResultV2`, `SignalVaultHashesV2`, and their TypeScript equivalents. Downstream plans import them; they do not redefine them.
- Gate 4B owns `IStrategyAdapterV2` and `IStrategyRecoveryV2`. Gate 4C consumes these exact interfaces.
- Gate 4C owns `IStrategyRouterV2`, frozen `routerConfigHash()`, and Vault execution semantics. Gate 4D deploys and exercises them without changing their ABI.
- Gate 4D is the first workstream allowed to modify the V2 HTTP `/allocate` boundary and deployment artifacts. Its Coston2 command is read-only and cannot broadcast.

## Approved Gate 3 Coverage Matrix

| Gate 3 requirement | Owning implementation tasks | Certification evidence |
|---|---|---|
| Section 3 net NAV, gross telemetry, direct underlying, share pricing | 4B Tasks 2–4; 4C Tasks 2 and 4 | Adapter accounting suites; Router accounting; Vault deposit/withdraw suites |
| Section 4 liquidity waterfall, partial/full close, dust | 4B Tasks 2 and 4; 4C Tasks 2 and 4 | `StrategyRouterV2Withdraw.t.sol`; `SignalVaultV2Withdraw.t.sol`; Anvil partial/full scenarios |
| Section 5 differential increase/decrease and bounded refinement | 4C Task 3 | Rebalance/risk suites; Anvil delta/call-counter evidence |
| Section 6 Adapter V2 ABI, composed preview, allowances, reconciliation, proxy bindings | 4B Tasks 1–5 | Adapter accounting/liquidity/execution/security suites |
| Section 7 Router V2 ABI and events | 4C Tasks 1–3 | Configuration/accounting/rebalance suites and ABI consumed by deployment |
| Section 8 frozen loss/churn controls and signed inequalities | 4A Tasks 1–4; 4C Tasks 1, 3, and 5 | Hash/fixture mutation tests; Router risk boundaries; Vault signed execution |
| Section 9 pause, illiquidity, upgrade response, emergency recovery | 4B Tasks 3–6; 4C Tasks 2 and 5; 4D Tasks 3–4 | Pause/limit/security tests; emergency suite; Anvil and read-only readiness reports |
| Section 10 honest Coston2 capability and independent V2 deployment | 4A Task 2; 4C Tasks 1 and 5; 4D Tasks 1–4 | Unsupported-weight tests; config hash; new-address deployment; no-write readiness |
| Section 11 security invariants | Every child task review checklist | Full Foundry/npm regressions and independent review gates |
| Section 12 complete test matrix | 4A–4C focused test files; 4D Anvil/readiness | Commands in the workstream index and child completion sections |

## Review and Commit Protocol

For every child-plan task:

1. run the named RED command and preserve the expected failure;
2. implement only the code required by that task;
3. run the named GREEN command and relevant P0/V2 regressions;
4. inspect `git diff --check`, `git diff --stat`, and the complete diff;
5. request an independent reviewer to compare the diff with the task and approved design;
6. resolve every Critical or Important finding;
7. stage only the task's named files and use its exact commit message.

## Gate 4 Completion Boundary

Gate 4 planning authorizes implementation only after all five planning documents are separately approved. Gate 4 implementation ends with a green Anvil V2 E2E and a read-only Coston2 readiness result. It does not include Coston2 deployment or transactions, frontend work, FTSO product integration, GCP Confidential Space, or TEE implementation.
