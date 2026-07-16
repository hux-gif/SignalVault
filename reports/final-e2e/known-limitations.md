# E2E Known Limitations

## Anvil E2E
- Deterministic local testnet, not Coston2
- Uses mock Upshift protocol (FeeAwareUpshiftVaultMock)
- Uses mock FXRP token (MockLPTokenV2)
- No real FTSOv2 feed — uses fixed timestamp

## Coston2 E2E
- Requires wallet signatures (HUMAN ACTION REQUIRED)
- Requires real FXRP and Upshift protocol addresses
- Network availability dependent
- Gas costs apply (testnet)

## FCC Mode
- Mode B (local deterministic signer) only
- NOT hardware TEE attestation
- Signer private key held by operator