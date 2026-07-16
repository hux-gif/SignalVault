# SignalVault Demo Script (3-5 minutes)

## Setup (0:00-0:30)

1. Show the SignalVault repository on GitHub
2. Explain the three-screen architecture: Private Intent → Confidential Decision → Verifiable Execution
3. Note: This runs on Flare Coston2 testnet

## Demo (0:30-4:00)

### Step 1: Deposit (0:30-1:00)
- Open the frontend
- Screen 1: Private Intent
- Explain: user deposits FXRP into SignalVaultV2
- Show vault address and nonce

### Step 2: Private Intent (1:00-2:00)
- User selects risk level (Conservative/Balanced/Growth)
- User enters private salt
- Explain: only commitment hash goes on-chain, never plaintext
- Submit intent

### Step 3: Confidential Decision (2:00-3:00)
- Screen 2: Confidential Decision
- FCC Mode B evaluates the private intent
- Show resultHash, allocation, FTSO value, signature status
- Explain: Mode B is local signer, NOT hardware TEE

### Step 4: Verifiable Execution (3:00-4:00)
- Screen 3: Verifiable Execution
- Show vault NAV, allocation, executionId
- Show transaction evidence with explorer links
- Explain: executionId links TEE result to on-chain event

## Closing (4:00-5:00)

1. Recap: Private intent → confidential evaluation → verifiable execution
2. Note: All code is open source on GitHub
3. Show the successful verification workflow: complete Foundry suite plus 169 JavaScript tests
4. Q&A

## Key Messages

- "Your private intent never touches the chain"
- "FCC Mode B simulates TEE attestation on Coston2"
- "Every execution is verifiable via executionId linkage"
- "The Upshift adapter targets the real protocol interface; the current live SignalVaultV2 deployment is still pending"
