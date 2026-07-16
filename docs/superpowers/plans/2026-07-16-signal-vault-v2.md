# SignalVaultV2 Implementation Plan

## Tasks

### SV1: Interface and immutable binding
- Create `src/v2/interfaces/ISignalVaultV2.sol` with frozen runtime ABI
- Create `src/v2/SignalVaultV2.sol` with constructor, immutable fields, validation
- TDD: RED test for constructor validation and binding
- Commit: `feat: add signal vault v2 immutable binding`

### SV2: Personal share accounting
- Implement ERC20 with non-transferable shares
- `totalAssets()`, `decimals()`, first deposit ratio
- TDD: RED test for non-transferability and accounting
- Commit: `feat: add signal vault v2 share accounting`

### SV3: Deposit and mint
- Implement `deposit(uint256 assets) returns (uint256 shares)`
- Proportional share minting, transferFrom, event
- TDD: RED test for deposit, first deposit, rounding
- Commit: `feat: add signal vault v2 deposit`

### SV4: Withdraw and redeem
- Implement `withdraw(uint256 shares) returns (uint256 assets)`
- Burn shares, router.withdrawToVault, transfer to user
- TDD: RED test for withdrawal, partial, full
- Commit: `feat: add signal vault v2 withdraw`

### SV5: Commitment, nonce, deadline
- Implement `submitPrivateIntent(bytes32 commitment, uint256 nonce)`
- Nonce advancement, commitment storage
- TDD: RED test for nonce, replay, invalid commitment
- Commit: `feat: add signal vault v2 intent commitment`

### SV6: TEEResultV2 verification
- Implement `executeAuthenticatedRebalance(TEEResultV2, bytes signature)`
- Full verification chain: user, vault, nonce, commitment, configHash, resultHash, signature
- Replay protection via executedResults
- TDD: RED test for verification, replay, stale config
- Commit: `feat: add signal vault v2 authenticated execution`

### SV7: executionId linkage
- executionId = resultHash
- Router rebalance call with executionId
- Event linkage: AuthenticatedRebalanceExecuted → AllocationExecuted
- TDD: RED test for executionId match
- Commit: `feat: add signal vault v2 execution linkage`

### SV8: Pause, emergency, recovery
- `pauseRouter()`, `unpauseRouter()`, `recoverRouterPosition()`
- Full close: `closeVault()`
- TDD: RED test for pause, recovery, close
- Commit: `feat: add signal vault v2 emergency controls`

### SV9: Adversarial security
- Reentrancy, non-vault-owner, invalid TEE result, stale config, replay
- Donation, rounding, dust, zero-share edge cases
- TDD: RED test for each adversarial vector
- Commit: `feat: add signal vault v2 adversarial security`

### SV10: Real Router integration and docs
- Integration test with real StrategyRouterV2, IdleAdapterV2, UpshiftAdapterV2
- Coverage manifest JSON
- README update
- Full review: SIGNAL_VAULT_V2_FULL_BRANCH_REVIEW: PASS
- Commit: `docs: certify signal vault v2`

## TDD cycle per task

1. RED: write failing test
2. GREEN: minimal implementation
3. Mutation: verify test catches mutations
4. Regression: full suite passes
5. Review: fresh-context check
6. Fix: Critical/Important findings
7. PASS: commit and push
8. Next: no pause