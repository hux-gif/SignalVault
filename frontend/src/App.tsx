import { useCallback, useEffect, useState } from "react";
import { getAddress } from "viem";
import { ContractDirectory } from "./components/ContractDirectory";
import { ControlsAudit } from "./components/ControlsAudit";
import { Footer } from "./components/Footer";
import { Header } from "./components/Header";
import { HeroDossier } from "./components/HeroDossier";
import { PrivacyBoundary } from "./components/PrivacyBoundary";
import { VaultState } from "./components/VaultState";
import { VerifiedRun } from "./components/VerifiedRun";
import { WalletDrawer } from "./components/WalletDrawer";
import { useWalletVerification } from "./hooks/useWalletVerification";
import { contracts, recordedSnapshot, transactions, type LiveSnapshot, type RpcState } from "./lib/evidence";
import { publicClient, STRATEGY_ROUTER_V2_ABI } from "./lib/viem";

const routerAddress = contracts.find((contract) => contract.name === "StrategyRouterV2")!.address;

function numericField(value: unknown, field: "idleBps" | "upshiftBps", fallback: number) {
  if (typeof value !== "object" || value === null) return fallback;
  const candidate = (value as Record<string, unknown>)[field];
  if (typeof candidate === "bigint") return Number(candidate);
  if (typeof candidate === "number") return candidate;
  return fallback;
}

export default function App() {
  const wallet = useWalletVerification();
  const [rpcState, setRpcState] = useState<RpcState>("loading");
  const [selectedTransaction, setSelectedTransaction] = useState(2);
  const [snapshot, setSnapshot] = useState<LiveSnapshot>(recordedSnapshot);

  const loadLiveSnapshot = useCallback(async () => {
    setRpcState("loading");
    try {
      const [netAssets, grossAssets, availableLiquidity, allocation] = await Promise.all([
        publicClient.readContract({ address: getAddress(routerAddress), abi: STRATEGY_ROUTER_V2_ABI, functionName: "totalAssets" }),
        publicClient.readContract({ address: getAddress(routerAddress), abi: STRATEGY_ROUTER_V2_ABI, functionName: "grossAssets" }),
        publicClient.readContract({ address: getAddress(routerAddress), abi: STRATEGY_ROUTER_V2_ABI, functionName: "availableLiquidity" }),
        publicClient.readContract({ address: getAddress(routerAddress), abi: STRATEGY_ROUTER_V2_ABI, functionName: "allocation" }),
      ]);

      setSnapshot({
        availableLiquidity: availableLiquidity as bigint,
        grossAssets: grossAssets as bigint,
        idleBps: numericField(allocation, "idleBps", recordedSnapshot.idleBps),
        netAssets: netAssets as bigint,
        upshiftBps: numericField(allocation, "upshiftBps", recordedSnapshot.upshiftBps),
      });
      setRpcState("live");
    } catch {
      setSnapshot(recordedSnapshot);
      setRpcState("degraded");
    }
  }, []);

  useEffect(() => {
    void loadLiveSnapshot();
  }, [loadLiveSnapshot]);

  return (
    <div className="app">
      <Header account={wallet.state === "connected" ? wallet.account : null} onVerify={wallet.openDrawer} rpcState={rpcState} />
      <main>
        <HeroDossier onVerify={wallet.openDrawer} />
        <VerifiedRun
          selected={selectedTransaction}
          transaction={transactions[selectedTransaction]}
          onSelect={setSelectedTransaction}
        />
        <PrivacyBoundary />
        <VaultState rpcState={rpcState} snapshot={snapshot} onRetry={() => void loadLiveSnapshot()} />
        <ControlsAudit />
        <ContractDirectory />
      </main>
      <Footer />
      <WalletDrawer
        account={wallet.account}
        addingNetworkPending={wallet.addingNetworkPending}
        isOpen={wallet.drawerOpen}
        rejectedAction={wallet.rejectedAction}
        state={wallet.state}
        onAddNetwork={() => void wallet.addNetwork()}
        onClose={wallet.closeDrawer}
        onDisconnect={wallet.disconnect}
        onRequestAccounts={() => void wallet.requestAccounts()}
        onRetryRejected={wallet.retryRejected}
        onSwitchNetwork={() => void wallet.switchNetwork()}
      />
    </div>
  );
}
