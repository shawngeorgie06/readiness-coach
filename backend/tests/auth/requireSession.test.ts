import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { mintSession } from "../../src/auth/session.js";
import { requireSession } from "../../src/middleware/auth.js";

const SECRET = "z".repeat(32);
const API_TOKEN = "shared-token";

function app() {
  const instance = express();
  instance.use(express.json());
  instance.use(requireSession({ sessionSecret: SECRET, apiToken: API_TOKEN }));
  instance.get("/probe", (req, res) => res.json({ userId: req.userId ?? null }));
  return instance;
}

describe("requireSession", () => {
  it("401s without a bearer", async () => {
    await request(app()).get("/probe").expect(401, { error: "unauthorized" });
  });

  it("accepts a session JWT and sets req.userId", async () => {
    const token = await mintSession("user-9", SECRET);
    await request(app())
      .get("/probe")
      .set("Authorization", `Bearer ${token}`)
      .expect(200, { userId: "user-9" });
  });

  it("accepts the legacy shared token with a query userId", async () => {
    await request(app())
      .get("/probe?userId=legacy-7")
      .set("Authorization", `Bearer ${API_TOKEN}`)
      .expect(200, { userId: "legacy-7" });
  });

  it("accepts the legacy shared token with a body userId", async () => {
    const instance = express();
    instance.use(express.json());
    instance.use(requireSession({ sessionSecret: SECRET, apiToken: API_TOKEN }));
    instance.post("/probe", (req, res) => res.json({ userId: req.userId ?? null }));

    await request(instance)
      .post("/probe")
      .set("Authorization", `Bearer ${API_TOKEN}`)
      .send({ userId: "legacy-body" })
      .expect(200, { userId: "legacy-body" });
  });

  it("401s on an unknown bearer", async () => {
    await request(app()).get("/probe").set("Authorization", "Bearer nope").expect(401, { error: "unauthorized" });
  });
});
