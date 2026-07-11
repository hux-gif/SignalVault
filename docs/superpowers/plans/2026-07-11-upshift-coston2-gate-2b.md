# Upshift Coston2 Gate 2B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure one real minimal Coston2 FTestXRP deposit and Upshift instant redemption using the verified protocol-native interface.

**Architecture:** Keep the integration independent from SignalVault and split pure selection/economics/status logic from live viem orchestration through exported helpers. All read-only protocol checks precede key parsing; transaction receipts are recorded immediately; cleanup gates success.

**Tech Stack:** TypeScript, viem, Vitest, Coston2 JSON-RPC, GitHub CLI.

## Global Constraints

- Chain ID must equal `114`.
- FTestXRP is `0x0b6A3645c240605887a5532109323A3E12273dc7`.
- Upshift vault is `0x24c1a47cD5e8473b64EAB2a94515a196E10C7C81`.
- Private keys come only from `COSTON2_PRIVATE_KEY` and are never printed or committed.
- Do not modify core contracts, adapters, frontend, TEE, or Coston2 deployments.
- Do not infer NAV from the vault's direct token balance.

---

### Task 1: Protocol-native preflight and status model

**Files:**
- Modify: `integration/upshift-coston2-smoke.test.ts`
- Modify: `integration/upshift-coston2-smoke.ts`
- Modify: `integration/README.md`

**Interfaces:**
- Produces: amount selection helper, four valid report statuses, protocol-native preflight result.

- [ ] Write failing tests for selecting the smallest amount with nonzero deposit and redemption previews and for report-status transitions.
- [ ] Run `npm test --workspace integration` and confirm the new assertions fail for missing behavior.
- [ ] Remove standard vault accounting probes as blockers, read LP metadata/supply instead, and perform all protocol-native checks before `parsePrivateKey`.
- [ ] Run integration tests and typecheck; require all tests and `tsc --noEmit` to pass.

### Task 2: Redemption approval discovery, reconciliation, and cleanup

**Files:**
- Modify: `integration/upshift-coston2-smoke.test.ts`
- Modify: `integration/upshift-coston2-smoke.ts`
- Modify: `reports/upshift-coston2-smoke.json`

**Interfaces:**
- Consumes: selected amount and verified LP token from Task 1.
- Produces: deposit/redemption measurements, both allowance cleanup results, terminal status.

- [ ] Write failing tests for bigint round-trip loss, partial-failure status, and cleanup-gated success.
- [ ] Run the focused Vitest file and confirm failures are caused by missing helpers.
- [ ] Implement receipt-first report recording, pre-redemption refreshed reads, simulation-based LP approval discovery, balance reconciliation, and exact allowance cleanup.
- [ ] Run integration tests and typecheck until green.

### Task 3: Live Coston2 execution and evidence

**Files:**
- Modify at runtime: `reports/upshift-coston2-smoke.json`

**Interfaces:**
- Consumes: locally set `COSTON2_PRIVATE_KEY`, a wallet with C2FLR and sufficient FTestXRP.
- Produces: confirmed hashes, blocks, measured deltas, fee components, and terminal report.

- [ ] Run `npm run upshift:smoke:coston2` with the private key set only in the local process environment.
- [ ] Confirm both receipts on Coston2 and verify the report contains their explorer URLs.
- [ ] Confirm final FTestXRP and LP allowances are both zero.
- [ ] Preserve any partial confirmed transaction in the report if the command exits nonzero.

### Task 4: Regression, review, commit, and publish

**Files:**
- Modify: only files already in Gate 2 scope.

**Interfaces:**
- Consumes: completed Gate 2 report.
- Produces: reviewed Git commit and pushed `signalvault-p0` branch.

- [ ] Run root npm tests/typecheck, Foundry fmt/build/31 tests, and local-signer 29 tests/typecheck.
- [ ] Request independent review and resolve every Critical or Important finding.
- [ ] Stage only Gate 2 documents, integration files, report, and package metadata.
- [ ] Commit with `test: verify upshift coston2 deposit and instant redemption` when the live report succeeds; otherwise use a message that explicitly states partial status.
- [ ] Authenticate `gh` as `hux-gif` without changing existing local Git identity, then push `signalvault-p0` to `origin`.
