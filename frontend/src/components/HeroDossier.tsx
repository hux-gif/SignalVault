interface Props {
  onVerify: () => void;
}

export function HeroDossier({ onVerify }: Props) {
  return (
    <section className="hero-dossier page-shell" id="top">
      <div className="hero-dossier__index">
        <span>Execution dossier</span>
        <strong>Run / 001</strong>
      </div>
      <div className="hero-dossier__copy">
        <p className="kicker">PERSONAL FXRP VAULT · FLARE COSTON2</p>
        <h1><span>Private strategy.</span><span>Public proof.</span></h1>
        <p className="hero-dossier__lede">A personal FXRP vault turned one private risk intent into a verified 50/50 Idle–Upshift execution on Flare.</p>
        <div className="hero-dossier__actions">
          <a className="button button--ink" href="#verified-run">Inspect the verified run</a>
          <button className="button button--paper" type="button" onClick={onVerify}>Verify with wallet</button>
        </div>
      </div>
      <div className="hero-dossier__facts" aria-label="Verified execution facts">
        <div><span>Deployment</span><strong>Coston2 · Chain 114</strong></div>
        <div><span>Deposit</span><strong>5.000000 FXRP</strong></div>
        <div><span>Allocation</span><strong>50% Idle / 50% Upshift</strong></div>
        <div><span>Exit evidence</span><strong>997,500 base units</strong></div>
      </div>
    </section>
  );
}
