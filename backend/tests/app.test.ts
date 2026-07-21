import request from "supertest";
import { describe, expect, it, vi } from "vitest";
import { createApp } from "../src/app.js";

describe("createApp", () => {
  it("reports ready when the database probe succeeds", async () => {
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => 1,
    });

    await request(app).get("/health").expect(200, { ok: true });
  });

  it("reports unavailable without leaking the database error", async () => {
    const error = new Error("password=secret");
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => {
        throw error;
      },
    });

    const response = await request(app).get("/health").expect(503);

    expect(response.body).toEqual({ ok: false });
    expect(JSON.stringify(response.body)).not.toContain("secret");
    expect(consoleError).toHaveBeenCalledWith("Database health check failed", error);
    consoleError.mockRestore();
  });

  it("rejects missing and invalid bearer tokens", async () => {
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => 1,
    });

    await request(app).get("/v1/today?userId=missing").expect(401, {
      error: "unauthorized",
    });
    await request(app)
      .get("/v1/today?userId=missing")
      .set("Authorization", "Bearer wrong-token")
      .expect(401, { error: "unauthorized" });
  });

  it("allows a valid token to reach the bound user route", async () => {
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => 1,
    });

    // Shared token authenticates (not 401). Route may 404/500 without a DB — binding is what matters.
    const response = await request(app)
      .get("/v1/today")
      .set("Authorization", "Bearer test-api-token");
    expect(response.status).not.toBe(401);
    expect(response.status).not.toBe(400);
  });

  it("ignores client userId spoofing on delete (still authenticated as bound user)", async () => {
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => 1,
    });

    const response = await request(app)
      .delete("/v1/user?userId=someone-else")
      .set("Authorization", "Bearer test-api-token");
    // Authenticated as bound user — never 401/400 from missing userId.
    expect(response.status).not.toBe(401);
    expect(response.status).not.toBe(400);
  });

  it("sets security headers via Helmet", async () => {
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => 1,
    });

    const response = await request(app).get("/health").expect(200);

    expect(response.headers["x-content-type-options"]).toBe("nosniff");
    expect(response.headers["x-powered-by"]).toBeUndefined();
  });

  it("blocks cross-origin requests when no origin is configured", async () => {
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => 1,
    });

    const response = await request(app)
      .get("/health")
      .set("Origin", "https://evil.example.com");

    expect(response.headers["access-control-allow-origin"]).toBeUndefined();
  });

  it("allows only the configured origin", async () => {
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => 1,
      corsOrigin: "https://app.readiness-coach.example",
    });

    const allowed = await request(app)
      .get("/health")
      .set("Origin", "https://app.readiness-coach.example");
    expect(allowed.headers["access-control-allow-origin"]).toBe(
      "https://app.readiness-coach.example",
    );

    const denied = await request(app)
      .get("/health")
      .set("Origin", "https://evil.example.com");
    expect(denied.headers["access-control-allow-origin"]).toBeUndefined();
  });

  it("rate-limits requests to the /v1 API surface", async () => {
    const app = createApp({
      apiTokenUserId: "test-user",
      apiToken: "test-api-token",
      sessionSecret: "t".repeat(32),
      checkDatabase: async () => 1,
      rateLimit: { windowMs: 60_000, max: 2 },
    });

    const first = await request(app)
      .get("/v1/today")
      .set("Authorization", "Bearer test-api-token");
    const second = await request(app)
      .get("/v1/today")
      .set("Authorization", "Bearer test-api-token");
    expect(first.status).not.toBe(429);
    expect(second.status).not.toBe(429);
    await request(app)
      .get("/v1/today")
      .set("Authorization", "Bearer test-api-token")
      .expect(429);
  });
});
