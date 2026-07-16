import { useState } from "react";

interface Props {
  vaultAddress: string;
  nonce: bigint;
  onSubmit: (commitment: string, nonce: bigint) => void;
}

export function PrivateIntentScreen({ vaultAddress, nonce, onSubmit }: Props) {
  const [riskLevel, setRiskLevel] = useState(1);
  const [salt, setSalt] = useState("");

  const riskLabels = ["Conservative (30% upshift)", "Balanced (50/50)", "Growth (70% upshift)"];

  return (
    <div className="screen">
      <h1>1. Private Intent</h1>
      <div className="vault-info">
        <p>Vault: <code>{vaultAddress}</code></p>
        <p>Next nonce: {nonce.toString()}</p>
      </div>
      <div className="intent-form">
        <label>Risk Level</label>
        <select value={riskLevel} onChange={(e) => setRiskLevel(Number(e.target.value))}>
          {riskLabels.map((label, i) => (
            <option key={i} value={i}>{label}</option>
          ))}
        </select>
        <label>Salt (private)</label>
        <input type="password" value={salt} onChange={(e) => setSalt(e.target.value)}
               placeholder="Random salt for commitment" />
        <button disabled title="The recorded Coston2 demonstration is complete; use the operator flow for a new private commitment." onClick={() => onSubmit("", nonce + 1n)}>
          Submit Intent
        </button>
      </div>
      <p className="privacy-note">
        Your private intent is never stored on-chain. Only a commitment hash is submitted.
      </p>
    </div>
  );
}
