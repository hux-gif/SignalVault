interface Props {
  fccMode: string;
  resultHash: string | null;
  allocation: { idleBps: number; upshiftBps: number } | null;
  ftsoValue: bigint | null;
  ftsoTimestamp: bigint | null;
  nonce: bigint;
  deadline: bigint | null;
  signatureStatus: "pending" | "signed" | "verified" | "failed";
}

export function ConfidentialDecisionScreen({
  fccMode, resultHash, allocation, ftsoValue, ftsoTimestamp, nonce, deadline, signatureStatus
}: Props) {
  return (
    <div className="screen">
      <h1>2. Confidential Decision</h1>
      <div className="fcc-info">
        <p>FCC Mode: <strong>{fccMode}</strong></p>
        <p>Result Hash: {resultHash ? <code>{resultHash.slice(0, 18)}...</code> : "pending"}</p>
      </div>
      {allocation && (
        <div className="allocation">
          <p>Allocation: {allocation.idleBps / 100}% idle / {allocation.upshiftBps / 100}% upshift</p>
        </div>
      )}
      {ftsoValue !== null && (
        <div className="ftso">
          <p>FTSO Value: {ftsoValue.toString()}</p>
          <p>FTSO Timestamp: {ftsoTimestamp?.toString()}</p>
        </div>
      )}
      <div className="params">
        <p>Nonce: {nonce.toString()}</p>
        <p>Deadline: {deadline?.toString() || "pending"}</p>
      </div>
      <div className="signature">
        <p>Signature Status: <strong>{signatureStatus}</strong></p>
      </div>
    </div>
  );
}