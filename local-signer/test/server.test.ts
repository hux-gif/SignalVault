import { afterEach, describe, expect, it, vi } from "vitest";
import type { Address, Hex } from "viem";
import { createServer } from "../src/server.js";
import { RequestValidationError } from "../src/service.js";

let server: ReturnType<typeof createServer> | undefined;
afterEach(() => server?.close());

describe("POST /allocate", () => {
  const request = {
    user: "0x3000000000000000000000000000000000000003",
    vault: "0x1000000000000000000000000000000000000001",
    intentVerifier: "0x2000000000000000000000000000000000000002",
    chainId: "31337", nonce: "1", intentCommitment: `0x${"44".repeat(32)}`,
    plainIntent: { riskLevel: 1, targetAprBps: 800, maxDrawdownBps: 250, rebalanceWindow: 3600, salt: `0x${"55".repeat(32)}` },
    ftso: { price: "100000", timestamp: "1000" },
  };

  async function start(service: Parameters<typeof createServer>[0]) {
    server = createServer(service);
    await new Promise<void>((resolve) => server!.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("missing address");
    return `http://127.0.0.1:${address.port}`;
  }

  it("returns exactly result and signature without secrets or plaintext intent", async () => {
    const service = vi.fn(async () => ({ result: { user: "0x3000000000000000000000000000000000000003" as Address }, signature: "0x1234" as Hex }));
    const url = await start(service as never);
    const response = await fetch(`${url}/allocate`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(request) });
    const body = await response.json();
    expect(Object.keys(body)).toEqual(["result", "signature"]);
    expect(JSON.stringify(body)).not.toContain("privateKey");
    expect(JSON.stringify(body)).not.toContain("plainIntent");
    expect(JSON.stringify(body)).not.toContain(request.plainIntent.salt);
  });

  it("rejects unsafe JSON numbers instead of accepting rounded uint256 values", async () => {
    const service = vi.fn();
    const url = await start(service as never);
    const response = await fetch(`${url}/allocate`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ...request, nonce: Number.MAX_SAFE_INTEGER + 1 }) });
    expect(response.status).toBe(400);
    const overflow = await fetch(`${url}/allocate`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ...request, nonce: (1n << 256n).toString() }) });
    expect(overflow.status).toBe(400);
    expect(service).not.toHaveBeenCalled();
  });

  it("returns 400 for malformed JSON and request validation errors", async () => {
    const service = vi.fn(async () => { throw new RequestValidationError("bad nonce"); });
    const url = await start(service as never);
    expect((await fetch(`${url}/allocate`, { method: "POST", body: "{" })).status).toBe(400);
    const response = await fetch(`${url}/allocate`, { method: "POST", body: JSON.stringify(request) });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "bad nonce" });
  });

  it("returns 413 for an oversized JSON body", async () => {
    const url = await start(vi.fn() as never);
    const response = await fetch(`${url}/allocate`, { method: "POST", body: JSON.stringify({ padding: "x".repeat(70_000) }) });
    expect(response.status).toBe(413);
  });

  it("uses 404 for unknown routes and 405 with Allow for unsupported allocate methods", async () => {
    const url = await start(vi.fn() as never);
    expect((await fetch(`${url}/missing`)).status).toBe(404);
    const response = await fetch(`${url}/allocate`);
    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("POST");
  });

  it("sanitizes unexpected internal failures as a generic 500", async () => {
    const url = await start((async () => { throw new Error("SIGNER_PRIVATE_KEY=secret"); }) as never);
    const response = await fetch(`${url}/allocate`, { method: "POST", body: JSON.stringify(request) });
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "internal server error" });
  });
});
