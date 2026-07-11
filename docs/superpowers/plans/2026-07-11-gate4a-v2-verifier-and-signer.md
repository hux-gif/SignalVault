# Gate 4A V2 Verifier and Signer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the independent V2 signed schema, canonical hashes, EIP-712 verifier, TypeScript signer codec, and byte-identical cross-language fixture.

**Architecture:** Solidity and TypeScript implement the same flattened field order from the approved Gate 3 design. Hash construction is centralized in V2-only modules, while P0 types, verifier, signer modules, fixture, and tests remain unchanged.

**Tech Stack:** Solidity 0.8.27, Foundry, OpenZeppelin EIP712/ECDSA, TypeScript 5.9, viem 2.x, Vitest 4.x.

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

## Frozen V2 Schema

Use these Solidity types in `src/v2/types/SignalVaultTypesV2.sol` and the same names with TypeScript scalar mappings in `local-signer/src/v2/types.ts`:

```solidity
struct AllocationV2 {
    uint16 upshiftBps;
    uint16 firelightBps;
    uint16 sparkdexBps;
    uint16 idleBps;
}

struct RebalanceLimitsV2 {
    uint256 minimumPostNAV;
    uint16 maximumRebalanceLossBps;
    uint16 maximumPreviewDeviationBps;
    uint16 allocationToleranceBps;
}

struct RiskConfigurationV2 {
    uint64 minimumRebalanceInterval;
    uint16 minimumAllocationChangeBps;
    uint16 maximumRebalanceLossBps;
    uint16 maximumPreviewDeviationBps;
    uint16 allocationToleranceBps;
}

struct TEEResultV2 {
    address user;
    address vault;
    bytes32 intentCommitment;
    bytes32 capabilityProfile;
    bytes32 routerConfigHash;
    AllocationV2 allocation;
    uint256 nonce;
    uint256 deadline;
    uint256 ftsoPriceTimestamp;
    uint256 chainId;
    RebalanceLimitsV2 limits;
    bytes32 resultHash;
}
```

The EIP-712 domain is exactly `{ name: "SignalVault", version: "2", chainId, verifyingContract: IntentVerifierV2 }`. The flattened primary type and canonical result-hash order are copied verbatim from the approved design; neither may use a nested EIP-712 type.

### Task 1: V2 Types and Canonical Hash Library

**Files:**
- Create: `src/v2/types/SignalVaultTypesV2.sol`
- Create: `src/v2/libraries/SignalVaultHashesV2.sol`
- Create: `test/v2/ResultHashV2.t.sol`

**Interfaces:**
- Consumes: OpenZeppelin-free `abi.encode` and `keccak256`; no P0 type import.
- Produces: `AllocationV2`, `RebalanceLimitsV2`, `RiskConfigurationV2`, `TEEResultV2`; `SignalVaultHashesV2.computeResultHash`, `computeRiskConfigurationHash`, and `computeRouterConfigHash`.

- [ ] **Step 1: Write the failing Solidity hash tests.**

```solidity
function testResultHashStartsWithV2DomainAndUsesFrozenOrder() external pure {
    TEEResultV2 memory result = fixtureResult();
    bytes32 expected = keccak256(abi.encode(
        keccak256("SIGNALVAULT_TEE_RESULT_V2"), result.user, result.vault,
        result.intentCommitment, result.capabilityProfile, result.routerConfigHash,
        result.allocation.upshiftBps, result.allocation.firelightBps,
        result.allocation.sparkdexBps, result.allocation.idleBps,
        result.nonce, result.deadline, result.ftsoPriceTimestamp, result.chainId,
        result.limits.minimumPostNAV, result.limits.maximumRebalanceLossBps,
        result.limits.maximumPreviewDeviationBps, result.limits.allocationToleranceBps
    ));
    assertEq(SignalVaultHashesV2.computeResultHash(result), expected);
}

function testRouterConfigHashMutatesForEveryBinding() external pure {
    bytes32 base = configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1);
    assertNotEq(base, configHash(115, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1));
    assertNotEq(base, configHash(114, address(1), ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1));
    assertNotEq(base, configHash(114, VAULT, address(2), ASSET, UPSHIFT, IDLE, PROFILE, RISK, 1));
    assertNotEq(base, configHash(114, VAULT, ROUTER, address(3), UPSHIFT, IDLE, PROFILE, RISK, 1));
    assertNotEq(base, configHash(114, VAULT, ROUTER, ASSET, address(4), IDLE, PROFILE, RISK, 1));
    assertNotEq(base, configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, address(5), PROFILE, RISK, 1));
    assertNotEq(base, configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, bytes32(uint256(6)), RISK, 1));
    assertNotEq(base, configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, bytes32(uint256(7)), 1));
    assertNotEq(base, configHash(114, VAULT, ROUTER, ASSET, UPSHIFT, IDLE, PROFILE, RISK, 2));
}
```

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/ResultHashV2.t.sol -vvv`

Expected: FAIL because the V2 type and hash library imports do not exist.

- [ ] **Step 3: Implement the minimal hash library with exact domains.**

```solidity
bytes32 internal constant RESULT_V2_DOMAIN = keccak256("SIGNALVAULT_TEE_RESULT_V2");
bytes32 internal constant RISK_CONFIG_V1_DOMAIN = keccak256("SIGNALVAULT_ROUTER_RISK_CONFIG_V1");
bytes32 internal constant ROUTER_CONFIG_V1_DOMAIN = keccak256("SIGNALVAULT_ROUTER_CONFIG_V1");
bytes32 internal constant COSTON2_PROFILE = keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1");
uint256 internal constant ROUTER_CONFIG_VERSION = 1;
```

`computeRiskConfigurationHash` encodes the risk domain followed by the five fields in struct order. `computeRouterConfigHash` encodes the Router domain, chain ID, Vault, Router, asset, Upshift adapter, Idle adapter, capability profile, risk hash, and version in that order. `computeResultHash` uses the 18 operands shown in Step 1 and excludes `result.resultHash`.

- [ ] **Step 4: Run GREEN and V1 regression.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/ResultHashV2.t.sol -vvv`

Expected: PASS with every field-mutation assertion green.

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/SignerGoldenFixture.t.sol -vvv`

Expected: P0 golden fixture remains PASS.

- [ ] **Step 5: Review and commit Task 1.**

Review checklist: confirm no P0 file changed; every constant string matches Gate 3; `resultHash` excludes itself; all config addresses and versions mutate the hash; no arithmetic narrows before encoding.

```powershell
git diff --check
git add src/v2/types/SignalVaultTypesV2.sol src/v2/libraries/SignalVaultHashesV2.sol test/v2/ResultHashV2.t.sol
git commit -m "test: define signalvault v2 hashes"
```

Request independent review and resolve every Critical or Important finding before Task 2.

### Task 2: IntentVerifierV2 and Domain Isolation

**Files:**
- Create: `src/v2/IntentVerifierV2.sol`
- Create: `test/v2/IntentVerifierV2.t.sol`

**Interfaces:**
- Consumes: `TEEResultV2` and `SignalVaultHashesV2.computeResultHash` from Task 1; OpenZeppelin `EIP712`, `ECDSA`, and `Ownable`.
- Produces: `TEERESULT_V2_TYPEHASH`, `hashTEEResult(TEEResultV2)`, `hashTypedData(TEEResultV2)`, `verifyTEEResult(TEEResultV2,bytes)`, and `trustedSigner` rotation.

- [ ] **Step 1: Write failing verifier tests.**

```solidity
function testVerifiesV2AndRejectsV1Domain() external view {
    TEEResultV2 memory result = fixtureResult();
    result.resultHash = SignalVaultHashesV2.computeResultHash(result);
    assertTrue(verifier.verifyTEEResult(result, signV2(result)));
    assertFalse(verifier.verifyTEEResult(result, signWithDomainVersion(result, "1")));
}

function testRejectsUnsupportedCoston2Weights() external view {
    TEEResultV2 memory result = fixtureResult();
    result.allocation.firelightBps = 1;
    result.allocation.idleBps -= 1;
    result.resultHash = SignalVaultHashesV2.computeResultHash(result);
    assertFalse(verifier.verifyTEEResult(result, signV2(result)));
}

function testRejectsWrongCapabilityProfile() external view {
    TEEResultV2 memory result = fixtureResult();
    result.capabilityProfile = keccak256("WRONG_PROFILE");
    result.resultHash = SignalVaultHashesV2.computeResultHash(result);
    assertFalse(verifier.verifyTEEResult(result, signV2(result)));
}
```

Also add focused cases for wrong chain, wrong Vault mutation, expired deadline, zero profile, wrong nonzero capability profile, zero config hash, wrong config-hash mutation, invalid result hash, untrusted signer, V1 signature bytes, and allocation sum other than 10,000.

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/IntentVerifierV2.t.sol -vvv`

Expected: FAIL because `IntentVerifierV2` is missing.

- [ ] **Step 3: Implement the verifier.**

Use `EIP712("SignalVault", "2")`. The TypeHash string is exactly:

```text
TEEResultV2(address user,address vault,bytes32 intentCommitment,bytes32 capabilityProfile,bytes32 routerConfigHash,uint16 upshiftBps,uint16 firelightBps,uint16 sparkdexBps,uint16 idleBps,uint256 nonce,uint256 deadline,uint256 ftsoPriceTimestamp,uint256 chainId,uint256 minimumPostNAV,uint16 maximumRebalanceLossBps,uint16 maximumPreviewDeviationBps,uint16 allocationToleranceBps,bytes32 resultHash)
```

Before recovery require: dynamic `block.chainid` equality; `deadline >= block.timestamp`; `capabilityProfile == keccak256("SIGNALVAULT_COSTON2_UPSHIFT_IDLE_V1")`; nonzero config hash; supplied canonical hash equality; `firelightBps == 0`; `sparkdexBps == 0`; and `upshiftBps + idleBps == 10_000`. Return `false`, rather than bubbling ECDSA errors, for invalid signatures. Router config equality is enforced by SignalVaultV2 in Gate 4C; Gate 4A proves any config-hash mutation invalidates the original signature.

- [ ] **Step 4: Run GREEN and verifier regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/IntentVerifierV2.t.sol -vvv`

Expected: all V2 verifier cases PASS.

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/IntentVerifier.t.sol -vvv`

Expected: all P0 verifier cases PASS.

- [ ] **Step 5: Review and commit Task 2.**

Review checklist: verify domain version is literal `2`; TypeHash contains every field once; canonical hash is recomputed; unsupported weights are rejected; `chainId` is dynamic; trusted signer cannot be zero.

```powershell
git diff --check
git add src/v2/IntentVerifierV2.sol test/v2/IntentVerifierV2.t.sol
git commit -m "feat: add intent verifier v2"
```

Request independent review and resolve every Critical or Important finding before Task 3.

### Task 3: TypeScript V2 Schema, Hashes, Typed Data, and JSON Codec

**Files:**
- Create: `local-signer/src/v2/types.ts`
- Create: `local-signer/src/v2/resultHash.ts`
- Create: `local-signer/src/v2/configHash.ts`
- Create: `local-signer/src/v2/typedData.ts`
- Create: `local-signer/src/v2/json.ts`
- Create: `local-signer/test/v2/schema.test.ts`
- Create: `local-signer/test/v2/json.test.ts`

**Interfaces:**
- Consumes: viem `encodeAbiParameters`, `keccak256`, `hashTypedData`, `signTypedData`; schema/constants from Tasks 1–2 by exact duplication across languages.
- Produces: `TEEResultV2`, `V2ValidationContext`, `computeResultHashV2`, `computeRiskConfigurationHashV2`, `computeRouterConfigHashV2`, `teeResultV2Domain`, `teeResultV2Digest`, `signTEEResultV2`, `parseUint16`, `parseUint256`, `parseAllocateRequestV2(value,context)`, and bigint-safe response serialization.

- [ ] **Step 1: Write failing TypeScript schema and JSON tests.**

```ts
it("uses the V2 domain and changes digest for every signed field", () => {
  expect(teeResultV2Domain(114n, verifier)).toEqual({
    name: "SignalVault", version: "2", chainId: 114n, verifyingContract: verifier,
  });
  const digest = teeResultV2Digest(result, verifier);
  for (const mutation of mutateEverySignedField(result)) {
    expect(teeResultV2Digest(mutation, verifier)).not.toBe(digest);
  }
});

it("rejects unsafe JSON numbers for every uint256", () => {
  expect(() => parseAllocateRequestV2(
    { ...request, minimumPostNAV: Number.MAX_SAFE_INTEGER + 1 }, validationContext,
  ))
    .toThrow(/decimal string/);
});

it("enforces integer-width boundaries before semantic allocation checks", () => {
  expect(parseUint16("65535")).toBe(65535);
  expect(() => parseUint16("65536")).toThrow(/uint16/);
  expect(parseUint256(((1n << 256n) - 1n).toString())).toBe((1n << 256n) - 1n);
  expect(() => parseUint256((1n << 256n).toString())).toThrow(/uint256/);
});
```

- [ ] **Step 2: Run RED.**

Run: `npm test --workspace local-signer -- --run test/v2/schema.test.ts test/v2/json.test.ts`

Expected: FAIL because V2 modules do not exist.

- [ ] **Step 3: Implement exact bigint-safe codecs.**

Use `number` only for width-validated `uint16` fields and `bigint` for `uint64`/`uint256`. Export `parseUint16` and `parseUint256` for focused boundary tests; semantic BPS validation then applies the stricter 10,000 ceiling. `V2ValidationContext` contains expected chain ID, Vault, verifier, capability profile, and Router config hash. `parseAllocateRequestV2(value,context)` rejects negative values, scientific notation, unsafe JSON numbers, values above `(1n << 256n) - 1n`, BPS above 10,000, malformed bytes32, zero addresses, or any context mismatch. `computeResultHashV2` begins with `keccak256(toHex("SIGNALVAULT_TEE_RESULT_V2"))` and uses the Solidity order. `teeResultV2Types` uses primary type `TEEResultV2` and domain version `2`.

- [ ] **Step 4: Run GREEN and TypeScript regressions.**

Run: `npm test --workspace local-signer -- --run test/v2/schema.test.ts test/v2/json.test.ts`

Expected: both V2 test files PASS.

Run: `npm test --workspace local-signer && npm run typecheck --workspace local-signer`

Expected: all P0 and V2 tests PASS and `tsc --noEmit` exits 0.

- [ ] **Step 5: Review and commit Task 3.**

Review checklist: compare every ABI type/order with Solidity; reject unsafe JSON numbers; ensure decimal strings serialize without precision loss; keep P0 imports untouched; verify config hash contains chain/Vault/Router/asset/adapters/profile/risk/version.

```powershell
git diff --check
git add local-signer/src/v2 local-signer/test/v2/schema.test.ts local-signer/test/v2/json.test.ts
git commit -m "feat: add local signer v2 schema"
```

Request independent review and resolve every Critical or Important finding before Task 4.

### Task 4: Cross-Language Golden Fixture and Mutation Matrix

**Files:**
- Create: `fixtures/tee-result-v2.json`
- Create: `test/v2/SignerGoldenFixtureV2.t.sol`
- Create: `local-signer/test/v2/golden.test.ts`
- Create: `local-signer/test/v2/mutations.test.ts`

**Interfaces:**
- Consumes: Solidity/TypeScript V2 types, hashes, typed data, and deterministic Anvil test key.
- Produces: one canonical fixture with decimal-string integers and expected risk hash, Router config hash, result hash, typed-data digest, signature, and recovered signer.

- [ ] **Step 1: Add a fixture skeleton and failing parity tests.**

The fixture uses `testOnly: true`, chain `31337`, no real address/key, four fields `5000/0/0/5000`, and string values for every `uint64`/`uint256`. Both test suites assert:

```ts
expect(computeRiskConfigurationHashV2(fixture.riskConfiguration)).toBe(fixture.expected.riskConfigurationHash);
expect(computeRouterConfigHashV2(fixture.routerConfiguration)).toBe(fixture.expected.routerConfigHash);
expect(computeResultHashV2(unsigned)).toBe(fixture.expected.resultHash);
expect(teeResultV2Digest(result, fixture.input.intentVerifier)).toBe(fixture.expected.typedDataDigest);
```

- [ ] **Step 2: Run RED.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignerGoldenFixtureV2.t.sol -vvv`

Run: `npm test --workspace local-signer -- --run test/v2/golden.test.ts test/v2/mutations.test.ts`

Expected: both commands FAIL because expected fixture values are empty or intentionally incorrect.

- [ ] **Step 3: Generate fixed expected values with V2 modules and freeze them.**

Use a one-off `tsx` expression importing only `local-signer/src/v2/*`; paste the deterministic hashes/signature into the fixture, then delete the one-off generator. The mutation matrix changes user, Vault, commitment, capability, config hash, all four weights, nonce, deadline, FTSO timestamp, chain, minimum NAV, all three signed BPS limits, and result hash one at a time. Each mutation must fail original-signer recovery or fail canonical-hash equality.

- [ ] **Step 4: Run GREEN and full cross-language regressions.**

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/v2/SignerGoldenFixtureV2.t.sol -vvv`

Run: `npm test --workspace local-signer -- --run test/v2/golden.test.ts test/v2/mutations.test.ts`

Run: `D:\xhy\tools\foundry\forge.exe test --match-path test/SignerGoldenFixture.t.sol -vvv`

Expected: V2 Solidity/TypeScript fixture parity passes and P0 fixture remains green.

- [ ] **Step 5: Review and commit Task 4.**

Review checklist: verify fixture is marked test-only; no credential came from `.env`; every integer is a decimal string; all signed fields have a mutation; V1/V2 digests differ; Solidity and TypeScript recovered signer match.

```powershell
git diff --check
git add fixtures/tee-result-v2.json test/v2/SignerGoldenFixtureV2.t.sol local-signer/test/v2/golden.test.ts local-signer/test/v2/mutations.test.ts
git commit -m "test: add v2 cross-language fixture"
```

Request independent review and resolve every Critical or Important finding.

## Gate 4A Completion Verification

Run fresh:

```powershell
D:\xhy\tools\foundry\forge.exe fmt --check
D:\xhy\tools\foundry\forge.exe build
D:\xhy\tools\foundry\forge.exe test --match-path 'test/v2/*V2.t.sol' -vvv
D:\xhy\tools\foundry\forge.exe test -vvv
npm test --workspace local-signer
npm run typecheck --workspace local-signer
```

Require no P0 production diff, no V1 fixture modification, and a reviewer verdict of ready with no unresolved Critical or Important issue. Stop Gate 4A before adapters, Router, Vault, deployment, Coston2, frontend, or TEE work.
