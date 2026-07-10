import request from "supertest";
import { describe, expect, it, vi } from "vitest";
import { createApp } from "../src/app.js";

describe("createApp", () => {
  it("reports ready when the database probe succeeds", async () => {
    const app = createApp({
      apiToken: "test-api-token",
      checkDatabase: async () => 1,
    });

    await request(app).get("/health").expect(200, { ok: true });
  });

  it("reports unavailable without leaking the database error", async () => {
    const error = new Error("password=secret");
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    const app = createApp({
      apiToken: "test-api-token",
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
      apiToken: "test-api-token",
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

  it("allows a valid token to reach route validation", async () => {
    const app = createApp({
      apiToken: "test-api-token",
      checkDatabase: async () => 1,
    });

    await request(app)
      .get("/v1/today")
      .set("Authorization", "Bearer test-api-token")
      .expect(400, { error: "userId_required" });
  });
});
