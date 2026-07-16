import type { LiveSnapshot, RpcState } from "../lib/evidence";
import { GITHUB_URL } from "../lib/evidence";
import { ExecutionOrb } from "./ExecutionOrb";
import { StatusBadge } from "./StatusBadge";

interface Props {
  rpcState: RpcState;
  snapshot: LiveSnapshot;
}

export function Hero({ rpcState, snapshot }: Props) {
  return (
    <section className="hero section-shell" id="top">
      <div className="hero__copy">
        <p className="eyebrow"><span /> PRIVATE INTENT COMMAND CENTER</p>
        <h1><span>Private intent.</span><strong>Verifiable FXRP execution.</strong></h1>
        <p className="hero__lede">
          SignalVault turns a private risk intent into an authenticated, fee-aware allocation between idle FXRP and a real Upshift position on Flare.
        </p>
        <div className="hero__actions">
          <a className="button button--primary" href="#proof">Replay live execution <span>↓</span></a>
          <a className="button button--secondary" href="#architecture">View contracts ↓</a>
        </div>
        <div className="hero__badges">
          <StatusBadge tone="green">● Deployed on Coston2</StatusBadge>
          <StatusBadge tone="cyan">● Real FXRP / Upshift position</StatusBadge>
          <StatusBadge tone="warning">Mode B — Not hardware TEE</StatusBadge>
        </div>
        <a className="hero__source" href={GITHUB_URL} target="_blank" rel="noreferrer">Open-source evidence repository ↗</a>
      </div>
      <ExecutionOrb rpcState={rpcState} snapshot={snapshot} />
    </section>
  );
}
