import { useCallback, useEffect, useState } from "react";
import { getAddress } from "viem";
import { Architecture } from "./components/Architecture";
import { BountyCards } from "./components/BountyCards";
import { Footer } from "./components/Footer";
import { Hero } from "./components/Hero";
import { IntentFlow } from "./components/IntentFlow";
import { LiveVault } from "./components/LiveVault";
import { Navbar } from "./components/Navbar";
import { ProofTimeline } from "./components/ProofTimeline";
import { SafetyGrid } from "./components/SafetyGrid";
import { contracts, recordedSnapshot, type LiveSnapshot, type RpcState } from "./lib/evidence";
import { publicClient, STRATEGY_ROUTER_V2_ABI } from "./lib/viem";

type ProviderListener = (value: unknown) => void;

interface EthereumProvider {
  on?: (event: "accountsChanged" | "chainChanged" | "disconnect", listener: ProviderListener) => void;
  removeListener?: (event: "accountsChanged" | "chainChanged" | "disconnect", listener: ProviderListener) => void;
  request(args: { method: string; params?: unknown[] }): Promise<unknown>;
}

declare global {
  interface Window {
    ethereum?: EthereumProvider;
  }
}

const routerAddress = contracts.find((contract) => contract.name === "StrategyRouterV2")!.address;
const COSTON2_CHAIN_ID = "0x72";
const COSTON2_WALLET_PARAMETERS = {
  blockExplorerUrls: ["https://coston2-explorer.flare.network"],
  chainId: COSTON2_CHAIN_ID,
  chainName: "Flare Testnet Coston2",
  nativeCurrency: { decimals: 18, name: "Coston2 Flare", symbol: "C2FLR" },
  rpcUrls: ["https://coston2-api.flare.network/ext/C/rpc"],
};

function hasErrorCode(error: unknown, code: number) {
  return typeof error === "object" && error !== null && "code" in error && (error as { code?: unknown }).code === code;
}

function numericField(value: unknown, field: "idleBps" | "upshiftBps", fallback: number) {
  if (typeof value !== "object" || value === null) return fallback;
  const candidate = (value as Record<string, unknown>)[field];
  if (typeof candidate === "bigint") return Number(candidate);
  if (typeof candidate === "number") return candidate;
  return fallback;
}

export default function App() {
  const [account, setAccount] = useState<string | null>(null);
  const [rpcState, setRpcState] = useState<RpcState>("loading");
  const [snapshot, setSnapshot] = useState<LiveSnapshot>(recordedSnapshot);
  const [walletStatus, setWalletStatus] = useState("Wallet not connected");

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

  useEffect(() => {
    const provider = window.ethereum;
    if (!provider?.on) return;

    const handleChainChanged: ProviderListener = (value) => {
      if (value !== COSTON2_CHAIN_ID) {
        setAccount(null);
        setWalletStatus("Switch to Coston2 · chain ID 114 to continue");
        return;
      }
      setWalletStatus("Coston2 active · connect wallet");
    };
    const handleAccountsChanged: ProviderListener = (value) => {
      const selected = Array.isArray(value) && typeof value[0] === "string" ? value[0] : null;
      setAccount(selected);
      setWalletStatus(selected ? "Wallet account changed · Coston2 chain check required" : "Wallet disconnected");
      void provider.request({ method: "eth_chainId" }).then((chainId) => {
        if (chainId !== COSTON2_CHAIN_ID) {
          setAccount(null);
          setWalletStatus("Switch to Coston2 · chain ID 114 to continue");
        } else if (selected) {
          setWalletStatus("Connected to Flare Coston2 · chain ID 114");
        }
      }).catch(() => {
        setAccount(null);
        setWalletStatus("Wallet network unavailable");
      });
    };
    const handleDisconnect: ProviderListener = () => {
      setAccount(null);
      setWalletStatus("Wallet disconnected");
    };

    provider.on("chainChanged", handleChainChanged);
    provider.on("accountsChanged", handleAccountsChanged);
    provider.on("disconnect", handleDisconnect);
    return () => {
      provider.removeListener?.("chainChanged", handleChainChanged);
      provider.removeListener?.("accountsChanged", handleAccountsChanged);
      provider.removeListener?.("disconnect", handleDisconnect);
    };
  }, []);

  async function connectWallet() {
    if (!window.ethereum) {
      setWalletStatus("Install an EIP-1193 wallet to connect");
      return;
    }

    try {
      let chainId = await window.ethereum.request({ method: "eth_chainId" });
      if (chainId !== COSTON2_CHAIN_ID) {
        setWalletStatus("Switch to Coston2 · chain ID 114 to continue");
        try {
          await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: COSTON2_CHAIN_ID }] });
        } catch (error) {
          if (!hasErrorCode(error, 4_902)) throw error;
          await window.ethereum.request({ method: "wallet_addEthereumChain", params: [COSTON2_WALLET_PARAMETERS] });
          await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: COSTON2_CHAIN_ID }] });
        }
        chainId = await window.ethereum.request({ method: "eth_chainId" });
        if (chainId !== COSTON2_CHAIN_ID) return;
      }

      const accounts = await window.ethereum.request({ method: "eth_requestAccounts" }) as string[];
      const selected = accounts[0];
      if (!selected) {
        setWalletStatus("No wallet account selected");
        return;
      }
      setAccount(selected);
      setWalletStatus("Connected to Flare Coston2 · chain ID 114");
    } catch {
      setWalletStatus("Wallet connection cancelled or Coston2 unavailable");
    }
  }

  return (
    <div className="app">
      <Navbar account={account} onConnect={() => void connectWallet()} walletStatus={walletStatus} />
      <main>
        <Hero rpcState={rpcState} snapshot={snapshot} />
        {walletStatus !== "Wallet not connected" && <div className="wallet-notice section-shell" role="status">{walletStatus}</div>}
        <LiveVault rpcState={rpcState} snapshot={snapshot} onRetry={() => void loadLiveSnapshot()} />
        <IntentFlow />
        <ProofTimeline />
        <SafetyGrid />
        <Architecture />
        <BountyCards />
      </main>
      <Footer />
    </div>
  );
}
