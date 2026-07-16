import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { getBlockMock, readContractMock } = vi.hoisted(() => ({
  getBlockMock: vi.fn(),
  readContractMock: vi.fn(),
}));

vi.mock("../src/lib/viem", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../src/lib/viem")>()),
  publicClient: {
    getBlock: getBlockMock,
    readContract: readContractMock,
  },
}));

import App from "../src/App";

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

function mockLiveRpc() {
  readContractMock.mockImplementation(({ functionName }: { functionName: string }) => {
    const values: Record<string, unknown> = {
      allocation: { idleBps: 5_000, upshiftBps: 5_000 },
      availableLiquidity: 3_990_000n,
      grossAssets: 4_002_499n,
      totalAssets: 3_990_000n,
      userIntentNonce: 1n,
    };
    return Promise.resolve(values[functionName]);
  });
  getBlockMock.mockResolvedValue({ timestamp: BigInt(Math.floor(Date.now() / 1_000)) });
}

async function renderLiveApp() {
  render(<App />);
  await screen.findByText("Coston2 RPC live");
}

describe("SignalVault live evidence experience", () => {
  beforeEach(() => {
    mockLiveRpc();
    delete window.ethereum;
  });

  afterEach(() => {
    cleanup();
    vi.clearAllMocks();
  });

  it("explains the product and identifies the live Coston2 network", async () => {
    await renderLiveApp();

    expect(screen.getByText("Private intent.")).toBeTruthy();
    expect(screen.getByText("Verifiable FXRP execution.")).toBeTruthy();
    expect(screen.getByText("Live on Coston2")).toBeTruthy();
  });

  it("shows every canonical V2 deployment address", async () => {
    await renderLiveApp();

    for (const address of contractAddresses) {
      expect(screen.getAllByText(address).length).toBeGreaterThan(0);
    }
  });

  it("links all four canonical Coston2 evidence transactions", async () => {
    await renderLiveApp();

    for (const hash of transactionHashes) {
      expect(document.querySelector(`a[href$="${hash}"]`)).toBeTruthy();
    }
  });

  it("discloses that Mode B is not a hardware-backed TEE", async () => {
    await renderLiveApp();

    expect(screen.getAllByText(/Mode B/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/not hardware(?:-backed)? TEE/i).length).toBeGreaterThan(0);
  });

  it("labels the historical FTSO input as recorded evidence, not live RPC data", async () => {
    await renderLiveApp();

    const ftsoMetric = screen.getByText("FTSO input age").closest("article");
    expect(ftsoMetric?.textContent).toContain("RECORDED E2E");
    expect(ftsoMetric?.textContent).not.toContain("LIVE");
  });

  it("keeps each execution step exposed as an interactive button", async () => {
    await renderLiveApp();

    expect(screen.getByRole("button", { name: /Private Intent/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /Mode B Signed Result/i })).toBeTruthy();
  });

  it("keeps verified evidence visible when live RPC calls fail", async () => {
    readContractMock.mockRejectedValue(new Error("RPC unavailable"));
    getBlockMock.mockRejectedValue(new Error("RPC unavailable"));

    render(<App />);

    expect(await screen.findByText("RPC degraded")).toBeTruthy();
    expect(screen.getByText(/Last verified evidence/i)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Retry live RPC" })).toBeTruthy();
    expect(document.querySelector(`a[href$="${transactionHashes[0]}"]`)).toBeTruthy();
  });

  it("warns instead of connecting when the wallet remains off chain 114", async () => {
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_chainId") return "0x1";
      if (method === "wallet_switchEthereumChain") return null;
      if (method === "eth_requestAccounts") return ["0x1111111111111111111111111111111111111111"];
      return null;
    });
    window.ethereum = { request };

    await renderLiveApp();
    fireEvent.click(screen.getByRole("button", { name: "Connect Wallet" }));

    await waitFor(() => {
      expect(screen.getByText(/Switch to Coston2.*114/i)).toBeTruthy();
    });
    expect(request).not.toHaveBeenCalledWith({ method: "eth_requestAccounts" });
  });

  it("adds Coston2 when a first-time wallet does not know chain 114", async () => {
    let chainId = "0x1";
    let switchAttempts = 0;
    const request = vi.fn(async ({ method }: { method: string; params?: unknown[] }) => {
      if (method === "eth_chainId") return chainId;
      if (method === "wallet_switchEthereumChain") {
        switchAttempts += 1;
        if (switchAttempts === 1) throw Object.assign(new Error("unknown chain"), { code: 4_902 });
        chainId = "0x72";
        return null;
      }
      if (method === "wallet_addEthereumChain") return null;
      if (method === "eth_requestAccounts") return ["0x1111111111111111111111111111111111111111"];
      return null;
    });
    window.ethereum = { request };

    await renderLiveApp();
    fireEvent.click(screen.getByRole("button", { name: "Connect Wallet" }));

    expect(await screen.findByText(/Connected to Flare Coston2/i)).toBeTruthy();
    expect(request).toHaveBeenCalledWith(expect.objectContaining({ method: "wallet_addEthereumChain" }));
    expect(switchAttempts).toBe(2);
  });

  it("reacts when the connected wallet changes away from Coston2", async () => {
    const listeners: Record<string, (value: unknown) => void> = {};
    const request = vi.fn(async ({ method }: { method: string }) => {
      if (method === "eth_chainId") return "0x72";
      if (method === "eth_requestAccounts") return ["0x1111111111111111111111111111111111111111"];
      return null;
    });
    window.ethereum = {
      request,
      on: vi.fn((event: string, listener: (value: unknown) => void) => { listeners[event] = listener; }),
      removeListener: vi.fn(),
    };

    await renderLiveApp();
    fireEvent.click(screen.getByRole("button", { name: "Connect Wallet" }));
    expect(await screen.findByText(/Connected to Flare Coston2/i)).toBeTruthy();

    act(() => listeners.chainChanged("0x1"));

    expect(screen.getByText(/Switch to Coston2.*114/i)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Connect Wallet" })).toBeTruthy();
  });

});
