import { createServer as createNodeServer, type IncomingMessage, type ServerResponse } from "node:http";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import type { Address, Hex } from "viem";
import { loadConfig } from "./config.js";
import { createAllocationService, RequestValidationError, type AllocationService } from "./service.js";
import type { AllocateInput } from "./types.js";

const UINT256_MAX = (1n << 256n) - 1n;

class PayloadTooLargeError extends RequestValidationError {}

async function readJson(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk);
    size += buffer.length;
    if (size > 64 * 1024) throw new PayloadTooLargeError("request body too large");
    chunks.push(buffer);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch (error) {
    if (error instanceof SyntaxError) throw new RequestValidationError("malformed JSON");
    throw error;
  }
}

function bigint(value: unknown, name: string): bigint {
  if (typeof value === "number" && (!Number.isSafeInteger(value) || value < 0)) {
    throw new RequestValidationError(`${name} JSON numbers must be safe unsigned integers; use a decimal string for larger values`);
  }
  if ((typeof value !== "string" && typeof value !== "number") || !/^\d+$/.test(String(value))) {
    throw new RequestValidationError(`${name} must be an unsigned integer`);
  }
  const parsed = BigInt(value);
  if (parsed > UINT256_MAX) throw new RequestValidationError(`${name} exceeds uint256`);
  return parsed;
}

function normalize(value: unknown): AllocateInput {
  if (!value || typeof value !== "object") throw new RequestValidationError("request body must be an object");
  const input = value as Record<string, any>;
  if (!input.plainIntent || !input.ftso) throw new RequestValidationError("plainIntent and ftso are required");
  return {
    user: input.user as Address, vault: input.vault as Address, intentVerifier: input.intentVerifier as Address,
    chainId: bigint(input.chainId, "chainId"), nonce: bigint(input.nonce, "nonce"), intentCommitment: input.intentCommitment as Hex,
    plainIntent: { ...input.plainIntent, riskLevel: Number(input.plainIntent.riskLevel), targetAprBps: Number(input.plainIntent.targetAprBps), maxDrawdownBps: Number(input.plainIntent.maxDrawdownBps), rebalanceWindow: Number(input.plainIntent.rebalanceWindow) },
    ftso: { price: bigint(input.ftso.price, "ftso.price"), timestamp: bigint(input.ftso.timestamp, "ftso.timestamp") },
  };
}

function send(response: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}): void {
  response.writeHead(status, { "content-type": "application/json", ...headers });
  response.end(JSON.stringify(body, (_, value) => typeof value === "bigint" ? value.toString() : value));
}

export function createServer(service: AllocationService) {
  return createNodeServer(async (request, response) => {
    if (request.url !== "/allocate") return send(response, 404, { error: "not found" });
    if (request.method !== "POST") return send(response, 405, { error: "method not allowed" }, { Allow: "POST" });
    try {
      const output = await service(normalize(await readJson(request)));
      return send(response, 200, { result: output.result, signature: output.signature });
    } catch (error) {
      if (error instanceof PayloadTooLargeError) return send(response, 413, { error: error.message });
      if (error instanceof RequestValidationError) {
        return send(response, 400, { error: error instanceof Error ? error.message : "invalid request" });
      }
      return send(response, 500, { error: "internal server error" });
    }
  });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const port = Number(process.env.PORT ?? "8787");
  if (!Number.isInteger(port) || port < 1 || port > 65_535) throw new Error("PORT must be between 1 and 65535");
  createServer(createAllocationService(loadConfig())).listen(port, "127.0.0.1", () => {
    console.info(`Local simulated TEE / local-signer demo mode listening on http://127.0.0.1:${port}`);
  });
}
