# Bounty 2: Confidential Compute Apps

## SignalVault Private Intent with FCC Mode B

SignalVault demonstrates confidential compute integration on Flare:

## Architecture

```
Private Intent → FCC Mode B (Local Signer) → TEEResultV2 → SignalVaultV2 → StrategyRouterV2
```

## Privacy Boundary

- Private intent is NEVER stored on-chain
- Only a commitment hash is submitted to SignalVaultV2
- The Mode B operator signer evaluates the private intent through an FCC-compatible interface using FTSOv2 market data
- Authenticated TEEResultV2 with EIP-712 signature
- Replay protection via resultHash

## FCC Mode Declaration

**Mode B — FCC-compatible simulated TEE attestation on Coston2**

This is NOT Mode C (real hardware TEE). The local signer simulates the TEE boundary for Coston2 demonstration.

The prototype does not implement hardware TEE execution, remote hardware attestation, enclave measurement verification, a hardware-bound signer key or a production FCC deployment.

## Verifiable Execution

- executionId = resultHash (direct linkage)
- AllocationExecuted event with executionId, BPS, pre/post NAV, loss
- AllocationSkipped event for no-op
- Events contain only public execution evidence (no private intent)

## Evidence

- FCC design: `docs/superpowers/specs/2026-07-16-fcc-mode-b-design.md`
- Local signer V2: `local-signer/src/v2/`
- SignalVaultV2 verification: `src/v2/SignalVaultV2.sol`
- IntentVerifierV2: `src/v2/IntentVerifierV2.sol`
- 28 SignalVaultV2 tests passing
