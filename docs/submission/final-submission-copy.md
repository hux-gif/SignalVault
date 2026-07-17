# Final Submission Copy

## Project name

SignalVault

## Tagline

Private strategy. Public proof.

## Short description

SignalVault is a personal FXRP vault on Flare Coston2 that converts a private
risk mandate into constrained, verifiable allocation between Idle FXRP and a
real Upshift position without publishing the plaintext intent.

## Full description

SignalVault gives XRP holders a way to automate DeFi allocation while keeping
their complete risk mandate offchain. The owner deposits FXRP into a personal,
non-transferable SignalVaultV2 and submits only a salted intent commitment. An
FCC-compatible Mode B signer evaluates the private input with an FTSOv2 data
point and produces a constrained EIP-712 V2 result. The signed result binds the
Vault, chain, capability profile, frozen Router configuration, allocation,
deadline, replay identifier and risk limits.

After verification, StrategyRouterV2 performs a fee-aware differential
rebalance between Idle FXRP and Upshift. Net-liquidation value prices shares and
withdrawals, while live protocol previews, balance-delta reconciliation,
bounded loss and preview-deviation controls protect execution. The result hash
becomes the public execution ID, making the decision boundary and resulting
transactions independently inspectable without revealing the plaintext intent.

The recorded Coston2 flow deposited 5 FXRP, committed a private intent,
executed a 50/50 Idle/Upshift allocation with a real Upshift LP position, and
withdrew 1,000,000 shares for 997,500 FXRP base units.

## Primary bounty

**Interoperable Asset Products.** SignalVault makes FXRP programmable through a
personal vault, FTSOv2-bound decision input, a real Upshift strategy adapter,
fee-aware accounting, differential rebalancing and a liquidity-first withdrawal
path on Flare Coston2.

## Secondary bounty

**Confidential Compute Apps.** SignalVault demonstrates an FCC-compatible Mode B
simulated attestation boundary. The private intent remains offchain, while a
constrained EIP-712 result is authenticated and consumed onchain. This prototype
does not claim hardware-backed TEE execution or remote hardware attestation.

## Repository URL

https://github.com/hux-gif/SignalVault

## Live demo URL

https://hux-gif.github.io/SignalVault/

## Demo video URL — user upload required

Paste the public or unlisted video URL here after uploading
`SignalVault-demo.mp4` from the local submission package.

## Coston2 deployment addresses

- IntentVerifierV2: `0x2C7b2a5620fbf25a65c81257F16b8437f5Af492a`
- StrategyRouterV2: `0x1d64CE2a9293F248a7298135932bE9674d39a764`
- IdleAdapterV2: `0xD0Ee1664e21aE9529f6cCCf94A70C29C7396fFD8`
- UpshiftAdapterV2: `0x6bF0f5f7e9595171246C888F9AC10c830e1D81Db`
- SignalVaultV2: `0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898`

## Four canonical transaction links

- [Deposit](https://coston2-explorer.flare.network/tx/0x245f207e77f19c3246e84c1df7f1e33794af124263ceffe07850832008376d79)
- [Commitment](https://coston2-explorer.flare.network/tx/0x8424df2d4833dd07521c529654b3df54a77291fbcd8141cf77fc31d253dcdd27)
- [Rebalance](https://coston2-explorer.flare.network/tx/0xe38ed07e2f77a03b29cc6ba57bc09cfbc2e18f8eda43a7819510f2b019ec2d23)
- [Withdrawal](https://coston2-explorer.flare.network/tx/0xe550cd5bde1ae67f15e1ae29f16eaeefe08a1410d18dde9a889a7872d790d1ba)

## Testing and verification

- JavaScript/TypeScript: 207 tests — 109 local-signer, 31 frontend and 67 integration.
- Typecheck and production frontend build pass.
- Complete Foundry format, build, size, test and lint gate passes in clean-checkout CI.
- [Verify workflow](https://github.com/hux-gif/SignalVault/actions/runs/29501160815)
- [Frontend deployment workflow](https://github.com/hux-gif/SignalVault/actions/runs/29501161290)
- Frontend release commit: `028947bcad9f129fd5ccf77669fc03528c5e9b14`

## Existing work versus hackathon work

No pre-hackathon production deployment is claimed. During the Flare Summer
Signal development period, the project progressed from the P0 personal-vault,
mock-routing and deterministic-signer baseline to the V2 signed schema, verifier,
fee-aware Idle/Upshift adapters, differential StrategyRouterV2, SignalVaultV2,
FTSOv2 input, FCC-compatible Mode B signer, Coston2 deployment, live protocol
execution evidence and the public execution dossier.

## Known limitations

- Coston2 testnet only; not deployed on Flare mainnet.
- Unaudited and not for real funds.
- Mode B uses an operator-held signer and is not hardware-backed TEE execution.
- Single-owner personal vault with non-transferable shares.
- No yield, APR or loss-protection guarantee.
- Upshift liquidity and protocol configuration can change.
- Hardware-backed FCC execution, remote attestation and an independent security
  audit remain future work.

## Final human submission checklist

- [ ] Upload `SignalVault-demo.mp4` to a public or unlisted video host.
- [ ] Paste the final video URL into the DoraHacks form and this document.
- [ ] Use `SignalVault-demo-cover.png` as the cover when the host requests one.
- [ ] Confirm the repository URL and live dashboard URL open without
  authentication.
- [ ] Select Interoperable Asset Products as the primary bounty.
- [ ] Select Confidential Compute Apps as the secondary bounty only with the
  Mode B disclosure intact.
- [ ] Recheck all five addresses and four Explorer links in the submission preview.
- [ ] Submit the DoraHacks form from the `hux-gif` account.
