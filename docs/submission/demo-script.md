# SignalVault Demo Script (2-3 minutes)

## Problem (0:00-0:20)

Explain that public DeFi automation can reveal a user's complete risk intent before execution.

## Live Coston2 vault (0:20-0:40)

Open the public evidence dashboard, connect a wallet and confirm Coston2 chain ID 114. Show the deployed SignalVaultV2 address.

## Private intent (0:40-1:00)

Show the private risk preference and salt boundary. Open the real commitment transaction and explain that only the salted commitment reaches the chain.

## FTSOv2 and Mode B result (1:00-1:20)

Show the live FTSOv2 value/timestamp and signed `TEEResultV2`. State clearly that the Mode B operator signer evaluates the intent through an FCC-compatible interface; this is not hardware TEE execution.

## Execution and position (1:20-2:05)

Open the rebalance transaction. Show the 50/50 Idle/Upshift target, real Upshift LP balance, net NAV, gross NAV and available liquidity. Confirm `executionId == resultHash`.

## Withdrawal and proof (2:05-2:40)

Show the withdrawal of 1,000,000 shares and receipt of 997,500 FXRP base units. Open all four Explorer transactions.

## Key Messages

- "Your private intent never touches the chain"
- "FCC Mode B simulates TEE attestation on Coston2"
- "Every execution is verifiable via executionId linkage"
- "SignalVaultV2 is deployed on Coston2 and the evidence includes a real Upshift position and withdrawal"
- "Testnet only, not audited, not for real funds, and Mode B is not hardware TEE"
