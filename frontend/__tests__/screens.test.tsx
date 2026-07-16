import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { PrivateIntentScreen } from "../src/screens/PrivateIntent";
import { ConfidentialDecisionScreen } from "../src/screens/ConfidentialDecision";
import { VerifiableExecutionScreen } from "../src/screens/VerifiableExecution";

describe("PrivateIntentScreen", () => {
  it("renders vault address and nonce", () => {
    const { getByText } = render(
      <PrivateIntentScreen vaultAddress="0x1234" nonce={1n} onSubmit={() => {}} />
    );
    expect(getByText("0x1234")).toBeTruthy();
    expect(getByText("1")).toBeTruthy();
  });

  it("renders privacy note", () => {
    const { getByText } = render(
      <PrivateIntentScreen vaultAddress="0x1234" nonce={1n} onSubmit={() => {}} />
    );
    expect(getByText(/never stored on-chain/i)).toBeTruthy();
  });
});

describe("ConfidentialDecisionScreen", () => {
  it("renders FCC mode label", () => {
    const { getByText } = render(
      <ConfidentialDecisionScreen
        fccMode="Mode B — local deterministic signer"
        resultHash={null}
        allocation={null}
        ftsoValue={null}
        ftsoTimestamp={null}
        nonce={1n}
        deadline={null}
        signatureStatus="pending"
      />
    );
    expect(getByText(/Mode B/i)).toBeTruthy();
  });

  it("renders allocation when present", () => {
    const { getByText } = render(
      <ConfidentialDecisionScreen
        fccMode="Mode B"
        resultHash="0xabc"
        allocation={{ idleBps: 5000, upshiftBps: 5000 }}
        ftsoValue={100n}
        ftsoTimestamp={123n}
        nonce={1n}
        deadline={456n}
        signatureStatus="signed"
      />
    );
    expect(getByText(/50% idle/i)).toBeTruthy();
  });
});

describe("VerifiableExecutionScreen", () => {
  it("renders vault and router addresses", () => {
    const { getByText } = render(
      <VerifiableExecutionScreen
        vaultAddress="0xVAULT"
        routerAddress="0xROUTER"
        netNAV={1000n}
        grossNAV={1100n}
        availableLiquidity={900n}
        idleBps={5000}
        upshiftBps={5000}
        executionId={null}
        txHashes={[]}
        explorerBaseUrl="https://explorer.example.com"
      />
    );
    expect(getByText("0xVAULT")).toBeTruthy();
    expect(getByText("0xROUTER")).toBeTruthy();
  });

  it("shows no transactions message when empty", () => {
    const { getByText } = render(
      <VerifiableExecutionScreen
        vaultAddress="0xV"
        routerAddress="0xR"
        netNAV={null}
        grossNAV={null}
        availableLiquidity={null}
        idleBps={0}
        upshiftBps={0}
        executionId={null}
        txHashes={[]}
        explorerBaseUrl=""
      />
    );
    expect(getByText(/No transactions yet/i)).toBeTruthy();
  });
});
