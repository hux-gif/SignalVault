# Judge Checklist

- Repository: https://github.com/hux-gif/SignalVault/tree/signalvault-final
- Final release commit: `f013cdb1ef8656a0343444709feb4f022803f428`
- Full verification: https://github.com/hux-gif/SignalVault/actions/runs/29480218456
- Public dashboard: HUMAN ACTION REQUIRED - enable GitHub Pages, then record the real URL.
- Demo video: HUMAN ACTION REQUIRED.

## Coston2 contracts

- IntentVerifierV2: `0x2C7b2a5620fbf25a65c81257F16b8437f5Af492a`
- StrategyRouterV2: `0x1d64CE2a9293F248a7298135932bE9674d39a764`
- IdleAdapterV2: `0xD0Ee1664e21aE9529f6cCCf94A70C29C7396fFD8`
- UpshiftAdapterV2: `0x6bF0f5f7e9595171246C888F9AC10c830e1D81Db`
- SignalVaultV2: `0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898`

## Three-minute verification

1. Open the dashboard and connect an EIP-1193 wallet.
2. Confirm the network guard targets Coston2, chain ID 114.
3. Review live Router net NAV, gross NAV and available liquidity.
4. Review the private-intent, Mode B decision and execution screens.
5. Open the Deposit, Commitment, Rebalance and Withdrawal Explorer links.
6. Confirm the rebalance event execution ID equals the signed result hash.
7. Review `docs/submission/existing-vs-new.md` and `docs/submission/known-limitations.md`.

## Required disclosure

The dashboard is a live Coston2 evidence dashboard with wallet and network verification, not a complete self-service production dApp. Mode B is simulated attestation and is not hardware-backed TEE execution.
