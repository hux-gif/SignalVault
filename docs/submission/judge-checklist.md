# Judge Checklist

Current status: pre-deployment package. The live steps below become available only after the Coston2 deployment manifest and public frontend URL are populated.

## Three-minute evidence review

1. Open the public frontend URL recorded in `reports/final-e2e/manifest.json`.
2. Confirm the network is Flare Coston2, chain ID 114.
3. Review the private/public boundary on the Private Intent screen.
4. Confirm the decision screen labels the service as `FCC-compatible Mode B simulated attestation — NOT hardware TEE`.
5. Compare `resultHash` with the execution event's `executionId`.
6. Open the Coston2 Explorer links for deployment and execution transactions.
7. Review pre/post NAV, allocation, balance and withdrawal evidence.

## Interactive flow after deployment

1. Connect a wallet and switch to Coston2.
2. Obtain test FXRP using the current official Flare testnet instructions.
3. Approve and deposit test FXRP into the personal SignalVaultV2.
4. Enter a private risk preference and local salt. Do not reuse the salt.
5. Submit only the commitment and encrypted payload to the Vault.
6. Request a Mode B signed `TEEResultV2`.
7. Inspect allocation, FTSO value/timestamp, deadline and signer status.
8. Submit the result and execute the differential rebalance.
9. Open the receipt and `AllocationExecuted` event in Coston2 Explorer.
10. Perform a partial withdrawal and confirm the withdrawal waterfall.

## Safety and limitations

- Testnet only; do not use real funds.
- Not audited and not financial advice.
- Mode B trusts an operator-held signer key and does not provide hardware attestation.
- SignalVault shares are non-transferable and the Vault is single-owner.
- If no deployment addresses or transaction hashes appear in the manifest, treat the package as a local prototype, not a working live app.

## Human-dependent fields

- Public frontend URL: pending hosting.
- Video URL: pending upload.
- SignalVaultV2 Coston2 addresses: pending wallet-authorized deployment.
- Example execution and withdrawal transactions: pending live E2E.
