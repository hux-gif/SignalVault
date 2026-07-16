import { evidence, formatAge, formatFxrp, type LiveSnapshot, type RpcState } from "../lib/evidence";

interface Props {
  onRetry: () => void;
  rpcState: RpcState;
  snapshot: LiveSnapshot;
}

export function VaultState({ onRetry, rpcState, snapshot }: Props) {
  const status = rpcState === "live" ? "Coston2 RPC live" : rpcState === "degraded" ? "RPC degraded" : "Reading Coston2";
  return (
    <section className="vault-state page-shell section-rule" id="vault-state">
      <header className="section-intro">
        <p className="section-number">03</p>
        <div><p className="kicker">LIVE VAULT STATE</p><h2>The Router reports net value, gross value and exit liquidity separately.</h2></div>
        <div className={`rpc-readout rpc-readout--${rpcState}`} role="status">
          <i aria-hidden="true" /><div><strong>{status}</strong><span>{rpcState === "degraded" ? "Last verified evidence" : "Chain ID 114"}</span></div>
          {rpcState === "degraded" && <button type="button" onClick={onRetry}>Retry live RPC</button>}
        </div>
      </header>
      <div className="vault-state__layout">
        <table>
          <tbody>
            <tr><th>Net NAV</th><td>{formatFxrp(snapshot.netAssets)} FXRP</td><td>{rpcState === "live" ? "LIVE" : "VERIFIED"}</td></tr>
            <tr><th>Gross NAV</th><td>{formatFxrp(snapshot.grossAssets)} FXRP</td><td>{rpcState === "live" ? "LIVE" : "VERIFIED"}</td></tr>
            <tr><th>Available liquidity</th><td>{formatFxrp(snapshot.availableLiquidity)} FXRP</td><td>{rpcState === "live" ? "LIVE" : "VERIFIED"}</td></tr>
            <tr><th>Idle exposure</th><td>{snapshot.idleBps / 100}%</td><td>{rpcState === "live" ? "LIVE" : "VERIFIED"}</td></tr>
            <tr><th>Upshift exposure</th><td>{snapshot.upshiftBps / 100}%</td><td>{rpcState === "live" ? "LIVE" : "VERIFIED"}</td></tr>
            <tr><th>FTSO input age</th><td>{formatAge(evidence.ftsoTimestamp)}</td><td>RECORDED E2E</td></tr>
            <tr><th>Protocol status</th><td>{rpcState === "live" ? "Operational" : "Recorded snapshot"}</td><td>{rpcState === "live" ? "LIVE" : "VERIFIED"}</td></tr>
          </tbody>
        </table>
        <div className="allocation-report" aria-label="Current strategy allocation">
          <div><span>Idle FXRP</span><strong>{snapshot.idleBps / 100}%</strong></div>
          <div className="allocation-report__bar"><i style={{ width: `${snapshot.idleBps / 100}%` }} /></div>
          <div><span>Upshift</span><strong>{snapshot.upshiftBps / 100}%</strong></div>
          <div className="allocation-report__bar allocation-report__bar--blue"><i style={{ width: `${snapshot.upshiftBps / 100}%` }} /></div>
          <p>Net-liquidation value prices shares and withdrawals. Gross value remains telemetry.</p>
        </div>
      </div>
    </section>
  );
}
