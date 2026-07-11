import { afterEach, describe, expect, it, vi } from "vitest";
import type { Address, Hex } from "viem";
import { createServer } from "../src/server.js";

let server: ReturnType<typeof createServer> | undefined;
afterEach(() => server?.close());

describe("POST /allocate", () => {
  it("returns exactly result and signature without secrets or plaintext intent", async () => {
    const service = vi.fn(async () => ({ result: { user: "0x3000000000000000000000000000000000000003" as Address }, signature: "0x1234" as Hex }));
    server = createServer(service as never);
    await new Promise<void>((resolve) => server!.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("missing address");
    const request = {
      user: "0x3000000000000000000000000000000000000003",
      vault: "0x1000000000000000000000000000000000000001",
      intentVerifier: "0x2000000000000000000000000000000000000002",
      chainId: "31337", nonce: "1", intentCommitment: `0x${"44".repeat(32)}`,
      plainIntent: { riskLevel: 1, targetAprBps: 800, maxDrawdownBps: 250, rebalanceWindow: 3600, salt: `0x${"55".repeat(32)}` },
      ftso: { price: "100000", timestamp: "1000" },
    };
    const response = await fetch(`http://127.0.0.1:${address.port}/allocate`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(request) });
    const body = await response.json();
    expect(Object.keys(body)).toEqual(["result", "signature"]);
    expect(JSON.stringify(body)).not.toContain("privateKey");
    expect(JSON.stringify(body)).not.toContain("plainIntent");
    expect(JSON.stringify(body)).not.toContain(request.plainIntent.salt);
  });
});
