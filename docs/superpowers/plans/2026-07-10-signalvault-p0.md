# SignalVault P0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a testable SignalVault P0 that accepts Coston2-compatible FXRP, protects private intent commitments, verifies a trusted local-signer allocation, and exposes the demo flow through a web UI.

**Architecture:** Each P0 `SignalVault` is a personal vault owned by one wallet; its non-transferable shares account for liquid FXRP plus one bound router's positions. The router performs whole-vault rebalances by withdrawing prior adapter shares before depositing the new allocation. A separate TypeScript service deterministically derives and signs allocations using the `IntentVerifier` address as the EIP-712 verifying contract.

**Tech Stack:** Solidity 0.8.27, Foundry, OpenZeppelin Contracts v5, TypeScript, viem, Node.js, Next.js, Vitest.

## Global Constraints

- Target network is Flare Coston2, chain ID `114`; deployments must be configurable rather than pre-claimed, and contracts must use dynamic `block.chainid`.
- Use FXRP as the only vault asset; token addresses must come from deployment configuration.
- P0 truthfulness: local-signer/local simulated TEE is a demo mode, not production FCC.
- P0 ownership: one vault instance serves one immutable `vaultOwner`; another user's intent can never rebalance its assets.
- Do not label FDC, Smart Accounts, PMW, production FCC registry, or a live Upshift vault as complete without executable proof.
- The signed allocation must bind user, vault, commitment, allocation, nonce, deadline, FTSO timestamp, chain ID, and result hash through the exact flattened `TEERESULT_TYPEHASH` in the final specification.
- `resultHash` is canonical: it is derived from every signed field except `resultHash` itself and is verified before replay state is written.
- `intentCommitment` is salted and domain-separated; plaintext intent is never emitted or stored on-chain.
- Allocation weights always total `10_000` basis points. Withdrawals redeem pro-rata across every adapter, never from idle funds alone.
- Shares are non-transferable in P0. Deposit, withdraw, and intent submission are owner-only; keepers may execute an owner-bound signed result.
- Router rebalance always withdraws all tracked adapter shares first; repeated allocations must not double-deposit existing assets.
- Adapter addresses are unique and configured once before the router is bound; a vault rejects a router already bound elsewhere.
- Execution requires a nonzero owner-submitted nonce and commitment; a trusted signer cannot create an intent from empty state.
- Router-level liquid FXRP participates in NAV and pro-rata withdrawals; zero-weight strategies are not called with `deposit(0)`.
- Share decimals mirror the FXRP token metadata.
- Share conversion uses pre-transfer assets; virtual asset/share inflation protection is production hardening, not P0.
- Every production behavior begins with a failing test.

---

## Planned file structure

- `foundry.toml` — compiler and dependency remappings.
- `src/SignalVault.sol` — FXRP custody, shares, commitments, execution entrypoint.
- `src/IntentVerifier.sol` — EIP-712 digest and trusted-signer verification.
- `src/StrategyRouter.sol` — allocation dispatch and tracked adapter balances.
- `src/interfaces/IStrategyAdapter.sol` — adapter boundary.
- `src/adapters/IdleAdapter.sol` — FXRP custody adapter.
- `src/adapters/MockStrategyAdapter.sol` — explicitly simulated Firelight/SparkDEX adapter behavior.
- `src/types/SignalVaultTypes.sol` — shared `Allocation` and `TEEResult` types.
- `test/*.t.sol` — Foundry behavior and security tests.
- `local-signer/src/*.ts` — deterministic allocation, typed-data signing, HTTP endpoint.
- `local-signer/test/*.test.ts` — signer behavior tests.
- `frontend/*` — a status-honest demo UI; UI tests cover pure intent preparation helpers.
- `README.md` and `docs/demo-script.md` — status table and a ≤3-minute demo script.
- `deployments/coston2.json` — begins with null addresses until manually verified deployment data exists.

### Task 1: Initialise repository and prove toolchain availability

**Files:**
- Create: `.gitignore`, `foundry.toml`, `package.json`

**Interfaces:**
- Produces `forge test` and `npm test` commands used by every later task.

- [ ] **Step 1: Initialise a Git repository and write the test manifests**

Use Foundry `src`, `test`, and `script` directories; use Node workspaces for `local-signer` and `frontend`. Ignore `out/`, `cache/`, `.env`, `node_modules/`, and Next build artifacts.

- [ ] **Step 2: Verify toolchains before production code**

Run: `forge --version; node --version; npm --version`

Expected: each command returns a version; otherwise report the exact unavailable tool before scaffolding its component.

- [ ] **Step 3: Commit the reproducible project setup**

Run: `git add .gitignore foundry.toml package.json && git commit -m "chore: initialise signalvault project"`

### Task 2: Define shared allocation types and write verifier tests

**Files:**
- Create: `src/types/SignalVaultTypes.sol`, `src/IntentVerifier.sol`, `test/IntentVerifier.t.sol`

**Interfaces:**
- Produces `Allocation(uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps)`.
- Produces `TEEResult(address user,address vault,bytes32 intentCommitment,Allocation allocation,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,bytes32 resultHash)`.
- Produces `verify(TEEResult calldata result, bytes calldata signature) external view returns (bool)`.

- [ ] **Step 1: Write failing tests for valid EIP-712 recovery, invalid signer, wrong chain, expired deadline, and non-10,000 BPS**

The desired test calls `verifier.hashTypedData(result)`, signs it with `vm.sign(TRUSTED_SIGNER_PK, digest)`, and expects `verify` to return true. Each single-invalid-field case must return false or revert with its documented custom error.

- [ ] **Step 2: Run the verifier test before implementation**

Run: `forge test --match-path test/IntentVerifier.t.sol -vvv`

Expected: compilation failure because `IntentVerifier` does not exist.

- [ ] **Step 3: Implement the minimum typed-data verifier**

Implement EIP-712 domain values `name = "SignalVault"`, `version = "1"`, current chain ID and verifier address. Hash the four BPS values in the typed struct; require a total of exactly `10_000`; recover with OpenZeppelin `ECDSA.recover`; compare against immutable `trustedSigner`; reject a deadline strictly before `block.timestamp` and a `result.chainId` not equal to `block.chainid`.

- [ ] **Step 4: Re-run the targeted test and then all Solidity tests**

Run: `forge test --match-path test/IntentVerifier.t.sol -vvv; forge test -vvv`

Expected: all tests PASS.

- [ ] **Step 5: Commit the verified signature boundary**

Run: `git add src/types src/IntentVerifier.sol test/IntentVerifier.t.sol && git commit -m "feat: verify signed allocations"`

### Task 3: Build FXRP vault accounting with private-intent state

**Files:**
- Create: `src/SignalVault.sol`, `test/SignalVault.t.sol`, `test/mocks/MockERC20.sol`

**Interfaces:**
- Consumes: `IntentVerifier.verify` and shared types.
- Produces `deposit(uint256 assets,address receiver) returns (uint256 shares)`, `withdraw(uint256 shares,address receiver) returns (uint256 assets)`, and `submitPrivateIntent(bytes encryptedIntent,bytes32 commitment,uint256 nonce)`.

- [ ] **Step 1: Write failing tests**

Cover: a 1:1 first deposit mints shares; a withdrawal burns shares and returns FXRP; second deposit uses proportional shares; non-owner actions and share transfers revert; empty ciphertext and zero commitment revert; submission records the latest commitment and increments the expected nonce.

- [ ] **Step 2: Run the vault test red**

Run: `forge test --match-path test/SignalVault.t.sol -vvv`

Expected: FAIL because `SignalVault` does not exist.

- [ ] **Step 3: Implement minimal custody and state transitions**

Use `SafeERC20`. Maintain ERC-20 vault `totalSupply` and balances; calculate shares with pre-transfer assets: `assets` if `totalSupply == 0 || totalAssetsBefore == 0`, otherwise `assets * totalSupply / totalAssetsBefore`. Store `latestIntentCommitment[user]` and `userIntentNonce[user]`; require submitted nonce equals `userIntentNonce[user] + 1`, then store it. Emit only ciphertext and commitment from private intent submission.

- [ ] **Step 4: Run red-to-green verification**

Run: `forge test --match-path test/SignalVault.t.sol -vvv; forge test -vvv`

Expected: all tests PASS.

- [ ] **Step 5: Commit vault accounting**

Run: `git add src/SignalVault.sol test/SignalVault.t.sol test/mocks/MockERC20.sol && git commit -m "feat: add FXRP vault and private intents"`

### Task 4: Add adapter router and execution replay protection

**Files:**
- Create: `src/interfaces/IStrategyAdapter.sol`, `src/StrategyRouter.sol`, `src/adapters/IdleAdapter.sol`, `src/adapters/MockStrategyAdapter.sol`, `test/StrategyRouter.t.sol`, `test/ReplayProtection.t.sol`
- Modify: `src/SignalVault.sol`

**Interfaces:**
- Consumes: verified `TEEResult`, `IStrategyAdapter.deposit(uint256) returns (uint256)`.
- Produces `executeTEEAllocation(TEEResult calldata result, bytes calldata signature)` and `executedResults(bytes32) -> bool`.

- [ ] **Step 1: Write failing execution tests**

Cover: a valid owner-bound signed result routes FXRP by BPS; execution before intent submission and non-canonical or replayed hashes revert; a second allocation withdraws the first allocation before redepositing; total NAV is preserved; routed and router-liquid assets can be fully withdrawn; token and adapter reentrancy and direct non-vault router calls revert; duplicate/repeated configuration fails; rounding dust is bounded and recovered by final withdrawal.

- [ ] **Step 2: Run the routing tests red**

Run: `forge test --match-path test/StrategyRouter.t.sol --match-path test/ReplayProtection.t.sol -vvv`

Expected: FAIL because router/execution methods do not exist.

- [ ] **Step 3: Implement execution with no hidden strategy logic**

Only the bound vault may call `StrategyRouter.rebalance` or `withdrawProRata`. `SignalVault` verifies owner, vault, canonical hash, commitment, nonce and EIP-712 signature, writes replay state before external calls, then invokes `rebalance`. Rebalance pulls liquid vault FXRP, withdraws all tracked adapter shares, and deposits the combined balance under the new BPS. On withdrawal, direct vault FXRP and every adapter position are redeemed proportionally. The fourth adapter absorbs allocation division remainder; withdrawal dust remains bounded and is recovered on final redemption.

- [ ] **Step 4: Verify the full contract security matrix**

Run: `forge test -vvv`

Expected: all P0 happy-path and reject-path tests PASS.

- [ ] **Step 5: Commit execution**

Run: `git add src test && git commit -m "feat: execute replay-safe signed allocations"`

### Task 5: Build local signer with deterministic allocation policy

**Files:**
- Create: `local-signer/package.json`, `local-signer/src/allocation.ts`, `local-signer/src/commitment.ts`, `local-signer/src/server.ts`, `local-signer/test/allocation.test.ts`, `local-signer/.env.example`

**Interfaces:**
- Consumes `{ user, vault, plainIntent, nonce, intentCommitment }`.
- Produces `{ result: TEEResult, signature: Hex }` from `POST /allocate`.

- [ ] **Step 1: Write failing pure-function tests**

Verify Safe yields `4000/2000/0/4000`, Balanced `5000/2000/1000/2000`, Aggressive `5000/2000/2500/500`; stale FTSO and restrictive drawdown shift BPS only from SparkDEX to Idle; all outputs total 10,000; commitment uses `keccak256(abi.encode(domain,user,plainIntentHash,salt,nonce,chainId))` semantics.

- [ ] **Step 2: Run tests red**

Run: `npm test --workspace local-signer`

Expected: FAIL because the allocation and commitment modules do not exist.

- [ ] **Step 3: Implement the smallest deterministic signer**

Use viem only. Read `SIGNER_PRIVATE_KEY`, `CHAIN_ID`, and `VAULT_ADDRESS` from environment; reject mismatched vault/chain and commitment; use the exact EIP-712 type definition from `IntentVerifier`; return no plaintext intent in the response beyond allocation inputs necessary for local demo logs.

- [ ] **Step 4: Verify local signer**

Run: `npm test --workspace local-signer`

Expected: all tests PASS.

- [ ] **Step 5: Commit local simulated TEE mode**

Run: `git add local-signer && git commit -m "feat: add deterministic local allocation signer"`

### Task 6: Build the truthful demo UI and supporting documentation

**Files:**
- Create: `frontend/package.json`, `frontend/app/page.tsx`, `frontend/lib/intent.ts`, `frontend/lib/contracts.ts`, `frontend/test/intent.test.ts`, `README.md`, `docs/demo-script.md`, `deployments/coston2.json`

**Interfaces:**
- Consumes frontend intent form values and signer `/allocate` response.
- Produces encrypted payload bytes, salted commitment, and transaction links supplied by wallet receipts.

- [ ] **Step 1: Write failing intent preparation tests**

Verify generated salts differ, commitments bind wallet and nonce, an intent serialized into the encrypted payload is not rendered as plaintext in public-event preview, and the public/private mapping has exactly the stated fields.

- [ ] **Step 2: Run UI helper tests red**

Run: `npm test --workspace frontend`

Expected: FAIL because `frontend/lib/intent.ts` does not exist.

- [ ] **Step 3: Implement the UI without overclaiming**

Include deposit/withdraw, intent form, submit intent, request allocation, execute allocation, public-versus-private table, and explorer link. The status card must call the signer `Local simulated TEE / local-signer (demo)`; Firelight and SparkDEX are `Simulated`; FDC, Smart Accounts, PMW, and production FCC are `Roadmap`. `deployments/coston2.json` begins with null addresses and no “deployed” claim until a deployment transaction is recorded.

- [ ] **Step 4: Write README and demo script from facts only**

README must distinguish Live / Strong Integrations / Simulated for Demo / Roadmap. Its submission checklist must say that DoraHacks fields have not been fully confirmed programmatically and must be reviewed manually before submission. The demo script must fit three minutes and show ciphertext in a Coston2 explorer only after deployment.

- [ ] **Step 5: Run the final checks**

Run: `forge test -vvv; npm test --workspace local-signer; npm test --workspace frontend`

Expected: all available test suites PASS.

- [ ] **Step 6: Commit presentation materials**

Run: `git add frontend README.md docs/demo-script.md deployments/coston2.json && git commit -m "feat: add honest SignalVault demo UI"`

## Self-review

- P0 custody, shares, salted commitment, ciphertext event, nonce/deadline/result replay defense, signed result verification, routing, signer service, UI, and explorer proof are each covered by a task.
- FTSO and Upshift are excluded from a false-live claim; they remain configurable follow-on integrations.
- FDC, Smart Accounts, PMW, and production FCC are roadmap-only.
- All interfaces use the same `TEEResult` fields and 10,000 BPS invariant.
