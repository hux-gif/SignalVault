import { describe, expect, it } from "vitest";

describe("frontend contract ABI initialization", () => {
  it("imports all deployed contract ABI definitions without throwing", async () => {
    await expect(import("../src/lib/viem")).resolves.toBeDefined();
  });
});
