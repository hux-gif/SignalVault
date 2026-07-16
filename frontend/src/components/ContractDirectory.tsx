import { contracts } from "../lib/evidence";
import { CopyAddress } from "./CopyAddress";

export function ContractDirectory() {
  return (
    <section className="contract-directory page-shell section-rule" id="contracts">
      <header className="section-intro section-intro--compact">
        <p className="section-number">05</p>
        <div><p className="kicker">DEPLOYED CONTRACTS</p><h2>Five Coston2 addresses define this verified run.</h2></div>
      </header>
      <div className="contract-directory__list">
        {contracts.map((contract) => <CopyAddress key={contract.address} address={contract.address} label={contract.name} showFull />)}
      </div>
    </section>
  );
}
