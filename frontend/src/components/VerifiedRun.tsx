import { EXPLORER_BASE_URL, formatAddress, transactions, type EvidenceTransaction } from "../lib/evidence";
import { ExecutionReceipt } from "./ExecutionReceipt";

interface Props {
  onSelect: (index: number) => void;
  selected: number;
  transaction: EvidenceTransaction;
}

export function VerifiedRun({ onSelect, selected, transaction }: Props) {
  return (
    <section className="verified-run page-shell section-rule" id="verified-run">
      <header className="section-intro">
        <p className="section-number">01</p>
        <div><p className="kicker">THE VERIFIED RUN</p><h2>Four transactions left one public record.</h2></div>
        <p>Each row opens the canonical Coston2 transaction. Select a row to inspect its receipt.</p>
      </header>
      <div className="verified-run__layout">
        <div className="transaction-ledger" aria-label="Verified transaction ledger">
          {transactions.map((item, index) => (
            <article className={selected === index ? "transaction-row transaction-row--selected" : "transaction-row"} key={item.hash}>
              <button type="button" aria-pressed={selected === index} onClick={() => onSelect(index)}>
                <span>{item.index}</span>
                <div><strong>{item.label}</strong><p>{item.detail}</p></div>
                <i aria-hidden="true">{selected === index ? "●" : "○"}</i>
              </button>
              <div className="transaction-row__evidence">
                <span>Block {item.block.toLocaleString("en-US")}</span>
                <a href={`${EXPLORER_BASE_URL}/tx/${item.hash}`} target="_blank" rel="noreferrer">
                  {formatAddress(item.hash, 10, 8)} <i aria-hidden="true">↗</i>
                </a>
                <span className="confirmed">Confirmed</span>
              </div>
            </article>
          ))}
        </div>
        <div className="verified-run__receipt"><ExecutionReceipt transaction={transaction} /></div>
      </div>
    </section>
  );
}
