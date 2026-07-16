# Deployment Addresses

## Network: Flare Coston2 (chainId: 114)

Status: NOT YET DEPLOYED

Deployment requires:
- FXRP_ADDRESS (Coston2 FXRP token)
- TRUSTED_SIGNER (local signer public key)
- VAULT_OWNER (vault owner address)
- UPSHIFT_VAULT_ADDRESS (Upshift protocol vault)
- LP_TOKEN_ADDRESS (Upshift LP token)

Deploy script: `forge script script/DeploySignalVaultV2.s.sol --rpc-url coston2 --broadcast`

After deployment, this file will contain:
- IntentVerifierV2 address
- StrategyRouterV2 address
- IdleAdapterV2 address
- UpshiftAdapterV2 address
- SignalVaultV2 address
- routerConfigHash
- riskConfigurationHash
- Deploy transaction hash
- Block number