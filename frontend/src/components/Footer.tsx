import { contracts, EXPLORER_BASE_URL, GITHUB_URL, transactions } from "../lib/evidence";

export function Footer() {
  return (
    <footer className="footer section-shell">
      <div className="footer__brand"><span className="brand-mark" aria-hidden="true"><i /><i /><i /></span><div><strong>SignalVault</strong><small>Private intent. Verifiable execution.</small></div></div>
      <div className="footer__warning">Coston2 testnet · Not audited · Not for real funds</div>
      <nav aria-label="Footer links">
        <a href={GITHUB_URL} target="_blank" rel="noreferrer">GitHub</a>
        <a href={`${GITHUB_URL}/actions`} target="_blank" rel="noreferrer">CI</a>
        <a href={`${EXPLORER_BASE_URL}/address/${contracts[1].address}`} target="_blank" rel="noreferrer">Contracts</a>
        <a href={`${EXPLORER_BASE_URL}/tx/${transactions[2].hash}`} target="_blank" rel="noreferrer">Transaction evidence</a>
      </nav>
    </footer>
  );
}
