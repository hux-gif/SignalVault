# Known Limitations

## FCC Mode

SignalVault uses FCC Mode B (local deterministic signer) on Coston2. This is NOT hardware TEE attestation (Mode C). The signer's private key is held by the operator. In production, Mode C would use real confidential hardware (Intel SGX, AMD SEV, or equivalent).

## Network

Coston2 testnet only. Not deployed on Flare mainnet. All FXRP and Upshift positions are testnet tokens with no real economic value.

## Economic Claims

SignalVault does NOT guarantee:
- Yield or profit
- Specific APR
- Protection against protocol risks (Upshift smart contract risk, FXRP depeg risk)
- Protection against market risks (impermanent loss, liquidation)

## Single-User Vault

SignalVaultV2 is a personal single-user vault. Shares are non-transferable. Only the vault owner can deposit, withdraw, submit intents, and execute rebalances.

## Upshift Liquidity

Upshift position liquidity depends on the protocol's available liquidity. In low-liquidity conditions, redemptions may be partially filled or require multiple transactions.