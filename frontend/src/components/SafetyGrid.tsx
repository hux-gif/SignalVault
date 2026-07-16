const controls = [
  ["Config Binding", "routerConfigHash prevents silent strategy replacement", "⌁"],
  ["Replay Protection", "nonce + deadline + canonical resultHash", "↻"],
  ["Net-Liquidation NAV", "fees are included in position valuation", "◒"],
  ["Differential Rebalance", "only the required strategy delta moves", "⇄"],
  ["Bounded Loss", "maximum loss and preview deviation enforced", "◇"],
  ["Withdrawal Waterfall", "Router → Idle → Upshift direct → LP redemption", "↓"],
] as const;

export function SafetyGrid() {
  return (
    <section className="section-shell section-block safety-section" id="safety">
      <div className="section-heading">
        <div><p className="eyebrow">SAFETY ENGINE</p><h2>Execution constrained by policy, not trust.</h2></div>
        <p className="section-heading__copy">Every allocation is bounded by signed intent, frozen configuration and measured balance deltas.</p>
      </div>
      <div className="safety-grid">
        {controls.map(([title, detail, icon]) => <article key={title}><span aria-hidden="true">{icon}</span><h3>{title}</h3><p>{detail}</p></article>)}
      </div>
      <p className="risk-strip"><span>!</span> Not audited · Coston2 testnet · Not intended for real funds</p>
    </section>
  );
}
