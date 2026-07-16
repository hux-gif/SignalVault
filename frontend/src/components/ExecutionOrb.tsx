import type { LiveSnapshot, RpcState } from "../lib/evidence";
import { formatFxrp } from "../lib/evidence";

interface Props {
  rpcState: RpcState;
  snapshot: LiveSnapshot;
}

export function ExecutionOrb({ rpcState, snapshot }: Props) {
  return (
    <div className="orb-card" aria-label="Verified allocation visualization">
      <div className="orb-stage" aria-hidden="true">
        <span className="orb-label orb-label--ftso">FTSOv2</span>
        <span className="orb-label orb-label--intent">Private Intent</span>
        <span className="orb-label orb-label--result">Verified Result</span>
        <span className="orb-label orb-label--idle">Idle <strong>{snapshot.idleBps / 100}%</strong></span>
        <span className="orb-label orb-label--upshift">Upshift <strong>{snapshot.upshiftBps / 100}%</strong></span>
        <svg className="orb-lines" viewBox="0 0 560 430" role="presentation">
          <defs>
            <linearGradient id="flow-gradient" x1="0" x2="1">
              <stop offset="0" stopColor="#ff4f8b" />
              <stop offset="1" stopColor="#56dff1" />
            </linearGradient>
          </defs>
          <path d="M280 72V146M75 210H207M353 210H486M253 278L157 354M307 278L403 354" />
          <circle className="flow-dot flow-dot--one" cx="280" cy="110" r="4" />
          <circle className="flow-dot flow-dot--two" cx="128" cy="210" r="4" />
          <circle className="flow-dot flow-dot--three" cx="380" cy="336" r="4" />
        </svg>
        <div className="orbital orbital--outer"><i /><i /><i /></div>
        <div className="orbital orbital--inner"><i /><i /></div>
        <div className="execution-orb">
          <span className="execution-orb__scan" />
          <small>AUTHENTICATED</small>
          <strong>VERIFIED</strong>
          <span>COSTON2 · 114</span>
        </div>
      </div>
      <div className="orb-metrics">
        <div><span>NAV</span><strong>{formatFxrp(snapshot.netAssets)} <small>FXRP</small></strong></div>
        <div><span>Liquidity</span><strong>{rpcState === "live" ? "live" : "verified"}</strong></div>
        <div><span>Allocation</span><strong>{snapshot.idleBps / 100} / {snapshot.upshiftBps / 100}</strong></div>
        <div><span>Network</span><strong>Coston2 · 114</strong></div>
      </div>
    </div>
  );
}
