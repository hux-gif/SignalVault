import { contracts, EXPLORER_BASE_URL, formatAddress, type EvidenceTransaction } from "../lib/evidence";

const vault = contracts.find((contract) => contract.name === "SignalVaultV2")!;
const router = contracts.find((contract) => contract.name === "StrategyRouterV2")!;

interface Props {
  transaction: EvidenceTransaction;
}

export function ExecutionReceipt({ transaction }: Props) {
  const rows = [
    ["Status", "Confirmed"],
    ["Network", "Coston2 · 114"],
    ["Block", transaction.block.toLocaleString("en-US")],
    ...transaction.receiptRows,
    ["Vault", formatAddress(vault.address, 8, 6)],
    ["Router", formatAddress(router.address, 8, 6)],
  ];

  return (
    <aside className="execution-receipt" aria-label="Execution receipt">
      <div className="execution-receipt__head">
        <div><span>Execution receipt</span><strong>{transaction.index} / {transaction.label}</strong></div>
        <span className="receipt-stamp">CONFIRMED</span>
      </div>
      <dl>
        {rows.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}
      </dl>
      <a href={`${EXPLORER_BASE_URL}/tx/${transaction.hash}`} target="_blank" rel="noreferrer">
        <span>Transaction</span><code>{formatAddress(transaction.hash, 6, 4)}</code><i aria-hidden="true">↗</i>
      </a>
      <p>The original strategy was not published in this transaction.</p>
    </aside>
  );
}
