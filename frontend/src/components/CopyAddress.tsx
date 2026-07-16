import { useState } from "react";
import { EXPLORER_BASE_URL, formatAddress } from "../lib/evidence";

interface Props {
  address: string;
  label: string;
  showFull?: boolean;
}

export function CopyAddress({ address, label, showFull = false }: Props) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(address);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1_400);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="copy-address">
      <div>
        <span className="copy-address__label">{label}</span>
        <code title={address}>{showFull ? address : formatAddress(address, 8, 6)}</code>
      </div>
      <div className="copy-address__actions">
        <button type="button" className="icon-button" onClick={() => void copy()} aria-label={`Copy ${label} address`}>
          {copied ? "Copied" : "Copy"}
        </button>
        <a className="icon-link" href={`${EXPLORER_BASE_URL}/address/${address}`} target="_blank" rel="noreferrer" aria-label={`Open ${label} on Explorer`}>
          ↗
        </a>
      </div>
    </div>
  );
}
