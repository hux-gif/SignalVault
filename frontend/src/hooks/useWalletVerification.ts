import { useCallback, useEffect, useRef, useState } from "react";
import { coston2 } from "../lib/chains";
import { contracts } from "../lib/evidence";

type ProviderListener = (value: unknown) => void;

export interface EthereumProvider {
  on?: (event: "accountsChanged" | "chainChanged" | "disconnect", listener: ProviderListener) => void;
  removeListener?: (event: "accountsChanged" | "chainChanged" | "disconnect", listener: ProviderListener) => void;
  request(args: { method: string; params?: unknown[] }): Promise<unknown>;
}

declare global {
  interface Window {
    ethereum?: EthereumProvider;
  }
}

export type WalletVerificationState =
  | "idle"
  | "wallet_missing"
  | "requesting_accounts"
  | "user_rejected"
  | "wrong_network"
  | "switching_network"
  | "adding_network"
  | "connected"
  | "disconnected"
  | "rpc_error";

export type RejectedAction = "accounts" | "switch" | "add";

export const COSTON2_CHAIN_ID = `0x${coston2.id.toString(16)}`;

const vaultAddress = contracts.find((contract) => contract.name === "SignalVaultV2")!.address;
const COSTON2_WALLET_PARAMETERS = {
  blockExplorerUrls: [coston2.blockExplorers.default.url],
  chainId: COSTON2_CHAIN_ID,
  chainName: coston2.name,
  nativeCurrency: coston2.nativeCurrency,
  rpcUrls: [...coston2.rpcUrls.default.http],
};

function hasErrorCode(error: unknown, code: number) {
  return typeof error === "object" && error !== null && "code" in error && (error as { code?: unknown }).code === code;
}

function firstAccount(value: unknown) {
  return Array.isArray(value) && typeof value[0] === "string" ? value[0] : null;
}

async function hasVaultBytecode(provider: EthereumProvider) {
  const code = await provider.request({ method: "eth_getCode", params: [vaultAddress, "latest"] });
  return typeof code === "string" && code !== "0x" && code !== "0x0";
}

export function useWalletVerification() {
  const [account, setAccount] = useState<string | null>(null);
  const [addingNetworkPending, setAddingNetworkPending] = useState(false);
  const [chainId, setChainId] = useState<string | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [rejectedAction, setRejectedAction] = useState<RejectedAction>("accounts");
  const [state, setState] = useState<WalletVerificationState>("idle");
  const accountRef = useRef<string | null>(null);
  const chainIdRef = useRef<string | null>(null);
  const stateRef = useRef<WalletVerificationState>("idle");
  const verificationVersion = useRef(0);

  accountRef.current = account;
  chainIdRef.current = chainId;
  stateRef.current = state;

  const openDrawer = useCallback(() => setDrawerOpen(true), []);
  const closeDrawer = useCallback(() => setDrawerOpen(false), []);

  const finishVerification = useCallback(async (provider: EthereumProvider, nextChainId: string, selectedAccount: string | null, version: number) => {
    if (version !== verificationVersion.current) return;
    chainIdRef.current = nextChainId;
    setChainId(nextChainId);
    if (nextChainId !== COSTON2_CHAIN_ID) {
      setState("wrong_network");
      return;
    }
    if (!selectedAccount) {
      setState("disconnected");
      return;
    }
    const bytecodeExists = await hasVaultBytecode(provider);
    if (version !== verificationVersion.current) return;
    if (!bytecodeExists) throw new Error("SignalVaultV2 bytecode unavailable");
    setState("connected");
  }, []);

  const requestAccounts = useCallback(async () => {
    const provider = window.ethereum;
    if (!provider) {
      setState("wallet_missing");
      return;
    }

    const version = ++verificationVersion.current;
    stateRef.current = "requesting_accounts";
    setState("requesting_accounts");
    try {
      const selected = firstAccount(await provider.request({ method: "eth_requestAccounts" }));
      if (version !== verificationVersion.current) return;
      if (!selected) {
        accountRef.current = null;
        setAccount(null);
        setState("disconnected");
        return;
      }
      setAccount(selected);
      accountRef.current = selected;
      const nextChainId = await provider.request({ method: "eth_chainId" });
      if (version !== verificationVersion.current) return;
      if (typeof nextChainId !== "string") throw new Error("Invalid eth_chainId response");
      await finishVerification(provider, nextChainId, selected, version);
    } catch (error) {
      if (version !== verificationVersion.current) return;
      accountRef.current = null;
      setAccount(null);
      if (hasErrorCode(error, 4_001)) {
        setRejectedAction("accounts");
        setState("user_rejected");
      } else {
        setState("rpc_error");
      }
    }
  }, [finishVerification]);

  const switchNetwork = useCallback(async () => {
    const provider = window.ethereum;
    if (!provider) {
      setState("wallet_missing");
      return;
    }

    const version = ++verificationVersion.current;
    setState("switching_network");
    try {
      await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: COSTON2_CHAIN_ID }] });
      if (version !== verificationVersion.current) return;
      const nextChainId = await provider.request({ method: "eth_chainId" });
      if (version !== verificationVersion.current) return;
      if (typeof nextChainId !== "string") throw new Error("Invalid eth_chainId response");
      await finishVerification(provider, nextChainId, account, version);
    } catch (error) {
      if (version !== verificationVersion.current) return;
      if (hasErrorCode(error, 4_902)) {
        setState("adding_network");
      } else if (hasErrorCode(error, 4_001)) {
        setRejectedAction("switch");
        setState("user_rejected");
      } else {
        setState("rpc_error");
      }
    }
  }, [account, finishVerification]);

  const addNetwork = useCallback(async () => {
    const provider = window.ethereum;
    if (!provider) {
      setState("wallet_missing");
      return;
    }

    const version = ++verificationVersion.current;
    setAddingNetworkPending(true);
    try {
      await provider.request({ method: "wallet_addEthereumChain", params: [COSTON2_WALLET_PARAMETERS] });
    } catch (error) {
      setAddingNetworkPending(false);
      if (version !== verificationVersion.current) return;
      if (hasErrorCode(error, 4_001)) {
        setRejectedAction("add");
        setState("user_rejected");
      } else {
        setState("rpc_error");
      }
      return;
    }

    if (version !== verificationVersion.current) {
      setAddingNetworkPending(false);
      return;
    }
    setAddingNetworkPending(false);
    setState("switching_network");
    try {
      await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: COSTON2_CHAIN_ID }] });
      if (version !== verificationVersion.current) return;
      const nextChainId = await provider.request({ method: "eth_chainId" });
      if (version !== verificationVersion.current) return;
      if (typeof nextChainId !== "string") throw new Error("Invalid eth_chainId response");
      await finishVerification(provider, nextChainId, account, version);
    } catch (error) {
      if (version !== verificationVersion.current) return;
      if (hasErrorCode(error, 4_001)) {
        setRejectedAction("switch");
        setState("user_rejected");
      } else {
        setState("rpc_error");
      }
    }
  }, [account, finishVerification]);

  const retryRejected = useCallback(() => {
    if (rejectedAction === "switch") return void switchNetwork();
    if (rejectedAction === "add") return void addNetwork();
    return void requestAccounts();
  }, [addNetwork, rejectedAction, requestAccounts, switchNetwork]);

  const disconnect = useCallback(() => {
    verificationVersion.current += 1;
    accountRef.current = null;
    chainIdRef.current = null;
    setAccount(null);
    setChainId(null);
    setState("disconnected");
  }, []);

  useEffect(() => {
    const provider = window.ethereum;
    if (!provider?.on) return;

    const handleAccountsChanged: ProviderListener = (value) => {
      const selected = firstAccount(value);
      if (selected && stateRef.current === "requesting_accounts") {
        accountRef.current = selected;
        setAccount(selected);
        return;
      }
      if (selected?.toLowerCase() === accountRef.current?.toLowerCase()) return;
      const version = ++verificationVersion.current;
      accountRef.current = selected;
      setAccount(selected);
      if (!selected) {
        setState("disconnected");
      } else if (chainIdRef.current === COSTON2_CHAIN_ID) {
        void hasVaultBytecode(provider)
          .then((exists) => { if (version === verificationVersion.current) setState(exists ? "connected" : "rpc_error"); })
          .catch(() => { if (version === verificationVersion.current) setState("rpc_error"); });
      } else {
        setState("wrong_network");
      }
    };
    const handleChainChanged: ProviderListener = (value) => {
      const nextChainId = typeof value === "string" ? value : null;
      if (nextChainId === chainIdRef.current) return;
      const version = ++verificationVersion.current;
      chainIdRef.current = nextChainId;
      setChainId(nextChainId);
      if (!accountRef.current) {
        setState("disconnected");
      } else if (nextChainId === COSTON2_CHAIN_ID) {
        void hasVaultBytecode(provider)
          .then((exists) => { if (version === verificationVersion.current) setState(exists ? "connected" : "rpc_error"); })
          .catch(() => { if (version === verificationVersion.current) setState("rpc_error"); });
      } else {
        setState("wrong_network");
      }
    };
    const handleDisconnect: ProviderListener = () => disconnect();

    provider.on("accountsChanged", handleAccountsChanged);
    provider.on("chainChanged", handleChainChanged);
    provider.on("disconnect", handleDisconnect);
    return () => {
      provider.removeListener?.("accountsChanged", handleAccountsChanged);
      provider.removeListener?.("chainChanged", handleChainChanged);
      provider.removeListener?.("disconnect", handleDisconnect);
    };
  }, [disconnect]);

  return {
    account,
    addNetwork,
    addingNetworkPending,
    chainId,
    closeDrawer,
    disconnect,
    drawerOpen,
    openDrawer,
    rejectedAction,
    requestAccounts,
    retryRejected,
    state,
    switchNetwork,
  };
}
