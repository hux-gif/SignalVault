// @vitest-environment node

import type { UserConfig } from "vite";
import { describe, expect, it } from "vitest";
import viteConfig from "../vite.config";

describe("GitHub Pages build configuration", () => {
  it("keeps the repository base path pinned", () => {
    expect((viteConfig as UserConfig).base).toBe("/SignalVault/");
  });
});
