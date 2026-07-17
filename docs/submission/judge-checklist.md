# Judge Checklist

- Repository: https://github.com/hux-gif/SignalVault/tree/main
- Frontend release commit: `028947bcad9f129fd5ccf77669fc03528c5e9b14`
- Full verification: https://github.com/hux-gif/SignalVault/actions/runs/29501160815
- Frontend deployment: https://github.com/hux-gif/SignalVault/actions/runs/29501161290
- Public dashboard: https://hux-gif.github.io/SignalVault/
- Demo video: recorded locally; public upload remains a user-owned action.

## Coston2 contracts

- IntentVerifierV2: `0x2C7b2a5620fbf25a65c81257F16b8437f5Af492a`
- StrategyRouterV2: `0x1d64CE2a9293F248a7298135932bE9674d39a764`
- IdleAdapterV2: `0xD0Ee1664e21aE9529f6cCCf94A70C29C7396fFD8`
- UpshiftAdapterV2: `0x6bF0f5f7e9595171246C888F9AC10c830e1D81Db`
- SignalVaultV2: `0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898`

## Three-minute verification

1. Open the dashboard and confirm the header reports `COSTON2 · LIVE`.
2. Review the four canonical transaction rows and their execution receipts.
3. Review the private/public disclosure boundary.
4. Review live Router net NAV, gross NAV, available liquidity and exposures.
5. Review the signed controls and five deployed contract addresses.
6. Confirm the Mode B and Coston2 testnet disclosures.
7. Review `docs/submission/existing-vs-new.md` and `docs/submission/known-limitations.md`.

## Required disclosure

The dashboard is a live Coston2 evidence dashboard with wallet and network verification, not a complete self-service production dApp. Mode B is simulated attestation and is not hardware-backed TEE execution.
