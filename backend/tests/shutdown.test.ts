import { describe, expect, it, vi } from "vitest";
import { createGracefulShutdown } from "../src/shutdown.js";

describe("createGracefulShutdown", () => {
  it("closes HTTP before disconnecting Prisma and runs only once", async () => {
    const events: string[] = [];
    const closeServer = vi.fn(async () => {
      events.push("http");
    });
    const disconnectDatabase = vi.fn(async () => {
      events.push("database");
    });
    const shutdown = createGracefulShutdown({
      closeServer,
      disconnectDatabase,
      onError: vi.fn(),
    });

    await Promise.all([shutdown(), shutdown()]);

    expect(events).toEqual(["http", "database"]);
    expect(closeServer).toHaveBeenCalledTimes(1);
    expect(disconnectDatabase).toHaveBeenCalledTimes(1);
  });

  it("reports and rethrows shutdown failures", async () => {
    const error = new Error("close failed");
    const onError = vi.fn();
    const shutdown = createGracefulShutdown({
      closeServer: vi.fn().mockRejectedValue(error),
      disconnectDatabase: vi.fn(),
      onError,
    });

    await expect(shutdown()).rejects.toThrow("close failed");
    expect(onError).toHaveBeenCalledWith(error);
  });
});
