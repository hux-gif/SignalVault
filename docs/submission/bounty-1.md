# Bounty 1: Interoperable Asset Products

## SignalVault FXRP Vault with Upshift Integration

SignalVault creates a personal FXRP vault on Flare Coston2 that interoperates with:
- **FXRP**: Cross-chain FXRP as the vault deposit asset
- **Upshift Protocol**: Real yield strategy adapter integration
- **FTSOv2**: Price feed for allocation decisions
- **Flare Network**: Native smart contract platform

## How it works

1. User deposits FXRP into SignalVaultV2
2. SignalVaultV2 binds to a frozen StrategyRouterV2
3. StrategyRouterV2 allocates between IdleAdapterV2 (direct FXRP) and UpshiftAdapterV2 (Upshift LP position)
4. Differential rebalancing adjusts allocation based on authenticated TEE results
5. Withdrawal waterfall: direct → idle → upshift direct → upshift LP

## Evidence

- Solidity contracts: `src/v2/SignalVaultV2.sol`, `src/v2/StrategyRouterV2.sol`
- Real adapter integration: `test/v2/StrategyRouterV2Integration.t.sol`
- 575 Foundry tests passing
- Deploy script: `script/DeploySignalVaultV2.s.sol`