import { contracts } from "../lib/evidence";
import { CopyAddress } from "./CopyAddress";
import { StatusBadge } from "./StatusBadge";

export function Architecture() {
  return (
    <section className="section-shell section-block" id="architecture">
      <div className="section-heading">
        <div><p className="eyebrow">ARCHITECTURE</p><h2>One private boundary. Five deployed contracts.</h2></div>
        <p className="section-heading__copy">The operator signs a constrained result; independent V2 contracts authenticate and execute it on Coston2.</p>
      </div>
      <div className="architecture-panel surface-card">
        <div className="architecture-flow">
          <article className="architecture-node architecture-node--offchain"><span>OFFCHAIN</span><strong>Private Risk Intent</strong><small>remains undisclosed</small></article>
          <i className="architecture-arrow">↓</i>
          <article className="architecture-node architecture-node--offchain"><span>MODE B</span><strong>Operator Signer</strong><small>FCC-compatible interface</small></article>
          <i className="architecture-arrow">↓</i>
          {contracts.slice(0, 3).map((contract) => <div key={contract.name} className="architecture-step"><article className="architecture-node"><span>ONCHAIN</span><strong>{contract.name}</strong><small>{contract.detail}</small></article>{contract.name !== "StrategyRouterV2" && <i className="architecture-arrow">↓</i>}</div>)}
          <div className="architecture-branches">
            {contracts.slice(3).map((contract) => <article className="architecture-node" key={contract.name}><span>STRATEGY</span><strong>{contract.name}</strong><small>{contract.detail}</small></article>)}
          </div>
        </div>
        <div className="contract-directory">
          <div className="contract-directory__heading"><div><span>Deployment directory</span><strong>Flare Coston2</strong></div><StatusBadge tone="green">CHAIN 114</StatusBadge></div>
          {contracts.map((contract) => <CopyAddress key={contract.address} label={contract.name} address={contract.address} showFull />)}
        </div>
      </div>
    </section>
  );
}
