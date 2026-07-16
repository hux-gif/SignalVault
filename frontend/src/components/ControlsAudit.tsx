const controls = [
  ["Signer binding", "IntentVerifierV2"],
  ["Chain binding", "chainId 114"],
  ["Vault binding", "Signed result includes Vault"],
  ["Strategy binding", "routerConfigHash"],
  ["Replay boundary", "nonce + deadline"],
  ["Loss ceiling", "maximumRebalanceLossBps"],
  ["Execution deviation", "maximumPreviewDeviationBps"],
  ["Liquidity exit", "Vault → Router → Idle → Upshift"],
] as const;

export function ControlsAudit() {
  return (
    <section className="controls-audit page-shell section-rule" id="controls">
      <header className="section-intro section-intro--compact">
        <p className="section-number">04</p>
        <div><p className="kicker">HOW IT IS CONSTRAINED</p><h2>The signed result cannot change the Vault, chain, Router configuration or loss limits.</h2></div>
      </header>
      <table><thead><tr><th>Control</th><th>Enforcement</th></tr></thead><tbody>{controls.map(([control, enforcement]) => <tr key={control}><th>{control}</th><td><code>{enforcement}</code></td></tr>)}</tbody></table>
    </section>
  );
}
