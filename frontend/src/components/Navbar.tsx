import { useEffect, useState } from "react";
import { EXPLORER_BASE_URL, GITHUB_URL } from "../lib/evidence";

interface Props {
  account: string | null;
  onConnect: () => void;
  walletStatus: string;
}

export function Navbar({ account, onConnect, walletStatus }: Props) {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const update = () => setScrolled(window.scrollY > 24);
    update();
    window.addEventListener("scroll", update, { passive: true });
    return () => window.removeEventListener("scroll", update);
  }, []);

  return (
    <header className={scrolled ? "navbar navbar--scrolled" : "navbar"}>
      <a className="brand" href="#top" aria-label="SignalVault home">
        <span className="brand-mark" aria-hidden="true"><i /><i /><i /></span>
        <span>SignalVault</span>
      </a>
      <nav className="navbar__links" aria-label="Primary navigation">
        <a href="#product">Product</a>
        <a href="#proof">Live Proof</a>
        <a href="#architecture">Architecture</a>
      </nav>
      <div className="navbar__actions">
        <span className="network-live"><i aria-hidden="true" />Live on Coston2</span>
        <a className="desktop-link" href={GITHUB_URL} target="_blank" rel="noreferrer">GitHub</a>
        <a className="desktop-link" href={EXPLORER_BASE_URL} target="_blank" rel="noreferrer">Explorer</a>
        <button className="wallet-button" type="button" onClick={onConnect} title={walletStatus}>
          {account ? `${account.slice(0, 8)}…` : "Connect Wallet"}
        </button>
      </div>
    </header>
  );
}
