import { describe, expect, it } from "vitest";
import { mintSession, verifySession } from "../../src/auth/session.js";

const secret = "s".repeat(32);

describe("session tokens", () => {
  it("round-trips the userId", async () => {
    const token = await mintSession("user-123", secret);
    expect(await verifySession(token, secret)).toBe("user-123");
  });

  it("rejects a token signed with a different secret", async () => {
    const token = await mintSession("user-123", secret);
    expect(await verifySession(token, "d".repeat(32))).toBeNull();
  });

  it("rejects an expired token", async () => {
    const token = await mintSession("user-123", secret, "0s");
    // allow the exp claim (whole-second granularity) to pass
    await new Promise((r) => setTimeout(r, 1100));
    expect(await verifySession(token, secret)).toBeNull();
  });

  it("returns null for garbage", async () => {
    expect(await verifySession("not-a-jwt", secret)).toBeNull();
  });
});
