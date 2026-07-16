import { contracts, EXPLORER_BASE_URL, GITHUB_URL, transactions } from "../lib/evidence";

const vault = contracts.find((contract) => contract.name === "SignalVaultV2")!;

export function Footer() {
  return (
    <footer className="site-footer page-shell">
      <div className="mode-disclosure">
        <span>Mode B disclosure</span>
        <p>Mode B is a software-isolated signer path. It is not a hardware-backed TEE. This dossier does not claim hardware confidential-compute guarantees.</p>
      </div>
      <div className="site-footer__bottom">
        <div><strong>SignalVault</strong><span>Live Coston2 execution dossier with wallet verification.</span></div>
        <p>Coston2 testnet · Not audited · Not for real funds</p>
        <nav aria-label="Footer links"><a href={GITHUB_URL} target="_blank" rel="noreferrer">Source</a><a href={`${EXPLORER_BASE_URL}/address/${vault.address}`} target="_blank" rel="noreferrer">Vault</a><a href={`${EXPLORER_BASE_URL}/tx/${transactions[2].hash}`} target="_blank" rel="noreferrer">Execution</a></nav>
      </div>
    </footer>
  );
}
