import { formatAddress } from "../lib/evidence";
import type { RpcState } from "../lib/evidence";

interface Props {
  account: string | null;
  onVerify: () => void;
  rpcState: RpcState;
}

export function Header({ account, onVerify, rpcState }: Props) {
  const networkLabel = rpcState === "live" ? "Coston2 · live" : rpcState === "degraded" ? "Coston2 · evidence" : "Coston2 · reading";
  return (
    <header className="site-header">
      <a className="wordmark" href="#top" aria-label="SignalVault home">
        <span className="wordmark__stamp" aria-hidden="true">SV</span>
        <span>SignalVault</span>
      </a>
      <nav aria-label="Primary navigation">
        <a href="#verified-run">Run</a>
        <a href="#vault-state">State</a>
        <a href="#controls">Controls</a>
      </nav>
      <div className="site-header__actions">
        <span className={`network-mark network-mark--${rpcState}`}><i aria-hidden="true" />{networkLabel}</span>
        <button className="wallet-trigger" type="button" onClick={onVerify}>
          {account ? `${formatAddress(account)} · Coston2` : "Verify with wallet"}
        </button>
      </div>
    </header>
  );
}
