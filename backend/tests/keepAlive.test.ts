import { describe, expect, it, vi } from "vitest";
import { resolveKeepAliveUrl, startKeepAlive } from "../src/keepAlive.js";

describe("resolveKeepAliveUrl", () => {
  it("prefers KEEP_ALIVE_URL", () => {
    expect(
      resolveKeepAliveUrl({
        KEEP_ALIVE_URL: "https://example.com/health",
        RENDER_EXTERNAL_URL: "https://ignored.onrender.com",
      }),
    ).toBe("https://example.com/health");
  });

  it("builds from RENDER_EXTERNAL_URL", () => {
    expect(
      resolveKeepAliveUrl({
        RENDER_EXTERNAL_URL: "https://app.onrender.com/",
      }),
    ).toBe("https://app.onrender.com/health");
  });

  it("returns undefined when unset", () => {
    expect(resolveKeepAliveUrl({})).toBeUndefined();
  });
});

describe("startKeepAlive", () => {
  it("pings on an interval and stops cleanly", async () => {
    vi.useFakeTimers();
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true });
    const handle = startKeepAlive({
      url: "https://app.onrender.com/health",
      intervalMs: 60_000,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      log: () => {},
      logError: () => {},
    });

    await vi.advanceTimersByTimeAsync(30_000);
    expect(fetchImpl).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(60_000);
    expect(fetchImpl).toHaveBeenCalledTimes(2);

    handle.stop();
    await vi.advanceTimersByTimeAsync(120_000);
    expect(fetchImpl).toHaveBeenCalledTimes(2);

    vi.useRealTimers();
  });
});
