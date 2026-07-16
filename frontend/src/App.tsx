import { useState } from "react";
import { PrivateIntentScreen } from "./screens/PrivateIntent";
import { ConfidentialDecisionScreen } from "./screens/ConfidentialDecision";
import { VerifiableExecutionScreen } from "./screens/VerifiableExecution";

export default function App() {
  const [screen, setScreen] = useState(0);

  const vaultAddress = "0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898";
  const routerAddress = "0x1d64CE2a9293F248a7298135932bE9674d39a764";
  const resultHash = "0x68f2749b7b7979f0d4edcbca1e5d2d3dcf397848cec326531c4e6e0ca1468110";
  const transactionHashes = [
    "0x245f207e77f19c3246e84c1df7f1e33794af124263ceffe07850832008376d79",
    "0x8424df2d4833dd07521c529654b3df54a77291fbcd8141cf77fc31d253dcdd27",
    "0xe38ed07e2f77a03b29cc6ba57bc09cfbc2e18f8eda43a7819510f2b019ec2d23",
    "0xe550cd5bde1ae67f15e1ae29f16eaeefe08a1410d18dde9a889a7872d790d1ba",
  ];

  return (
    <div className="app">
      <nav className="screen-nav">
        <button onClick={() => setScreen(0)}>1. Private Intent</button>
        <button onClick={() => setScreen(1)}>2. Confidential Decision</button>
        <button onClick={() => setScreen(2)}>3. Verifiable Execution</button>
      </nav>

      {screen === 0 && (
        <PrivateIntentScreen
          vaultAddress={vaultAddress}
          nonce={1n}
          onSubmit={() => setScreen(1)}
        />
      )}

      {screen === 1 && (
        <ConfidentialDecisionScreen
          fccMode="Mode B — local deterministic signer, NOT hardware TEE"
          resultHash={resultHash}
          allocation={{ idleBps: 5000, upshiftBps: 5000 }}
          ftsoValue={660964n}
          ftsoTimestamp={1784184124n}
          nonce={1n}
          deadline={1784184425n}
          signatureStatus="signed"
        />
      )}

      {screen === 2 && (
        <VerifiableExecutionScreen
          vaultAddress={vaultAddress}
          routerAddress={routerAddress}
          netNAV={3990000n}
          grossNAV={4002499n}
          availableLiquidity={3990000n}
          idleBps={5000}
          upshiftBps={5000}
          executionId={resultHash}
          txHashes={transactionHashes}
          explorerBaseUrl="https://coston2-explorer.flare.network"
        />
      )}
    </div>
  );
}
