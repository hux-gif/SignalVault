import { useEffect, useRef } from "react";
import type { RejectedAction, WalletVerificationState } from "../hooks/useWalletVerification";
import { EXPLORER_BASE_URL, formatAddress } from "../lib/evidence";

interface Props {
  account: string | null;
  addingNetworkPending: boolean;
  isOpen: boolean;
  onAddNetwork: () => void;
  onClose: () => void;
  onDisconnect: () => void;
  onRequestAccounts: () => void;
  onRetryRejected: () => void;
  onSwitchNetwork: () => void;
  rejectedAction: RejectedAction;
  state: WalletVerificationState;
}

const focusableSelector = "a[href], button:not([disabled])";

export function WalletDrawer({ account, addingNetworkPending, isOpen, onAddNetwork, onClose, onDisconnect, onRequestAccounts, onRetryRejected, onSwitchNetwork, rejectedAction, state }: Props) {
  const closeButton = useRef<HTMLButtonElement>(null);
  const drawer = useRef<HTMLElement>(null);
  const previousFocus = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    previousFocus.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    closeButton.current?.focus();

    const handleKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onClose();
        return;
      }
      if (event.key !== "Tab") return;
      const drawerElement = drawer.current;
      const focusable = Array.from(drawerElement?.querySelectorAll<HTMLElement>(focusableSelector) ?? []);
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (!drawerElement?.contains(document.activeElement)) {
        event.preventDefault();
        (event.shiftKey ? last : first).focus();
      } else if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    window.addEventListener("keydown", handleKey);
    return () => {
      window.removeEventListener("keydown", handleKey);
      previousFocus.current?.focus();
    };
  }, [isOpen, onClose]);

  useEffect(() => {
    if (isOpen && drawer.current && !drawer.current.contains(document.activeElement)) closeButton.current?.focus();
  }, [addingNetworkPending, isOpen, state]);

  if (!isOpen) return null;

  const accountRejected = rejectedAction === "accounts";
  const rejectionTitle = accountRejected ? "Connection cancelled" : rejectedAction === "switch" ? "Network switch cancelled" : "Network addition cancelled";
  const rejectionCopy = accountRejected
    ? "No account was connected. You can still inspect the verified execution."
    : "Your account remains selected. The Coston2 network change was not approved.";
  const rejectionAction = accountRejected ? "Try again" : rejectedAction === "switch" ? "Retry network switch" : "Retry network addition";

  return (
    <div className="wallet-overlay" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <aside ref={drawer} className="wallet-drawer" role="dialog" aria-modal="true" aria-labelledby="wallet-title">
        <div className="wallet-drawer__head"><div><p>NETWORK VERIFICATION</p><h2 id="wallet-title">Verify with wallet</h2></div><button ref={closeButton} type="button" onClick={onClose} aria-label="Close wallet verification">×</button></div>
        <p className="wallet-drawer__intro">Connect an EVM wallet to verify chain 114 and the deployed SignalVaultV2 bytecode on Coston2.</p>
        <ul className="wallet-assurances"><li>No transaction will be sent</li><li>No signature will be requested</li><li>Your address is not stored</li></ul>
        <div className="wallet-network"><span>Network required</span><strong>Coston2 · Chain 114</strong></div>
        <div className="wallet-state" aria-live="polite">
          {state === "idle" && <><h3>Ready to verify</h3><p>Your wallet will expose the selected address, active chain and read-only contract bytecode.</p><button className="button button--ink" type="button" onClick={onRequestAccounts}>Browser Wallet</button></>}
          {state === "wallet_missing" && <><h3>No browser wallet detected</h3><p>Install an EVM wallet or open this page inside a wallet browser.</p><div className="wallet-state__actions"><a className="button button--ink" href="https://metamask.io/download/" target="_blank" rel="noreferrer">Install MetaMask</a><button className="text-button" type="button" onClick={onClose}>Continue in read-only mode</button></div></>}
          {state === "requesting_accounts" && <><span className="wallet-spinner" aria-hidden="true" /><h3>Waiting for wallet approval…</h3><p>Check your wallet extension.</p></>}
          {state === "user_rejected" && <><h3>{rejectionTitle}</h3><p>{rejectionCopy}</p><button className="button button--ink" type="button" onClick={onRetryRejected}>{rejectionAction}</button></>}
          {state === "wrong_network" && <><h3>Wrong network</h3><p>SignalVault is deployed on Coston2. Switch the selected account to chain 114.</p><button className="button button--ink" type="button" onClick={onSwitchNetwork}>Switch to Coston2</button></>}
          {state === "switching_network" && <><span className="wallet-spinner" aria-hidden="true" /><h3>Switching to Coston2…</h3><p>Approve the network change in your wallet.</p></>}
          {state === "adding_network" && addingNetworkPending && <><span className="wallet-spinner" aria-hidden="true" /><h3>Waiting for network approval…</h3><p>Review the Coston2 configuration in your wallet.</p></>}
          {state === "adding_network" && !addingNetworkPending && <><h3>Coston2 is not configured in this wallet.</h3><p>The verified chain configuration will be shown by your wallet before it is added.</p><button className="button button--ink" type="button" onClick={onAddNetwork}>Add Coston2 network</button></>}
          {state === "connected" && account && <><span className="wallet-check" aria-hidden="true">✓</span><h3>Wallet verified</h3><code>{formatAddress(account)}</code><p><strong>Coston2 · Chain 114</strong><br />SignalVaultV2 bytecode found</p><p>This wallet connection is read-only. No transaction has been requested.</p><div className="wallet-state__actions"><a className="button button--ink" href={`${EXPLORER_BASE_URL}/address/${account}`} target="_blank" rel="noreferrer">View account on Explorer</a><button className="text-button" type="button" onClick={onDisconnect}>Disconnect</button></div></>}
          {state === "disconnected" && <><h3>Wallet disconnected</h3><p>No account is retained by this page.</p><button className="button button--ink" type="button" onClick={onRequestAccounts}>Verify again</button></>}
          {state === "rpc_error" && <><h3>Verification unavailable</h3><p>The wallet did not return a usable account, chain or SignalVaultV2 bytecode response. No transaction was requested.</p><button className="button button--ink" type="button" onClick={onRequestAccounts}>Try again</button></>}
        </div>
      </aside>
    </div>
  );
}
