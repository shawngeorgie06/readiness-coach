import express from "express";
import request from "supertest";
import { expect, it } from "vitest";
import { createRequestTimer } from "../../src/middleware/timing.js";

it("logs method, path without query, status and whole ms", async () => {
  const lines: string[] = [];
  let t = 1000;
  const app = express();
  app.use(createRequestTimer((l) => lines.push(l), () => (t += 12.4)));
  app.get("/v1/today", (_q, r) => r.json({ ok: true }));
  await request(app).get("/v1/today?userId=secret-user&tz=-240");
  expect(lines).toEqual(["GET /v1/today 200 12ms"]);
  expect(lines.join()).not.toContain("secret-user");
});
