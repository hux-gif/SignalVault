interface Props {
  vaultAddress: string;
  routerAddress: string;
  netNAV: bigint | null;
  grossNAV: bigint | null;
  availableLiquidity: bigint | null;
  idleBps: number;
  upshiftBps: number;
  executionId: string | null;
  txHashes: string[];
  explorerBaseUrl: string;
}

export function VerifiableExecutionScreen({
  vaultAddress, routerAddress, netNAV, grossNAV, availableLiquidity,
  idleBps, upshiftBps, executionId, txHashes, explorerBaseUrl
}: Props) {
  return (
    <div className="screen">
      <h1>3. Verifiable Execution</h1>
      <div className="addresses">
        <p>Vault: <code>{vaultAddress}</code></p>
        <p>Router: <code>{routerAddress}</code></p>
      </div>
      <div className="nav">
        <p>Net NAV: {netNAV?.toString() || "鈥?}</p>
        <p>Gross NAV: {grossNAV?.toString() || "鈥?}</p>
        <p>Available Liquidity: {availableLiquidity?.toString() || "鈥?}</p>
      </div>
      <div className="exposure">
        <p>Idle: {idleBps / 100}%</p>
        <p>Upshift: {upshiftBps / 100}%</p>
      </div>
      {executionId && (
        <div className="execution">
          <p>Execution ID: <code>{executionId.slice(0, 18)}...</code></p>
        </div>
      )}
      <div className="transactions">
        <h3>Transaction Evidence</h3>
        {txHashes.length === 0 ? (
          <p>No transactions yet</p>
        ) : (
          <ul>
            {txHashes.map((hash, i) => (
              <li key={i}>
                <a href={`${explorerBaseUrl}/tx/${hash}`} target="_blank" rel="noopener noreferrer">
                  {hash.slice(0, 18)}...
                </a>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}