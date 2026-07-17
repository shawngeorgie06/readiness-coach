import { describe, expect, it } from "vitest";
import { loadEnv } from "../../src/env.js";

const base = {
  DATABASE_URL: "postgres://x",
  API_TOKEN: "token-1234",
  SESSION_SECRET: "a".repeat(32),
  APPLE_BUNDLE_ID: "com.example.app",
};

describe("loadEnv auth vars", () => {
  it("parses SESSION_SECRET and APPLE_BUNDLE_ID", () => {
    const env = loadEnv(base as NodeJS.ProcessEnv);
    expect(env.SESSION_SECRET).toBe("a".repeat(32));
    expect(env.APPLE_BUNDLE_ID).toBe("com.example.app");
  });

  it("rejects a short SESSION_SECRET", () => {
    expect(() => loadEnv({ ...base, SESSION_SECRET: "short" } as NodeJS.ProcessEnv)).toThrow(/Invalid env/);
  });
});
