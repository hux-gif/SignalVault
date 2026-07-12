# Gate 4A final fix report

## Scope and outcome

Base: `7ad48c01ae5663f45824e85d771af2d93c24b461`

Implemented the final whole-branch review wave without changing P0 production semantics, fixture values, adapters, routers, vaults, deployment, or E2E code.

- Added exported `validateSignableTEEResultV2`, which calls the existing Coston2 validator and rejects invalid/zero user and vault addresses, malformed/zero router config hashes, and non-canonical `resultHash` values before private-key parsing.
- Made the ordinary signed schema test fixture compute its canonical result hash before signing.
- Rejected zero router config hashes in request parsing even when the validation context also contains zero.
- Rejected numeric negative zero in `parseUint16` using `Object.is`.
- Added `minimumRebalanceInterval` coverage for `0`, `2^64 - 1`, and rejection of `2^64`.
- Added actual V2-to-P0 signature isolation with a valid P0 signature sensitivity assertion; retained V1-to-V2 isolation.
- Made `SignalVaultHashesV2.COSTON2_PROFILE` authoritative for the Solidity verifier.
- Replaced positional golden-fixture mutation identifiers with a named `MutationField` enum and an explicit unsupported-field revert.

## RED evidence

Command:

`npm test --workspace local-signer -- --run test/v2/schema.test.ts test/v2/json.test.ts`

Observed before production edits: 9 expected failures, 37 passes.

- Seven direct signer cases reached viem private-key parsing instead of rejecting malformed/zero user, malformed/zero vault, malformed/zero router config hash, or mismatched result hash.
- `parseUint16(-0)` returned successfully.
- A zero router config hash matching a zero validation context parsed successfully.

The uint64 boundary test passed immediately under existing viem ABI encoding behavior and is recorded as coverage addition, not a fabricated RED.

The reverse-isolation Solidity test includes the sensitivity probe in the permanent test: the P0 verifier first accepts a genuine V1 signature for the valid P0 result, then rejects genuine V2 signature bytes for that same P0 result.

## GREEN and verification evidence

- Focused affected Vitest: 2 files, 47/47 tests passed.
- Focused `ResultHashV2.t.sol`: 4/4 passed.
- Focused `IntentVerifierV2.t.sol`: 24/24 passed.
- Focused `SignerGoldenFixtureV2.t.sol`: 20/20 passed after the final enum guard refinement.
- All V2 Foundry: 48/48 passed.
- P0 golden fixture: 1/1 passed.
- P0 verifier: 5/5 passed.
- Full Foundry: 79/79 passed.
- Full local-signer: 10 files, 96/96 passed.
- Root `npm test`: local-signer 96/96 plus integration 22/22, 118/118 total.
- Local-signer typecheck: passed.
- Root typecheck: local-signer and integration passed.
- `forge fmt --check`: passed.
- `forge build`: passed.
- `git diff --check`: passed.

## Files changed

- `local-signer/src/v2/json.ts`
- `local-signer/src/v2/typedData.ts`
- `local-signer/src/v2/validation.ts`
- `local-signer/test/v2/json.test.ts`
- `local-signer/test/v2/schema.test.ts`
- `src/v2/IntentVerifierV2.sol`
- `test/v2/IntentVerifierV2.t.sol`
- `test/v2/SignerGoldenFixtureV2.t.sol`
- `.superpowers/sdd/final-fix-report.md`

## Self-review

- Confirmed the signer validator runs synchronously before `privateKeyToAccount` and recomputes the result hash from every field except `resultHash`.
- Confirmed no fixture data or P0 production file changed.
- Confirmed the Solidity profile value remains byte-identical and is now sourced from the hash library.
- Confirmed all 18 golden mutation wrappers use the corresponding named enum member, with no numeric mutation selectors remaining.
- Confirmed no `as any` or `as unknown` was introduced. The hostile direct-signer strings use narrow `Address`/`Hex` assertions because viem's template-literal types otherwise prevent representing runtime-hostile values at the typed API boundary; object spreads preserve the rest of the real `TEEResultV2` shape.

## Concerns

None. The uint64 upper-bound rejection is intentionally supplied by viem's ABI encoder and is now locked by focused coverage.
