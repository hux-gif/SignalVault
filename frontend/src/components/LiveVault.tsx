import type { LiveSnapshot, RpcState } from "../lib/evidence";
import { evidence, formatAge, formatFxrp, formatTimestamp } from "../lib/evidence";
import { StatusBadge } from "./StatusBadge";

interface Props {
  onRetry: () => void;
  rpcState: RpcState;
  snapshot: LiveSnapshot;
}

function Metric({ label, recorded = false, value, suffix, rpcState }: { label: string; recorded?: boolean; value: string; suffix?: string; rpcState: RpcState }) {
  const loading = rpcState === "loading" && !recorded;

  return (
    <article className="metric-card">
      <div className="metric-card__top">
        <span>{label}</span>
        {loading
          ? <span className="skeleton skeleton--pill" />
          : <StatusBadge tone={recorded ? "neutral" : rpcState === "live" ? "green" : "warning"}>{recorded ? "RECORDED E2E" : rpcState === "live" ? "LIVE" : "VERIFIED"}</StatusBadge>}
      </div>
      {loading ? <span className="skeleton skeleton--value" /> : <strong>{value} {suffix && <small>{suffix}</small>}</strong>}
    </article>
  );
}

export function LiveVault({ onRetry, rpcState, snapshot }: Props) {
  return (
    <section className="section-shell section-block" id="product">
      <div className="section-heading">
        <div>
          <p className="eyebrow">LIVE VAULT</p>
          <h2>A real vault. A real position. A real withdrawal.</h2>
        </div>
        <div className="rpc-state" aria-live="polite">
          <span className={`rpc-state__dot rpc-state__dot--${rpcState}`} />
          <div><strong>{rpcState === "degraded" ? "RPC degraded" : rpcState === "live" ? "Coston2 RPC live" : "Reading Coston2"}</strong><small>{rpcState === "degraded" ? "Last verified evidence" : "chain ID 114"}</small></div>
          {rpcState === "degraded" && <button type="button" onClick={onRetry}>Retry live RPC</button>}
        </div>
      </div>
      <div className="metrics-grid">
        <Metric label="Net NAV" value={formatFxrp(snapshot.netAssets)} suffix="FXRP" rpcState={rpcState} />
        <Metric label="Gross NAV" value={formatFxrp(snapshot.grossAssets)} suffix="FXRP" rpcState={rpcState} />
        <Metric label="Available Liquidity" value={formatFxrp(snapshot.availableLiquidity)} suffix="FXRP" rpcState={rpcState} />
        <Metric label="FTSO input age" value={formatAge(evidence.ftsoTimestamp)} rpcState={rpcState} recorded />
      </div>
      <div className="allocation-panel surface-card">
        <div className="allocation-panel__copy">
          <div className="allocation-panel__header"><div><span>Current allocation</span><strong>Fee-aware strategy exposure</strong></div><StatusBadge tone="green">AUTHENTICATED</StatusBadge></div>
          <div className="allocation-row">
            <div><span>Idle FXRP</span><strong>{snapshot.idleBps / 100}%</strong></div>
            <div className="allocation-bar"><i style={{ width: `${snapshot.idleBps / 100}%` }} /></div>
          </div>
          <div className="allocation-row allocation-row--cyan">
            <div><span>Upshift Position</span><strong>{snapshot.upshiftBps / 100}%</strong></div>
            <div className="allocation-bar"><i style={{ width: `${snapshot.upshiftBps / 100}%` }} /></div>
          </div>
          <p className="allocation-note">FTSO input {formatTimestamp(evidence.ftsoTimestamp)} · Signed into the authenticated result.</p>
        </div>
        <div className="allocation-donut" style={{ background: `conic-gradient(#56dff1 0 ${snapshot.upshiftBps / 100}%, #ff4f8b ${snapshot.upshiftBps / 100}% 100%)` }}>
          <div><strong>{snapshot.idleBps / 100}/{snapshot.upshiftBps / 100}</strong><span>onchain</span></div>
        </div>
      </div>
    </section>
  );
}
