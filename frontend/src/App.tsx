import { useState } from "react";
import { PrivateIntentScreen } from "./screens/PrivateIntent";
import { ConfidentialDecisionScreen } from "./screens/ConfidentialDecision";
import { VerifiableExecutionScreen } from "./screens/VerifiableExecution";

export default function App() {
  const [screen, setScreen] = useState(0);

  const vaultAddress = "0x0000000000000000000000000000000000000000";
  const routerAddress = "0x0000000000000000000000000000000000000001";

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
          resultHash="0x0000000000000000000000000000000000000000000000000000000000000000"
          allocation={{ idleBps: 5000, upshiftBps: 5000 }}
          ftsoValue={100n}
          ftsoTimestamp={123n}
          nonce={1n}
          deadline={456n}
          signatureStatus="signed"
        />
      )}

      {screen === 2 && (
        <VerifiableExecutionScreen
          vaultAddress={vaultAddress}
          routerAddress={routerAddress}
          netNAV={1000n}
          grossNAV={1100n}
          availableLiquidity={900n}
          idleBps={5000}
          upshiftBps={5000}
          executionId="0x0000000000000000000000000000000000000000000000000000000000000000"
          txHashes={[]}
          explorerBaseUrl="https://coston2-explorer.flare.network"
        />
      )}
    </div>
  );
}
