# Deployment Addresses

## Network: Flare Coston2 (chainId: 114)

Status: DEPLOYED on 2026-07-16 from git commit `356ac06`

- IntentVerifierV2: `0x2C7b2a5620fbf25a65c81257F16b8437f5Af492a`
- StrategyRouterV2: `0x1d64CE2a9293F248a7298135932bE9674d39a764`
- IdleAdapterV2: `0xD0Ee1664e21aE9529f6cCCf94A70C29C7396fFD8`
- UpshiftAdapterV2: `0x6bF0f5f7e9595171246C888F9AC10c830e1D81Db`
- SignalVaultV2: `0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898`
- routerConfigHash: `0x202497cf161eef43d5bc473c227f33ecea8c74868f1cfab4ea71f1f555ccb00c`
- riskConfigurationHash: `0xbc1236d24d6b8d7b511a12c32113ea33579d6ad34c14e9f9fa5d0a1e55d93836`

Canonical transaction hashes and blocks are recorded in `deployments/coston2-v2.json`.

Deployment requires:
- FXRP_ADDRESS (Coston2 FXRP token)
- TRUSTED_SIGNER (local signer public key)
- VAULT_OWNER (vault owner address)
- UPSHIFT_VAULT_ADDRESS (Upshift protocol vault)
- LP_TOKEN_ADDRESS (Upshift LP token)

Deploy script: `forge script script/DeploySignalVaultV2.s.sol --rpc-url coston2 --broadcast`

The deployment manifest contains:
- IntentVerifierV2 address
- StrategyRouterV2 address
- IdleAdapterV2 address
- UpshiftAdapterV2 address
- SignalVaultV2 address
- routerConfigHash
- riskConfigurationHash
- Deploy transaction hash
- Block number
