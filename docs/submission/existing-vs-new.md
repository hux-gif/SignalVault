# Existing vs New Work

## Before the hackathon

No pre-hackathon production deployment is claimed. The repository history used for this submission begins during the Flare Summer Signal development period. The earliest P0 work established a personal vault prototype, mock strategy routing, local signing and deterministic fixtures.

## Built during the hackathon

- P0 personal SignalVault and private-intent commitment flow.
- Gate 4A V2 schema, canonical hashes, verifier and cross-language signer fixtures.
- Gate 4B fee-aware Idle and Upshift adapters with protocol-bound accounting and adversarial tests.
- StrategyRouterV2 Tasks 1–10: frozen configuration, differential planning and execution, net accounting, withdrawal waterfall, recovery and security suites.
- SignalVaultV2 with non-transferable shares, owner authorization, replay protection and authenticated Router execution.
- FCC-compatible Mode B local signer boundary. This is simulated attestation, not hardware TEE.
- FTSOv2 reader and freshness validation.
- Three-screen frontend presentation and Anvil E2E tooling.
- Coston2 protocol probes, deployment script and submission evidence package.

## Ported or integrated on Flare

- Coston2 chain profile and Explorer links.
- FXRP/FTestXRP as the vault asset profile.
- Upshift protocol adapter using its native vault and LP-token interfaces.
- FTSOv2 market-data input bound by timestamp into the signed result.
- EVM contracts and EIP-712 verification deployed through a Coston2-ready Foundry script.

SignalVaultV2 and its V2 dependencies were deployed to Coston2 on 2026-07-16. The recorded live E2E uses real SignalVaultV2 transactions and is kept separate from historical Upshift probes.

## Improved during the hackathon

- Replaced full unwind/redeposit routing with differential rebalancing.
- Added fee-aware net NAV and liquidity-first withdrawal behavior.
- Added configuration and capability-profile hashes to prevent silent strategy substitution.
- Added preview deviation, allocation tolerance and maximum-loss controls.
- Added replay, nonce, deadline, Vault, chain and signer binding.
- Added recovery and paused/illiquid failure boundaries.
- Added reproducible GitHub Actions verification for Node and Solidity workspaces.

## Future roadmap

1. Replace Mode B operator signing with hardware-backed FCC execution and remote attestation.
2. Obtain an independent security audit before any mainnet or real-funds use.
3. Validate usability with pilot users and record honest feedback.
4. Prepare Flare mainnet/FAssets production readiness and operational monitoring.
