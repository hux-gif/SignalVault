# SignalVault - Private Intent, Verifiable FXRP Execution

SignalVault is a deployed personal FXRP strategy vault on Flare Coston2. It converts a private risk intent into an authenticated, fee-aware differential allocation between idle FXRP and a real Upshift position, with bounded-loss execution and a verified withdrawal path.

## Target user and problem

SignalVault is designed for XRP holders who want automated DeFi allocation without publishing their complete risk thresholds, timing preferences and strategy rationale. Conventional onchain automation exposes those inputs before execution, making strategies easier to copy or anticipate.

## Product flow

1. The owner deposits FXRP into a personal, non-transferable SignalVaultV2.
2. The plaintext intent and salt stay offchain; only a salted commitment is submitted.
3. A Mode B operator signer reads live FTSOv2 data and evaluates the private intent through an FCC-compatible interface.
4. It signs a constrained EIP-712 `TEEResultV2` containing the commitment, nonce, deadline, FTSO timestamp, allocation, risk limits and frozen Router configuration hash.
5. SignalVaultV2 authenticates the result and StrategyRouterV2 performs a fee-aware differential rebalance between idle FXRP and Upshift.
6. The result hash becomes the public execution ID, linking the private decision boundary to verifiable onchain evidence.

## Live Coston2 evidence

- SignalVaultV2: `0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898`
- StrategyRouterV2: `0x1d64CE2a9293F248a7298135932bE9674d39a764`
- Deposit: `0x245f207e77f19c3246e84c1df7f1e33794af124263ceffe07850832008376d79`
- Commitment: `0x8424df2d4833dd07521c529654b3df54a77291fbcd8141cf77fc31d253dcdd27`
- Rebalance: `0xe38ed07e2f77a03b29cc6ba57bc09cfbc2e18f8eda43a7819510f2b019ec2d23`
- Withdrawal: `0xe550cd5bde1ae67f15e1ae29f16eaeefe08a1410d18dde9a889a7872d790d1ba`

The verified flow deposited 5 FXRP, executed a 50/50 Idle/Upshift allocation, created a real Upshift LP position and redeemed 1,000,000 shares for 997,500 FXRP base units.

## Bounty positioning

Primary: **Bounty 1 - Interoperable Asset Products**. SignalVault gives FXRP a programmable, risk-constrained DeFi allocation and withdrawal path on Flare.

Secondary: **Bounty 2 - Confidential Compute Apps**. SignalVault currently uses an FCC-compatible Mode B simulated attestation boundary. It demonstrates private-intent evaluation, authenticated EIP-712 results and verifiable onchain consumption, but does not claim hardware-backed TEE execution.

## Limitations

- Coston2 testnet only; not audited and not for real funds.
- Mode B trusts an operator-held signer key and provides no hardware attestation.
- Single-owner personal vault with non-transferable shares.
- Production use requires an external audit and hardware-backed FCC integration.
