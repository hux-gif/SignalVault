import { EXPLORER_BASE_URL, formatAddress, transactions } from "../lib/evidence";
import { ExecutionReceipt } from "./ExecutionReceipt";

export function ProofTimeline() {
  return (
    <section className="section-shell section-block" id="proof">
      <div className="section-heading">
        <div><p className="eyebrow">PROOF OF EXECUTION</p><h2>Four transactions. One verifiable execution.</h2></div>
        <p className="section-heading__copy">No screenshots as proof. Every step links to the canonical Coston2 transaction.</p>
      </div>
      <div className="proof-layout">
        <div className="timeline">
          {transactions.map((transaction) => (
            <article className="timeline-item" key={transaction.hash}>
              <div className="timeline-item__marker"><span>✓</span></div>
              <div className="timeline-item__content">
                <div><span>{transaction.index}</span><h3>{transaction.label}</h3><small>SUCCESS</small></div>
                <p>{transaction.detail}</p>
                <a href={`${EXPLORER_BASE_URL}/tx/${transaction.hash}`} target="_blank" rel="noreferrer">
                  <code>{formatAddress(transaction.hash, 12, 8)}</code><span>View on Explorer ↗</span>
                </a>
              </div>
            </article>
          ))}
        </div>
        <ExecutionReceipt />
      </div>
    </section>
  );
}
