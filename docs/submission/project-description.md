# SignalVault 鈥?Private Intent, Confidential Compute, Verifiable Execution

SignalVault is a personal FXRP vault on Flare Coston2 that bridges private user intent with on-chain verifiable execution through a confidential compute boundary.

## Problem

DeFi vaults require users to publicly broadcast their investment strategy. This exposes intent to MEV, front-running, and copy-trading. Users need a way to express private investment intent that is evaluated confidentially and executed verifiably on-chain.

## Solution

SignalVault introduces a three-layer architecture:

1. **Private Intent** 鈥?Users submit only a commitment hash. The plaintext intent never touches the chain.
2. **Confidential Decision** 鈥?A trusted compute boundary (FCC Mode B: local deterministic signer on Coston2) evaluates the private intent against market conditions (FTSOv2) and produces an authenticated allocation result.
3. **Verifiable Execution** 鈥?The SignalVaultV2 contract verifies the TEE result signature, binds it to the frozen Router configuration hash, and executes a differential rebalance through StrategyRouterV2. Every execution emits an `AllocationExecuted` event with `executionId` linked to the TEE `resultHash`.

## Architecture

```
FXRP 鈫?SignalVaultV2 deposit 鈫?Private intent commitment
鈫?FCC Mode B (local signer) 鈫?TEEResultV2 + EIP-712 signature
鈫?FTSOv2 price feed 鈫?SignalVaultV2 verification
鈫?StrategyRouterV2 rebalance 鈫?IdleAdapterV2 + UpshiftAdapterV2
鈫?Withdrawal waterfall
```

## Flare Integration

- **FXRP**: Vault deposit asset on Coston2
- **Upshift**: Yield strategy adapter (real protocol integration)
- **FTSOv2**: Price feed for allocation decisions
- **FCC**: Confidential compute boundary (Mode B)

## Bounties

1. **Interoperable Asset Products** 鈥?FXRP vault with Upshift integration
2. **Confidential Compute Apps** 鈥?Private intent with TEE attestation

## Known Limitations

- FCC Mode B uses local deterministic signer, NOT hardware TEE
- Coston2 testnet only, not mainnet
- No guaranteed yield or profit
- Single-user personal vault (non-transferable shares)