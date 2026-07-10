import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("fetchToday", () => {
  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("throws a configuration error when env vars are missing", async () => {
    vi.stubEnv("VITE_API_URL", "");
    vi.stubEnv("VITE_API_TOKEN", "");
    vi.stubEnv("VITE_USER_ID", "");

    const { fetchToday } = await import("../src/api");

    await expect(fetchToday()).rejects.toThrow(/Missing dashboard configuration/);
  });

  it("fetches today's data with the configured auth header", async () => {
    vi.stubEnv("VITE_API_URL", "http://localhost:4000");
    vi.stubEnv("VITE_API_TOKEN", "token-123");
    vi.stubEnv("VITE_USER_ID", "user-1");

    const mockToday = {
      date: "2026-07-10",
      readiness: 82,
      decision: "push",
      calibrating: false,
      pillars: {
        sleep: { score: 90, drivers: [] },
        recovery: { score: 78, drivers: [] },
        load: { score: 70, drivers: [] },
      },
      overridesApplied: [],
      confidence: "high",
      missing: [],
      advisor: { decision: "push", why: [], prescription: "", ifIgnored: "", source: "template" },
    };
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => mockToday,
    });
    vi.stubGlobal("fetch", fetchMock);

    const { fetchToday } = await import("../src/api");
    const result = await fetchToday();

    expect(result).toEqual(mockToday);
    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:4000/v1/today?userId=user-1",
      expect.objectContaining({ headers: { Authorization: "Bearer token-123" } }),
    );
  });

  it("throws a descriptive error on a non-ok response", async () => {
    vi.stubEnv("VITE_API_URL", "http://localhost:4000");
    vi.stubEnv("VITE_API_TOKEN", "token-123");
    vi.stubEnv("VITE_USER_ID", "user-1");
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 404,
        json: async () => ({ error: "user_not_found" }),
      }),
    );

    const { fetchToday } = await import("../src/api");

    await expect(fetchToday()).rejects.toThrow("Today request failed: user_not_found");
  });
});
