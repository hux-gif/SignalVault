# FCC Mode B Design 鈥?Simulated TEE Attestation

## 1. Mode declaration

**Mode B 鈥?FCC-compatible simulated TEE attestation on Coston2**

This is NOT Mode C (real confidential hardware). Mode B uses a local deterministic signer that simulates the TEE attestation boundary. The signer operates as a trusted oracle that evaluates private intent and produces authenticated allocation results.

## 2. Architecture

```
Private Intent 鈫?Local Signer (Mode B) 鈫?TEEResultV2 鈫?SignalVaultV2 鈫?StrategyRouterV2
```

The local signer:
- Receives private intent + vault snapshot + FTSO input + nonce + deadline + chainId
- Computes deterministic allocation based on risk level
- Produces commitment hash, resultHash, and EIP-712 signature
- Returns TEEResultV2 with signature

## 3. Operation and Command

- Operation: `SIGNALVAULT`
- Command: `EVALUATE_INTENT`

## 4. Inputs

- Private intent (risk level, target APR, max drawdown, rebalance window, salt)
- Vault snapshot (address, total assets, current allocation)
- routerConfigHash (frozen on-chain)
- FTSO input (price, timestamp, decimals)
- Nonce (from vault)
- Deadline (current time + TTL)
- ChainId (Coston2 = 114)

## 5. Outputs

- Vault address
- Intent commitment (hash, not plaintext)
- Allocation (idleBps, upshiftBps)
- Risk limits (from frozen risk configuration)
- Nonce
- Deadline
- priceTimestamp
- routerConfigHash
- resultHash
- Signature (EIP-712)
- Attestation metadata: "Mode B 鈥?local deterministic signer, NOT hardware TEE"

## 6. Allocation strategy

Deterministic, simple, explainable:
- Risk level 0 (conservative): 100% idle, 0% upshift
- Risk level 1 (balanced): 50% idle, 50% upshift
- Risk level 2 (growth): 30% idle, 70% upshift

No AI price prediction. No guaranteed alpha. Allocation is a fixed function of risk level.

## 7. Privacy boundary

- Private intent is NEVER stored on-chain
- Only the commitment hash is submitted
- The signer does NOT log plaintext intent (configurable, disabled in production)
- Events contain only public execution evidence

## 8. FCC integration points

The local-signer service (`local-signer/src/service.ts`) already implements the complete Mode B flow. The V2 extension (`local-signer/src/v2/`) provides:
- `resultHash.ts` 鈥?V2 resultHash computation
- `typedData.ts` 鈥?V2 EIP-712 typed data signing
- `types.ts` 鈥?V2 TEEResultV2 type
- `configHash.ts` 鈥?V2 config hash computation
- `validation.ts` 鈥?V2 input validation

## 9. Known limitations

- Mode B does NOT provide hardware attestation
- The signer's private key must be protected by the operator
- In production, Mode C would use real TEE hardware (e.g., Intel SGX, AMD SEV)
- Mode B is suitable for Coston2 testnet and hackathon demonstration