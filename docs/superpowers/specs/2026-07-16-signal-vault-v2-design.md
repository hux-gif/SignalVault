# SignalVaultV2 Design

## 1. Overview

SignalVaultV2 is a personal, single-user ERC20 vault that binds to a frozen StrategyRouterV2. It provides:

- Non-transferable shares (personal vault)
- FXRP deposit and proportional share mint
- Share burn and asset withdrawal via Router waterfall
- Private intent commitment with nonce and deadline
- Authenticated TEE result verification via IntentVerifierV2
- Router rebalance execution with executionId linkage
- Replay protection via resultHash
- Router config hash verification
- Pause, emergency recovery, and full close

## 2. Deployment sequence (address cycle resolution)

The Router requires Vault address in `bindVault()`, adapters require Router address in constructor, and Vault requires Router address in constructor. The cycle is broken by deploying Router first with only (asset, vaultOwner):

1. Deploy IntentVerifierV2(trustedSigner)
2. Deploy StrategyRouterV2(asset, vaultOwner)
3. Deploy IdleAdapterV2(asset, router)
4. Deploy UpshiftAdapterV2(asset, router, protocol, lpToken)
5. Router.configureAdapters(upshift, idle)
6. Router.configureRisk(risk)
7. Deploy SignalVaultV2(asset, router, verifier, vaultOwner)
8. Router.bindVault(vault)

## 3. Immutable bindings

```solidity
IERC20 public immutable asset;
StrategyRouterV2 public immutable router;
IntentVerifierV2 public immutable verifier;
address public immutable vaultOwner;
```

Constructor validates:
- No zero addresses
- `router.asset() == address(asset)`
- `router.vaultOwner() == vaultOwner`

No `forceApprove(type(uint256).max)`. All Router funding uses exact transfers.

## 4. Share accounting

ERC20 with non-transferable shares. `_update` override blocks all transfers except mint (from=0) and burn (to=0).

```
totalAssets() = asset.balanceOf(vault) + router.totalAssets()
```

First deposit: shares = assets (1:1). Subsequent: shares = assets * supply / totalAssets.

Decimals match underlying asset.

## 5. Deposit

```solidity
function deposit(uint256 assets) external onlyVaultOwner nonReentrant returns (uint256 shares)
```

- Validate assets > 0
- Compute shares from proportional ratio
- Transfer asset from user to vault
- Mint shares to user
- Emit Deposited(user, assets, shares)

## 6. Withdraw

```solidity
function withdraw(uint256 shares) external onlyVaultOwner nonReentrant returns (uint256 assets)
```

- Validate shares > 0 and shares <= balance
- Compute assets from proportional ratio
- Burn shares
- If vault direct < assets: call `router.withdrawToVault(deficit)`
- Transfer assets to user
- Emit Withdrawn(user, assets, shares)

## 7. Private intent submission

```solidity
function submitPrivateIntent(bytes32 intentCommitment, uint256 nonce) external onlyVaultOwner
```

- Validate commitment != 0
- Validate nonce == userIntentNonce + 1
- Store commitment and advance nonce
- Emit PrivateIntentSubmitted(user, commitment, nonce)

No encrypted intent payload stored on-chain (privacy). Only the commitment hash is stored.

## 8. Authenticated Router execution

```solidity
function executeAuthenticatedRebalance(TEEResultV2 calldata result, bytes calldata signature) external nonReentrant
```

Verification chain:
1. `result.user == vaultOwner`
2. `result.vault == address(this)`
3. `result.nonce == userIntentNonce`
4. `result.intentCommitment == latestIntentCommitment`
5. `result.routerConfigHash == router.routerConfigHash()`
6. `result.capabilityProfile == router.capabilityProfile()`
7. `result.chainId == block.chainid`
8. `result.resultHash == SignalVaultHashesV2.computeResultHash(result)`
9. `!executedResults[result.resultHash]`
10. `verifier.verifyTEEResult(result, signature)`

Execution:
1. Mark `executedResults[result.resultHash] = true`
2. Transfer `fundingAssets` from vault to router (exact amount)
3. Call `router.rebalance(result.resultHash, result.allocation, result.limits, fundingAssets)`
4. Emit AuthenticatedRebalanceExecuted(vaultOwner, result.resultHash, totalAssetsAfter)

`executionId = result.resultHash` creates direct linkage between TEE result and Router's AllocationExecuted event.

## 9. Replay protection

`mapping(bytes32 => bool) public executedResults`

Each resultHash can only be executed once. The resultHash binds all fields of TEEResultV2 including nonce, so a new intent requires a new nonce and produces a new resultHash.

## 10. Router config hash verification

Before execution, vault verifies `result.routerConfigHash == router.routerConfigHash()`. This ensures the TEE result was computed against the same frozen Router configuration that is deployed on-chain. Any adapter swap, risk change, or vault rebind would change the hash and invalidate the result.

## 11. Pause, emergency, recovery

```solidity
function pauseRouter() external onlyVaultOwner
function unpauseRouter() external onlyVaultOwner
function recoverRouterPosition() external onlyVaultOwner nonReentrant
```

- `pauseRouter()`: calls `router.setExecutionPaused(true)`
- `unpauseRouter()`: calls `router.setExecutionPaused(false)`
- `recoverRouterPosition()`: calls `router.recoverAdapterPosition()`, receives LP tokens

## 12. Full close

```solidity
function closeVault() external onlyVaultOwner nonReentrant returns (uint256 assetsDelivered)
```

- Burns all user shares
- Calls `router.withdrawAllToVault()`
- Transfers all assets to user
- Emits VaultClosed(user, assetsDelivered)

## 13. Donation handling

Direct donations to vault or router increase totalAssets without minting shares. This dilutes existing shares (benefits the vault owner). No special handling needed — donations are counted as NAV.

## 14. Rounding and first deposit

First deposit: shares = assets (1:1). This avoids division by zero and sets the initial share-to-asset ratio.

Rounding favors the vault (rounds shares down on deposit, rounds assets down on withdraw). Dust may accumulate to the vault's benefit.

## 15. Atomic rollback

All state-changing functions use `nonReentrant`. If `router.rebalance` reverts, the entire `executeAuthenticatedRebalance` reverts — the resultHash is NOT marked as executed, and the funding transfer is rolled back. If `router.withdrawToVault` reverts, the share burn is rolled back.

## 16. Events

```solidity
event Deposited(address indexed user, uint256 assets, uint256 shares);
event Withdrawn(address indexed user, uint256 assets, uint256 shares);
event PrivateIntentSubmitted(address indexed user, bytes32 indexed intentCommitment, uint256 nonce);
event AuthenticatedRebalanceExecuted(address indexed user, bytes32 indexed resultHash, uint256 totalAssetsAfter);
event VaultClosed(address indexed user, uint256 assetsDelivered);
event RouterPaused(address indexed user, bool paused);
event RouterPositionRecovered(address indexed user, uint256 sharesRecovered);
```

No private intent, commitment preimage, or TEE payload in events.

## 17. Security invariants

1. Only vaultOwner can deposit, withdraw, submit intent, execute rebalance, pause, recover, close
2. Shares are non-transferable (only mint/burn)
3. Every state mutation is non-reentrant
4. TEE result must match frozen Router config hash
5. TEE result must match latest intent commitment and nonce
6. Each resultHash can only execute once
7. executionId links Router event to TEE result
8. No unlimited approvals (exact transfers only)
9. Donations counted as NAV, not shares
10. Atomic rollback on any Router failure

## 18. Reuses

- SignalVaultTypesV2 (AllocationV2, RebalanceLimitsV2, RiskConfigurationV2, TEEResultV2)
- SignalVaultHashesV2 (computeResultHash, computeRouterConfigHash, COSTON2_PROFILE)
- IntentVerifierV2 (EIP-712 verification, verifyTEEResult)
- StrategyRouterV2 (rebalance, withdrawToVault, withdrawAllToVault, setExecutionPaused, recoverAdapterPosition)

No second TEEResult schema, resultHash, or EIP-712 domain.