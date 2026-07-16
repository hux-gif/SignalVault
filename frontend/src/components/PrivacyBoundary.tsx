const privateFacts = ["Full risk preference", "Reasoning and thresholds", "Original private instruction", "Offchain evaluation context"];
const publicFacts = ["Salted commitment", "Signed allocation", "Result hash", "Execution transaction", "Final asset allocation"];

export function PrivacyBoundary() {
  return (
    <section className="privacy-boundary page-shell section-rule">
      <header className="section-intro section-intro--compact">
        <p className="section-number">02</p>
        <div><p className="kicker">DISCLOSURE BOUNDARY</p><h2>The strategy stayed private. Its constraints did not.</h2></div>
      </header>
      <div className="privacy-boundary__grid">
        <div><h3>Remained private</h3><ul>{privateFacts.map((fact) => <li key={fact}>{fact}</li>)}</ul></div>
        <div><h3>Became public</h3><ul>{publicFacts.map((fact) => <li key={fact}>{fact}</li>)}</ul></div>
      </div>
      <p className="privacy-boundary__note">The original strategy stayed offchain. Only its salted commitment and signed allocation were published.</p>
    </section>
  );
}
