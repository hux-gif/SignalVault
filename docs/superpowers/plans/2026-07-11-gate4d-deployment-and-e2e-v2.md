# Gate 4D Deployment and E2E V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the independently deployed V2 stack through deterministic deployment tests, the real local HTTP `/allocate` boundary, a canonical Anvil E2E, and a read-only Coston2 readiness gate.

**Architecture:** Deployment follows an explicit Router-first, Vault-last, bind-and-freeze sequence that resolves address dependencies before any signature exists. The V2 local signer reads the frozen on-chain configuration, Anvil uses the fee-aware Upshift mock, and Coston2 readiness never broadcasts.

**Tech Stack:** Solidity 0.8.27, Foundry scripts/tests, TypeScript 5.9, viem 2.x, Vitest 4.x, Node HTTP, Anvil, Coston2 read-only JSON-RPC.

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

## Exact Deployment Order and Local Risk Configuration

The deployment transaction sequence is:

```text
1. resolve existing underlying asset
2. deploy IntentVerifierV2(trustedSigner)
3. deploy StrategyRouterV2(asset, vaultOwner)
4. deploy IdleAdapterV2(asset, router)
5. deploy UpshiftAdapterV2(asset, router, upshiftVault)
6. router.configureAdapters(upshiftAdapter, idleAdapter)
7. router.configureRisk(riskConfiguration)
8. deploy SignalVaultV2(asset, router, verifier, vaultOwner)
9. router.bindVault(vault)
10. read frozen riskConfigurationHash and routerConfigHash
11. configure/start V2 signer only after step 10
```

Steps 2–9 execute from `vaultOwner`; Router ownership and Vault ownership therefore match. Vault construction accepts only an unbound Router with the expected asset. Binding has the Vault address required to freeze `routerConfigHash`, so no circular address is guessed and no allocation is signed before the hash exists.

Anvil uses this reviewed nonzero test configuration:

```text
minimumRebalanceInterval       = 300 seconds
minimumAllocationChangeBps     = 100
maximumRebalanceLossBps        = 100
maximumPreviewDeviationBps     = 25
allocationToleranceBps         = 25
```

These values certify local behavior only. A later Coston2 deployment authorization must approve its values explicitly; this plan never broadcasts them to Coston2.

### Task 1: Independent V2 Deployment Script and Constructor/Binding Tests

**Files:**
- Create: `script/v2/DeploySignalVaultV2.s.sol`
- Create: `test/v2/DeploymentFlowV2.t.sol`
- Create: `test/v2/mocks/SixDecimalAssetV2.sol`

**Interfaces:**
- Consumes: all reviewed Gate 4A–4C constructors/configuration methods and fee-aware Upshift mock.
- Produces: `DeploySignalVaultV2.Deployment`, `deployContracts`, exact bind/freeze order, and deployment invariant assertions.

- [ ] **Step 1: Write failing deployment-order tests.**

```solidity
function testDeploymentFreezesConfigBeforeAnySignedAllocation() external {
    Deployment memory d = deployer.deployContracts(asset, protocol, signer, owner, localRisk());
    assertEq(d.router.vault(), address(d.vault));
    assertTrue(d.router.riskConfigurationFrozen());
    assertEq(d.router.routerConfigHash(), SignalVaultHashesV2.computeRouterConfigHash(
        block.chainid, address(d.vault), address(d.router), address(asset),
        address(d.upshift), address(d.idle), d.router.capabilityProfile(),
        d.router.riskConfigurationHash(), 1
    ));
}

function testV2AddressesAreIndependentFromP0() external {
    assertTrue(address(d.vault) != address(p0Vault));
    assertTrue(address(d.router) != address(p0Router));
    assertTrue(address(d.verifier) != address(p0Verifier));
}
```

Also test wrong owner, bind before risk, configure twice, non-six-decimal asset support in generic arithmetic, six-decimal runtime metadata, and all immutable bindings.

The test `setUp` deploys a P0 baseline through the existing `DeploySignalVault` only to obtain comparison addresses; it never modifies or upgrades those P0 instances.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/DeploymentFlowV2.t.sol -vvv`

Expected: FAIL because the V2 deploy script is absent.

- [ ] **Step 3: Implement the exact sequence.**

`run()` reads only public addresses/values from environment and never reads a private key itself; Foundry broadcast credentials remain outside source. `deployContracts` follows steps 1–10 above and `_assertDeployment` checks code, asset, owner, adapters, capability, risk freeze, config hashes, verifier signer, zero Vault→Router allowance, zero adapter protocol allowance, and no P0 address reuse.

- [ ] **Step 4: Run GREEN and deployment regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/DeploymentFlowV2.t.sol -vvv`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/DeploymentFlow.t.sol -vvv`

Expected: V2 and P0 deployment suites PASS.

- [ ] **Step 5: Review and commit Task 1.**

Review checklist: order matches 1–11; owner performs configuration/bind; config hash is read after bind; no signature precedes hash; no P0 address or source is changed; no unlimited allowance or secret exists.

```powershell
git diff --check
git add script/v2/DeploySignalVaultV2.s.sol test/v2/DeploymentFlowV2.t.sol test/v2/mocks/SixDecimalAssetV2.sol
git commit -m "feat: add signalvault v2 deployment"
```

Request independent review and resolve every Critical or Important finding before Task 2.

### Task 2: Local Signer V2 Allocation Policy and HTTP Boundary

**Files:**
- Create: `local-signer/src/v2/allocation.ts`
- Create: `local-signer/src/v2/config.ts`
- Create: `local-signer/src/v2/service.ts`
- Create: `local-signer/src/v2/server.ts`
- Create: `local-signer/src/v2/onchainConfig.ts`
- Create: `local-signer/test/v2/allocation.test.ts`
- Create: `local-signer/test/v2/onchainConfig.test.ts`
- Create: `local-signer/test/v2/service.test.ts`
- Create: `local-signer/test/v2/server.test.ts`
- Create: `local-signer/.env.v2.example`
- Modify: `local-signer/package.json`

**Interfaces:**
- Consumes: Gate 4A V2 types/hashes/typed data/JSON codec and frozen on-chain profile/config values.
- Produces: V2 `POST /allocate`, `loadVerifiedOnchainConfigV2`, `createAllocationServiceV2`, `createServerV2`, and exact two-strategy policy.

- [ ] **Step 1: Write failing signer/service tests.**

```ts
it.each([
  [0, { upshiftBps: 3000, firelightBps: 0, sparkdexBps: 0, idleBps: 7000 }],
  [1, { upshiftBps: 5000, firelightBps: 0, sparkdexBps: 0, idleBps: 5000 }],
  [2, { upshiftBps: 7000, firelightBps: 0, sparkdexBps: 0, idleBps: 3000 }],
])("emits only the Coston2 capability for risk %i", (riskLevel, expected) => {
  expect(allocateV2({ riskLevel })).toEqual(expected);
});

it("signs configured profile/config and rejects caller mutation", async () => {
  const output = await service(validRequest);
  expect(output.result.capabilityProfile).toBe(config.capabilityProfile);
  expect(output.result.routerConfigHash).toBe(config.routerConfigHash);
  await expect(service({ ...validRequest, routerConfigHash: otherHash })).rejects.toThrow(/config/);
});

it("rejects plaintext, commitment, nonce, chain, vault, verifier, and FTSO mismatches", async () => {
  await expect(service({ ...validRequest, nonce: "8" })).rejects.toThrow(/commitment/);
  await expect(service({ ...validRequest, chainId: "1" })).rejects.toThrow(/chain/);
  await expect(service({ ...validRequest, ftso: { price: "0", timestamp: "1000" } }))
    .rejects.toThrow(/FTSO/);
});

it.each([
  "asset", "vault", "upshiftAdapter", "idleAdapter", "capabilityProfile",
  "maximumRebalanceLossBps", "maximumPreviewDeviationBps", "allocationToleranceBps",
  "riskConfigurationHash", "routerConfigVersion", "routerConfigHash",
  "vaultAsset", "vaultRouter", "vaultVerifier", "trustedSigner"
])("refuses startup when %s differs from the deployment/config/private key", async (field) => {
  const chain = verifiedChainFixture();
  chain.mutate(field);
  await expect(loadVerifiedOnchainConfigV2(chain.client, artifact, env)).rejects.toThrow(field);
});
```

`onchainConfig.test.ts` supplies a deterministic fake public client for every read named above. Its `trustedSigner` case derives the expected address with `privateKeyToAccount(env.PRIVATE_KEY).address`, returns a different address from Verifier `trustedSigner()`, and proves startup rejects; no test stores or logs the key. Separate cases alter each frozen risk field while leaving the artifact risk hash stale, and alter only the artifact verifier while leaving `vault.verifier()` intact, so neither comparison can pass accidentally through config-hash recomputation.

Server tests require string parsing for every uint256, sanitized 400/413/500 behavior, exactly `{result,signature}` response keys, and no private key/plain intent/salt in output or error.

- [ ] **Step 2: Run RED.**

Run: `npm test --workspace local-signer -- --run test/v2/allocation.test.ts test/v2/onchainConfig.test.ts test/v2/service.test.ts test/v2/server.test.ts`

Expected: FAIL because V2 server/service/allocation modules are absent.

- [ ] **Step 3: Implement V2-only signer wiring.**

V2 startup config requires private key, RPC URL, deployment artifact path, maximum loss BPS, maximum preview deviation BPS, allocation tolerance BPS, FTSO max age, TTL, and the existing `LOG_PLAINTEXT_INTENT` rule. `loadVerifiedOnchainConfigV2` reads `deployments/anvil-v2.json`; queries Router `asset`, `vault`, adapter addresses, capability profile, `riskConfiguration()`, risk hash, config version, and config hash; queries Vault `asset()`, `router()`, and `verifier()`; and queries Verifier `trustedSigner()`. It then requires exact equality among the artifact, configured signer maxima, and every queried address/value, recomputes both `riskConfigurationHash` and `routerConfigHash` offchain, and refuses startup on any mismatch. In particular, all three configured signed maxima must equal the frozen Router risk fields, and the artifact verifier must equal `vault.verifier()` rather than merely being a nonzero deployed address. Its verified output supplies `V2ValidationContext`; callers cannot supply or loosen it.

Service reuses the existing pure `computeIntentCommitment` module and validation rules: validate nonzero user/Vault/verifier addresses; positive nonce/chain/FTSO price/timestamp; no future or stale FTSO; configured Vault/verifier/chain equality; recomputed salted commitment equality over plaintext, nonce, user, and chain; configured profile/config equality; and deadline overflow. The request carries decimal-string `minimumPostNAV`; the local simulated signer validates it but production TEE policy remains out of scope. Plaintext logging remains disabled by default and can be enabled only when `LOG_PLAINTEXT_INTENT=true` and `NODE_ENV=development`; plaintext/salt never enter responses or sanitized errors. Service rejects nonzero unsupported weights, recomputes canonical hash, and signs domain version `2`. P0 server/modules remain untouched.

- [ ] **Step 4: Run GREEN and signer regressions.**

Run: `npm test --workspace local-signer -- --run test/v2/allocation.test.ts test/v2/onchainConfig.test.ts test/v2/service.test.ts test/v2/server.test.ts`

Run: `npm test --workspace local-signer`

Run: `npm run typecheck --workspace local-signer`

Expected: all V2/P0 signer tests PASS and typecheck exits 0.

- [ ] **Step 5: Review and commit Task 2.**

Review checklist: profile has only Upshift/Idle; startup artifact, every Router getter, the full frozen risk struct, Vault asset/router/verifier, and Verifier signer reconcile; plaintext commitment and all request context are recomputed; FTSO and nonce boundaries match P0 hardening; config values are not caller-loosened; domain is V2; unsafe JSON numbers reject; dev-only logging cannot leak through responses/errors; P0 server behavior stays green.

```powershell
git diff --check
git add local-signer/src/v2 local-signer/test/v2 local-signer/.env.v2.example local-signer/package.json
git commit -m "feat: expose local signer v2 allocate"
```

Request independent review and resolve every Critical or Important finding before Task 3.

### Task 3: Canonical Anvil V2 HTTP E2E

**Files:**
- Create: `local-signer/src/v2/e2e.ts`
- Modify: `local-signer/package.json`
- Create at command runtime: `deployments/anvil-v2.json`
- Create at command runtime: `reports/gate4-v2-anvil-e2e.json`

**Interfaces:**
- Consumes: V2 deployment artifacts, fee-aware Upshift mock, `createServerV2`, viem public/wallet clients, Anvil test keys only.
- Produces: `npm run e2e:v2:anvil --workspace local-signer` and a bigint-string evidence report.

The TypeScript E2E is the sole Anvil orchestrator. It reads compiled JSON from `out/`, deploys every contract directly with viem in steps 1–9 of this plan, waits for each receipt, then writes this artifact before starting the signer:

```ts
interface AnvilV2Deployment {
  schemaVersion: 1;
  network: "anvil";
  chainId: "31337";
  asset: Address;
  protocol: Address;
  lpToken: Address;
  verifier: Address;
  router: Address;
  upshiftAdapter: Address;
  idleAdapter: Address;
  vault: Address;
  capabilityProfile: Hex;
  riskConfigurationHash: Hex;
  routerConfigHash: Hex;
  routerConfigVersion: "1";
  transactions: Record<string, { hash: Hex; blockNumber: string }>;
}
```

`script/v2/DeploySignalVaultV2.s.sol` remains the production deployment implementation and is certified by Task 1; the E2E does not invoke or parse Foundry broadcast directories. On exit, the HTTP server closes in `finally`; restarting Anvil supplies full chain cleanup.

- [ ] **Step 1: Write the E2E with an intentional first failing checkpoint.**

Initially stop after deployment with:

```ts
if (onchainConfigHash !== offchainConfigHash) {
  throw new Error(`routerConfigHash mismatch: ${onchainConfigHash} != ${offchainConfigHash}`);
}
throw new Error("RED: V2 allocation scenarios not implemented");
```

The script must use only standard deterministic Anvil keys, label them test-only, deploy via viem, write the artifact schema above, call `loadVerifiedOnchainConfigV2`, start `/allocate` only after verification, and never read Coston2 credentials.

- [ ] **Step 2: Run RED.**

Start Anvil in a separate terminal using `D:\xhy\tools\foundry\anvil.exe --chain-id 31337`, then run:

`npm run e2e:v2:anvil --workspace local-signer`

Expected: deployment/config parity succeeds, then command exits nonzero with `RED: V2 allocation scenarios not implemented`.

- [ ] **Step 3: Implement the complete scenario sequence.**

Mint and deposit `1_000_000` six-decimal smallest units. For each signed result set `minimumPostNAV = floor(preNAV * (10_000 - signed.maximumRebalanceLossBps) / 10_000)`. Execute and assert in this order: deployment invariants; on/offchain risk/config hash parity; deposit; preview matrix at raw fees `0`, `25`, `50`, `100`, and `1_000`; reset fee to `50`; first `5000/0/0/5000` allocation; identical no-op with zero protocol calls; below-threshold `5050/0/0/4950` consumed without cooldown update; advance Anvil by exactly 301 seconds using `evm_increaseTime` followed by `evm_mine`; increase to `6000/0/0/4000` moving only delta; decrease to `4000/0/0/6000` redeeming only delta; liquidity-first partial withdrawal; replay rejection; one-at-a-time signed limit/profile/config mutations; protocol pause behavior; live mock fee change from 50 to 100 without redeployment; full withdrawal; zero share supply, adapter shares, recoverable underlying, and allowances.

Every transaction receipt, block, before/after balance, preview, call counter, config hash, and terminal assertion is serialized as strings in the report.

- [ ] **Step 4: Run GREEN twice from fresh Anvil state.**

Restart Anvil for each run, then run: `npm run e2e:v2:anvil --workspace local-signer`

Expected: exit 0 twice; both reports end `status: "success"`; no state depends on the previous run.

Run: `npm test --workspace local-signer && npm run typecheck --workspace local-signer`

Expected: signer unit/regression tests PASS.

- [ ] **Step 5: Review and commit Task 3.**

Review checklist: viem is the only Anvil orchestrator; every deployment receipt/address is recorded; artifact schema and Router getters reconcile before signer startup; real HTTP boundary used; exact scenario order present; no direct signer call bypasses HTTP; server closes in `finally`; no Coston2 transaction; delta-only assertions inspect balances/counters; final allowances and balances are zero; report contains no key.

```powershell
git diff --check
git add local-signer/src/v2/e2e.ts local-signer/package.json deployments/anvil-v2.json reports/gate4-v2-anvil-e2e.json
git commit -m "test: add signalvault v2 anvil e2e"
```

Request independent review and resolve every Critical or Important finding before Task 4.

### Task 4: Read-Only Coston2 V2 Readiness Gate

**Files:**
- Create: `integration/signalvault-v2-coston2-readiness.ts`
- Create: `integration/signalvault-v2-coston2-readiness.test.ts`
- Modify: `integration/package.json`
- Modify: `package.json`
- Create at command runtime: `reports/signalvault-v2-coston2-readiness.json`

**Interfaces:**
- Consumes: official FTestXRP/Upshift addresses, Gate 2 reports, V2 protocol ABI, reviewed risk/profile constants.
- Produces: `npm run readiness:v2:coston2`, a read-only report, and no deployment/broadcast.

- [ ] **Step 1: Write failing readiness-state tests.**

```ts
it("cannot be ready without Anvil evidence and live bindings", () => {
  expect(deriveReadiness({ anvilPassed: false, chainId: 114, bindingsValid: true,
    previewsValid: true, conservativeLimitApplied: true })).toBe("not_ready");
});

it("serializes all integers as strings", () => {
  expect(stringifyReadiness({ limit: 9007199254740993n })).toContain("9007199254740993");
});
```

- [ ] **Step 2: Run RED.**

Run: `npm test --workspace integration -- --run signalvault-v2-coston2-readiness.test.ts`

Expected: FAIL because readiness helpers are absent.

- [ ] **Step 3: Implement a no-key, no-write readiness probe.**

The module imports no wallet client and rejects any configured private-key environment variable. It checks chain 114, code, proxy implementation slot, asset/LP bindings, decimals, pause, fee view, composed deposit/redeem previews, conservative gross/net limit, prior successful Anvil report, and zero Firelight/SparkDEX capability. It compares the current implementation-slot value with the Gate 2C baseline and records `implementation_changed` plus old/new addresses when they differ; that state is not ready and instructs owner pause/review. It records `ready_for_authorized_deployment` only when every read-only and local prerequisite passes; this status is not a deployment authorization.

The probe always writes its report. The default `readiness:v2:coston2` command exits 0 only for exact status `ready_for_authorized_deployment` and exits nonzero for `not_ready`, `implementation_changed`, or probe failure. An optional pure unit-test helper may classify non-ready states without turning them into command success.

- [ ] **Step 4: Run GREEN and explicit readiness command.**

Run: `npm test --workspace integration -- --run signalvault-v2-coston2-readiness.test.ts`

Run: `npm run readiness:v2:coston2`

Expected: tests PASS; command exits 0 only when the report status is exactly `ready_for_authorized_deployment`; Coston2 transaction count is zero. Any other status blocks Gate 4 completion while preserving the report.

Run: `npm run typecheck --workspace integration`

Expected: typecheck exits 0.

- [ ] **Step 5: Review and commit Task 4.**

Review checklist: no wallet/private key/write method; Anvil evidence required; command success requires exact ready status; readiness is not authorization; conservative limit remains; reports contain no secret; direct Upshift vault balance is not NAV.

```powershell
git diff --check
git add integration/signalvault-v2-coston2-readiness.ts integration/signalvault-v2-coston2-readiness.test.ts integration/package.json package.json reports/signalvault-v2-coston2-readiness.json
git commit -m "test: add coston2 v2 readiness probe"
```

Request independent review and resolve every Critical or Important finding before Task 5.

### Task 5: Gate 4 Regression Certification and Handoff

**Files:**
- Modify: `integration/README.md`
- Create: `docs/superpowers/coverage/2026-07-11-gate4-v2-section12.json`
- Create: `integration/gate4-v2-coverage.test.ts`
- Modify: `reports/gate4-v2-anvil-e2e.json` only by a fresh successful run
- Modify: `reports/signalvault-v2-coston2-readiness.json` only by a fresh read-only run

**Interfaces:**
- Consumes: every Gate 3 Section 12 bullet, all Gate 4A–4D test files, and both reports.
- Produces: a bullet-level coverage manifest, an executable evidence audit, reproducible verification commands, and an implementation-complete/deployment-not-authorized handoff.

- [ ] **Step 1: Write the coverage audit and Run RED.**

Create `integration/gate4-v2-coverage.test.ts` to extract every Markdown bullet between Gate 3 `## 12` and `## 13`, then load the coverage JSON and require exact text equality plus at least one evidence entry. Each evidence entry has this schema:

```ts
interface CoverageEvidence {
  kind: "foundry" | "vitest" | "anvil-report" | "readiness-report";
  file: string;
  symbolOrAssertion: string;
  expected?: string | number | boolean | null;
}
interface CoverageEntry {
  requirement: string;
  evidence: CoverageEvidence[];
}
```

For Foundry/Vitest evidence, `expected` must be absent; the audit reads the named file and requires the named test function/title to exist. For report evidence, `symbolOrAssertion` is an RFC 6901 JSON Pointer such as `/status` or `/allowancesAfter/fxrp`, `expected` is mandatory and JSON-safe, and the audit resolves the pointer and requires deep equality with `expected`. Integer report values that are serialized as decimal strings therefore use string expectations rather than JSON numbers.

Run before creating the manifest:

```powershell
npm test --workspace integration -- --run gate4-v2-coverage.test.ts
```

Expected: FAIL because `docs/superpowers/coverage/2026-07-11-gate4-v2-section12.json` does not exist.

- [ ] **Step 2: Populate exact coverage and documentation.**

Create one manifest entry for every exact Gate 3 Section 12 bullet; name concrete test functions or report assertions, never a whole file without a symbol. Add the Anvil startup, `e2e:v2:anvil`, `readiness:v2:coston2`, coverage-audit command, report paths, no-key readiness guarantee, and the sentence: `Coston2 V2 deployment remains unauthorized until a later explicit gate.`

- [ ] **Step 3: Run GREEN for full verification and refresh both reports.**

```powershell
npm test
npm run typecheck
D:\xhy\tools\foundry\forge.exe fmt --check
D:\xhy\tools\foundry\forge.exe build
D:\xhy\tools\foundry\forge.exe test -vvv
```

Restart Anvil and run `npm run e2e:v2:anvil --workspace local-signer`, then run `npm run readiness:v2:coston2`. Require every exit code 0, exact readiness status `ready_for_authorized_deployment`, final Anvil allowances/balances zero, and readiness report free of transactions.

- [ ] **Step 4: Run the coverage audit against the freshly generated reports.**

Run: `npm test --workspace integration -- --run gate4-v2-coverage.test.ts`

Expected: PASS with every Section 12 bullet mapped, every referenced test symbol found, and every report assertion evaluated against the report files produced in Step 3. Do not regenerate either report after this command.

- [ ] **Step 5: Perform final independent review.**

Review checklist: coverage manifest text matches every Section 12 bullet exactly; every referenced test/report assertion exists; compare all five Gate 4 plans; inspect complete Gate 4 diff; confirm no P0 regression/security assertion weakened; confirm no `.env`, key, secret, broadcast, frontend, or TEE file is staged; resolve every Critical or Important finding.

- [ ] **Step 6: Commit the certification.**

```powershell
git diff --check
git add integration/README.md integration/gate4-v2-coverage.test.ts docs/superpowers/coverage/2026-07-11-gate4-v2-section12.json reports/gate4-v2-anvil-e2e.json reports/signalvault-v2-coston2-readiness.json
git commit -m "docs: certify gate 4 v2 readiness"
```

## Gate 4D Completion Verification

Gate 4 implementation is ready for plan review only when all five Task commits exist, the complete Anvil V2 E2E is green from fresh state, the read-only Coston2 readiness command is green, P0 and V2 regressions pass, and no reviewer Critical/Important item remains. Stop without deploying to Coston2 and without beginning frontend or TEE work.
