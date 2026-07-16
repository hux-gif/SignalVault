import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { readContractMock } = vi.hoisted(() => ({
  readContractMock: vi.fn(),
}));

vi.mock("../src/lib/viem", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../src/lib/viem")>()),
  publicClient: {
    readContract: readContractMock,
  },
}));

import App from "../src/App";

const accountA = "0x1111111111111111111111111111111111111111";
const accountB = "0x2222222222222222222222222222222222222222";
const contractAddresses = [
  "0x2C7b2a5620fbf25a65c81257F16b8437f5Af492a",
  "0x1d64CE2a9293F248a7298135932bE9674d39a764",
  "0xD0Ee1664e21aE9529f6cCCf94A70C29C7396fFD8",
  "0x6bF0f5f7e9595171246C888F9AC10c830e1D81Db",
  "0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898",
];
const transactionHashes = [
  "0x245f207e77f19c3246e84c1df7f1e33794af124263ceffe07850832008376d79",
  "0x8424df2d4833dd07521c529654b3df54a77291fbcd8141cf77fc31d253dcdd27",
  "0xe38ed07e2f77a03b29cc6ba57bc09cfbc2e18f8eda43a7819510f2b019ec2d23",
  "0xe550cd5bde1ae67f15e1ae29f16eaeefe08a1410d18dde9a889a7872d790d1ba",
];

type Listener = (value: unknown) => void;

function mockLiveRpc() {
  readContractMock.mockImplementation(({ functionName }: { functionName: string }) => {
    const values: Record<string, unknown> = {
      allocation: { idleBps: 5_000, upshiftBps: 5_000 },
      availableLiquidity: 3_990_000n,
      grossAssets: 4_002_499n,
      totalAssets: 3_990_000n,
    };
    return Promise.resolve(values[functionName]);
  });
}

function installProvider({ account = accountA, chainId = "0x72" } = {}) {
  const listeners: Record<string, Listener> = {};
  let currentChain = chainId;
  const request = vi.fn(async ({ method }: { method: string; params?: unknown[] }) => {
    if (method === "eth_requestAccounts") return [account];
    if (method === "eth_chainId") return currentChain;
    if (method === "eth_getCode") return "0x60006000";
    if (method === "wallet_switchEthereumChain") {
      currentChain = "0x72";
      return null;
    }
    if (method === "wallet_addEthereumChain") return null;
    return null;
  });
  window.ethereum = {
    request,
    on: vi.fn((event: string, listener: Listener) => { listeners[event] = listener; }),
    removeListener: vi.fn(),
  };
  return { listeners, request };
}

async function renderLiveApp() {
  render(<App />);
  await screen.findByText("Coston2 RPC live");
}

async function openWalletDrawer() {
  fireEvent.click(screen.getAllByRole("button", { name: "Verify with wallet" })[0]);
  return screen.findByRole("dialog", { name: "Verify with wallet" });
}

describe("SignalVault execution dossier", () => {
  beforeEach(() => {
    mockLiveRpc();
    delete window.ethereum;
  });

  afterEach(() => {
    cleanup();
    vi.clearAllMocks();
  });

  it("opens a wallet-verification drawer before requesting access", async () => {
    await renderLiveApp();
    await openWalletDrawer();

    expect(screen.getByText("No transaction will be sent")).toBeTruthy();
    expect(screen.getByText("No signature will be requested")).toBeTruthy();
    expect(screen.getByText("Your address is not stored")).toBeTruthy();
    expect(screen.getAllByText(/Coston2 · Chain 114/i).length).toBeGreaterThan(0);
  });

  it("shows a wallet-missing state without window.ethereum", async () => {
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));

    expect(await screen.findByText("No browser wallet detected")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Install MetaMask" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Continue in read-only mode" })).toBeTruthy();
  });

  it("requests accounts only after Browser Wallet is selected", async () => {
    const { request } = installProvider();
    await renderLiveApp();
    await openWalletDrawer();
    expect(request).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));

    await screen.findByText("Wallet verified");
    expect(request).toHaveBeenCalledWith({ method: "eth_requestAccounts" });
  });

  it("turns EIP-1193 rejection 4001 into a retryable cancellation state", async () => {
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_requestAccounts") throw Object.assign(new Error("rejected"), { code: 4_001 });
      return null;
    });
    window.ethereum = { request };
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));

    expect(await screen.findByText("Connection cancelled")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Try again" })).toBeTruthy();
  });

  it("offers an explicit Coston2 switch when the account is on another chain", async () => {
    installProvider({ chainId: "0x1" });
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));

    expect(await screen.findByText("Wrong network")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Switch to Coston2" })).toBeTruthy();
  });

  it("offers the verified add-network request after an unknown-chain response", async () => {
    let currentChain = "0x1";
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_requestAccounts") return [accountA];
      if (method === "eth_chainId") return currentChain;
      if (method === "eth_getCode") return "0x60006000";
      if (method === "wallet_switchEthereumChain") {
        if (currentChain === "0x1") throw Object.assign(new Error("unknown chain"), { code: 4_902 });
        return null;
      }
      if (method === "wallet_addEthereumChain") {
        currentChain = "0x72";
        return null;
      }
      return null;
    });
    window.ethereum = { request };
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));
    fireEvent.click(await screen.findByRole("button", { name: "Switch to Coston2" }));

    expect(await screen.findByText("Coston2 is not configured in this wallet.")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Add Coston2 network" }));

    expect(await screen.findByText("Wallet verified")).toBeTruthy();
    expect(request).toHaveBeenCalledWith({
      method: "wallet_addEthereumChain",
      params: [expect.objectContaining({
        chainId: "0x72",
        rpcUrls: ["https://coston2-api.flare.network/ext/C/rpc"],
      })],
    });
  });

  it("shows progress and prevents duplicate clicks while adding Coston2", async () => {
    let resolveAdd: (() => void) | undefined;
    let currentChain = "0x1";
    const addApproval = new Promise<void>((resolve) => { resolveAdd = resolve; });
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_requestAccounts") return [accountA];
      if (method === "eth_chainId") return currentChain;
      if (method === "eth_getCode") return "0x60006000";
      if (method === "wallet_switchEthereumChain") {
        if (currentChain === "0x1") throw Object.assign(new Error("unknown chain"), { code: 4_902 });
        return null;
      }
      if (method === "wallet_addEthereumChain") {
        await addApproval;
        currentChain = "0x72";
        return null;
      }
      return null;
    });
    window.ethereum = { request };
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));
    fireEvent.click(await screen.findByRole("button", { name: "Switch to Coston2" }));
    fireEvent.click(await screen.findByRole("button", { name: "Add Coston2 network" }));

    expect(await screen.findByText("Waiting for network approval…")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Add Coston2 network" })).toBeNull();

    await act(async () => { resolveAdd?.(); await addApproval; });
    expect(await screen.findByText("Wallet verified")).toBeTruthy();
  });

  it("keeps network rejection context and retries the rejected switch", async () => {
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_requestAccounts") return [accountA];
      if (method === "eth_chainId") return "0x1";
      if (method === "wallet_switchEthereumChain") throw Object.assign(new Error("rejected"), { code: 4_001 });
      return null;
    });
    window.ethereum = { request };
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));
    fireEvent.click(await screen.findByRole("button", { name: "Switch to Coston2" }));

    expect(await screen.findByText("Network switch cancelled")).toBeTruthy();
    expect(screen.getByText(/account remains selected/i)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Retry network switch" })).toBeTruthy();
    expect(screen.queryByText(/No account was connected/i)).toBeNull();
  });

  it("labels a rejected post-add switch as a switch cancellation", async () => {
    let switchAttempts = 0;
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_requestAccounts") return [accountA];
      if (method === "eth_chainId") return "0x1";
      if (method === "wallet_addEthereumChain") return null;
      if (method === "wallet_switchEthereumChain") {
        switchAttempts += 1;
        throw Object.assign(new Error(switchAttempts === 1 ? "unknown chain" : "rejected"), { code: switchAttempts === 1 ? 4_902 : 4_001 });
      }
      return null;
    });
    window.ethereum = { request };
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));
    fireEvent.click(await screen.findByRole("button", { name: "Switch to Coston2" }));
    fireEvent.click(await screen.findByRole("button", { name: "Add Coston2 network" }));

    expect(await screen.findByText("Network switch cancelled")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Retry network switch" })).toBeTruthy();
    expect(screen.queryByText("Network addition cancelled")).toBeNull();
  });

  it("shows the verified account and chain 114 after connecting", async () => {
    installProvider();
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));

    expect(await screen.findByText("Wallet verified")).toBeTruthy();
    expect(screen.getAllByText("0x1111…1111").length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Coston2 · Chain 114/i).length).toBeGreaterThan(0);
    expect(screen.getByRole("link", { name: "View account on Explorer" }).getAttribute("href")).toContain(accountA);
    expect(window.ethereum?.request).toHaveBeenCalledWith({
      method: "eth_getCode",
      params: ["0x730CbAc00b4bfbBE4D9985Bf4eCe222bB6399898", "latest"],
    });
  });

  it("updates the visible account after accountsChanged", async () => {
    const { listeners } = installProvider();
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));
    await screen.findByText("Wallet verified");

    await act(async () => { listeners.accountsChanged([accountB]); });

    expect(screen.getAllByText("0x2222…2222").length).toBeGreaterThan(0);
  });

  it("updates the drawer when chainChanged leaves Coston2", async () => {
    const { listeners } = installProvider();
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));
    await screen.findByText("Wallet verified");

    act(() => { listeners.chainChanged("0x1"); });

    expect(screen.getByText("Wrong network")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Switch to Coston2" })).toBeTruthy();
    expect(screen.getAllByRole("button", { name: "Verify with wallet" }).length).toBeGreaterThan(0);
  });

  it("returns to a disconnected state after the provider disconnects", async () => {
    const { listeners } = installProvider();
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));
    await screen.findByText("Wallet verified");

    act(() => { listeners.disconnect({ code: 4_900 }); });

    expect(screen.getByText("Wallet disconnected")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Verify again" })).toBeTruthy();
  });

  it("never enters connected state from a chain event without an account", async () => {
    const { listeners } = installProvider();
    await renderLiveApp();

    act(() => { listeners.chainChanged("0x72"); });
    await openWalletDrawer();

    expect(screen.getByText("Wallet disconnected")).toBeTruthy();
    expect(screen.queryByText("Wallet verified")).toBeNull();
  });

  it("does not let stale bytecode verification overwrite a disconnect", async () => {
    const listeners: Record<string, Listener> = {};
    let resolveCode: ((value: string) => void) | undefined;
    const codeResponse = new Promise<string>((resolve) => { resolveCode = resolve; });
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_requestAccounts") return [accountA];
      if (method === "eth_chainId") return "0x72";
      if (method === "eth_getCode") return codeResponse;
      return null;
    });
    window.ethereum = {
      request,
      on: vi.fn((event: string, listener: Listener) => { listeners[event] = listener; }),
      removeListener: vi.fn(),
    };
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));
    await waitFor(() => expect(request).toHaveBeenCalledWith(expect.objectContaining({ method: "eth_getCode" })));

    act(() => { listeners.disconnect({ code: 4_900 }); });
    await act(async () => { resolveCode?.("0x60006000"); await codeResponse; });

    expect(screen.getByText("Wallet disconnected")).toBeTruthy();
    expect(screen.queryByText("Wallet verified")).toBeNull();
  });

  it("requires deployed SignalVaultV2 bytecode before reporting verification", async () => {
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_requestAccounts") return [accountA];
      if (method === "eth_chainId") return "0x72";
      if (method === "eth_getCode") return "0x";
      return null;
    });
    window.ethereum = { request };
    await renderLiveApp();
    await openWalletDrawer();
    fireEvent.click(screen.getByRole("button", { name: "Browser Wallet" }));

    expect(await screen.findByText("Verification unavailable")).toBeTruthy();
    expect(screen.queryByText("Wallet verified")).toBeNull();
  });

  it("traps drawer focus and restores it to the opening control", async () => {
    await renderLiveApp();
    const opener = screen.getAllByRole("button", { name: "Verify with wallet" })[0];
    opener.focus();
    fireEvent.click(opener);
    const close = await screen.findByRole("button", { name: "Close wallet verification" });
    expect(document.activeElement).toBe(close);

    fireEvent.keyDown(window, { key: "Tab", shiftKey: true });
    expect(document.activeElement).toBe(screen.getByRole("button", { name: "Browser Wallet" }));
    fireEvent.keyDown(window, { key: "Escape" });

    expect(screen.queryByRole("dialog", { name: "Verify with wallet" })).toBeNull();
    expect(document.activeElement).toBe(opener);
  });

  it("recovers focus when a pending wallet state removes its action", async () => {
    const pendingAccounts = new Promise<string[]>(() => undefined);
    window.ethereum = { request: vi.fn(async ({ method }: { method: string }) => method === "eth_requestAccounts" ? pendingAccounts : null) };
    await renderLiveApp();
    await openWalletDrawer();
    const browserWallet = screen.getByRole("button", { name: "Browser Wallet" });
    browserWallet.focus();
    fireEvent.click(browserWallet);

    expect(await screen.findByText("Waiting for wallet approval…")).toBeTruthy();
    const close = screen.getByRole("button", { name: "Close wallet verification" });
    expect(document.activeElement).toBe(close);
    fireEvent.keyDown(window, { key: "Tab" });
    expect(document.activeElement).toBe(close);
  });

  it("links all four canonical Coston2 transactions to Explorer", async () => {
    await renderLiveApp();

    for (const hash of transactionHashes) {
      expect(document.querySelector(`a[href$="${hash}"]`)).toBeTruthy();
    }
  });

  it("updates the execution receipt when another transaction is selected", async () => {
    await renderLiveApp();
    expect(screen.getByRole("complementary", { name: "Execution receipt" }).textContent).toContain("Execution");

    fireEvent.click(screen.getByRole("button", { name: /01.*Deposit/i }));

    expect(screen.getByRole("complementary", { name: "Execution receipt" }).textContent).toContain("Deposit");
    expect(screen.getByRole("complementary", { name: "Execution receipt" }).textContent).toContain("0x245f…6d79");
  });

  it("keeps last verified evidence readable when Coston2 RPC fails", async () => {
    readContractMock.mockRejectedValue(new Error("RPC unavailable"));
    render(<App />);

    expect(await screen.findByText("RPC degraded")).toBeTruthy();
    expect(screen.getByText("Coston2 · evidence")).toBeTruthy();
    expect(screen.getByText(/Last verified evidence/i)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Retry live RPC" })).toBeTruthy();
    expect(document.querySelector(`a[href$="${transactionHashes[0]}"]`)).toBeTruthy();
  });

  it("discloses the exact Mode B boundary", async () => {
    await renderLiveApp();

    expect(screen.getAllByText(/Mode B/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/not (?:a )?hardware(?:-backed)? TEE/i).length).toBeGreaterThan(0);
  });

  it("uses the approved product language and canonical deployment addresses", async () => {
    await renderLiveApp();

    expect(screen.getByText("Private strategy.")).toBeTruthy();
    expect(screen.getByText("Public proof.")).toBeTruthy();
    for (const address of contractAddresses) {
      expect(screen.getByText(address)).toBeTruthy();
    }
  });
});
