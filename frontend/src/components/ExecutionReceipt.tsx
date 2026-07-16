import { contracts, evidence, formatAddress } from "../lib/evidence";
import { StatusBadge } from "./StatusBadge";

const vault = contracts.find((contract) => contract.name === "SignalVaultV2")!;
const router = contracts.find((contract) => contract.name === "StrategyRouterV2")!;

export function ExecutionReceipt() {
  const rows = [
    ["Execution ID", formatAddress(evidence.executionId, 12, 10)],
    ["Result hash", formatAddress(evidence.resultHash, 12, 10)],
    ["Network", "Coston2 · 114"],
    ["Vault", formatAddress(vault.address, 10, 6)],
    ["Router", formatAddress(router.address, 10, 6)],
    ["Allocation", "50% Idle / 50% Upshift"],
    ["Shares redeemed", "1,000,000"],
    ["FXRP received", "997,500 base units"],
  ];

  return (
    <aside className="receipt-card surface-card">
      <div className="receipt-card__header"><div><span>Execution receipt</span><small>Canonical Coston2 evidence</small></div><StatusBadge tone="green">VERIFIED</StatusBadge></div>
      <div className="receipt-card__seal"><span>SV</span><div><strong>AUTHENTICATED</strong><small>RESULT · 0x68f2749b</small></div></div>
      <dl>{rows.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>
      <div className="receipt-card__footer"><span>Result signature</span><strong>VALID ✓</strong></div>
    </aside>
  );
}
