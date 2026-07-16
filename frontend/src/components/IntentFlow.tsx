import { useState } from "react";
import { evidence, formatAddress, formatTimestamp } from "../lib/evidence";

const steps = [
  { index: "01", title: "Private Intent", caption: "Never published onchain", detail: "A user's risk preference stays offchain. Only its salted commitment crosses the trust boundary." },
  { index: "02", title: "Salted Commitment", caption: formatAddress(evidence.commitment, 10, 8), detail: `Commitment ${evidence.commitment} binds the hidden intent without revealing it.` },
  { index: "03", title: "Live FTSOv2 Input", caption: "$0.660964 · recorded", detail: `Value ${evidence.ftsoValue} with 6 decimals, timestamp ${formatTimestamp(evidence.ftsoTimestamp)}.` },
  { index: "04", title: "Mode B Signed Result", caption: formatAddress(evidence.resultHash, 10, 8), detail: `Signer ${evidence.trustedSigner}. FCC-compatible simulated attestation; not hardware-backed TEE.` },
  { index: "05", title: "Onchain Authentication", caption: `Nonce ${evidence.nonce} · EIP-712`, detail: `Deadline ${formatTimestamp(evidence.deadline)}. routerConfigHash ${evidence.routerConfigHash}.` },
  { index: "06", title: "Differential Execution", caption: "50% Idle · 50% Upshift", detail: `Execution ID ${evidence.executionId}. Only the required delta moved; signed maximum loss was 100 bps.` },
] as const;

export function IntentFlow() {
  const [active, setActive] = useState(0);

  return (
    <section className="section-shell section-block flow-section" id="flow">
      <div className="section-heading">
        <div><p className="eyebrow">INTENT → EXECUTION</p><h2>Private by default. Verifiable by design.</h2></div>
        <p className="section-heading__copy">Follow one authenticated signal from an offchain boundary to a measured, differential FXRP allocation.</p>
      </div>
      <div className="flow-track" role="list">
        <span className="flow-track__line" aria-hidden="true"><i /></span>
        {steps.map((step, index) => (
          <div className="flow-track__item" key={step.index} role="listitem">
            <button className={active === index ? "flow-node flow-node--active" : "flow-node"} type="button" onClick={() => setActive(index)} aria-pressed={active === index}>
              <span>{step.index}</span><strong>{step.title}</strong><small>{step.caption}</small>
            </button>
          </div>
        ))}
      </div>
      <div className="flow-detail surface-card" aria-live="polite">
        <div className="flow-detail__index">{steps[active].index}</div>
        <div><span>{steps[active].title}</span><strong>{steps[active].caption}</strong><p>{steps[active].detail}</p></div>
        <div className="flow-detail__seal">VERIFIED<br /><small>CANONICAL EVIDENCE</small></div>
      </div>
    </section>
  );
}
