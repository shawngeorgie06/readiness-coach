import request from "supertest";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createApp } from "../../src/app.js";
import { prisma } from "../../src/db.js";
import { resetTestDatabase } from "../helpers/testDatabase.js";

const TOKEN = process.env.API_TOKEN ?? "integration-test-token";
const authorization = `Bearer ${TOKEN}`;
const INTEGRATION_USER_ID = "integration-user";
const app = createApp({
  apiToken: TOKEN,
  apiTokenUserId: INTEGRATION_USER_ID,
  sessionSecret: "t".repeat(32),
});
const date = "2026-07-10";

const syncPayload = {
  userId: INTEGRATION_USER_ID,
  samples: [
    {
      hkUuid: "sleep-core",
      type: "sleep_analysis",
      startAt: "2026-07-09T22:00:00.000Z",
      endAt: "2026-07-10T02:00:00.000Z",
      metadata: { stage: "core" },
    },
    {
      hkUuid: "sleep-deep",
      type: "sleep_analysis",
      startAt: "2026-07-10T02:00:00.000Z",
      endAt: "2026-07-10T04:00:00.000Z",
      metadata: { stage: "deep" },
    },
    {
      hkUuid: "sleep-rem",
      type: "sleep_analysis",
      startAt: "2026-07-10T04:00:00.000Z",
      endAt: "2026-07-10T06:00:00.000Z",
      metadata: { stage: "rem" },
    },
    {
      hkUuid: "hrv-baseline",
      type: "hrv_sdnn",
      startAt: "2026-06-15T07:00:00.000Z",
      endAt: "2026-06-15T07:00:00.000Z",
      value: 50,
      unit: "ms",
    },
    {
      hkUuid: "hrv-current",
      type: "hrv_sdnn",
      startAt: "2026-07-10T07:00:00.000Z",
      endAt: "2026-07-10T07:00:00.000Z",
      value: 55,
      unit: "ms",
    },
    {
      hkUuid: "rhr-baseline",
      type: "resting_heart_rate",
      startAt: "2026-06-15T07:05:00.000Z",
      endAt: "2026-06-15T07:05:00.000Z",
      value: 54,
      unit: "count/min",
    },
    {
      hkUuid: "rhr-current",
      type: "resting_heart_rate",
      startAt: "2026-07-10T07:05:00.000Z",
      endAt: "2026-07-10T07:05:00.000Z",
      value: 53,
      unit: "count/min",
    },
  ],
  workouts: [],
};

beforeEach(async () => {
  await resetTestDatabase();
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe("backend API integration", () => {
  it("reports healthy with the real PostgreSQL connection", async () => {
    await request(app).get("/health").expect(200, { ok: true });
  });

  it("enforces bearer authentication", async () => {
    await request(app).get(`/v1/today?userId=integration-user&date=${date}`).expect(401);
    await request(app)
      .get(`/v1/today?userId=integration-user&date=${date}`)
      .set("Authorization", "Bearer invalid")
      .expect(401);
  });

  it("rejects invalid sync input", async () => {
    await request(app)
      .post("/v1/sync")
      .set("Authorization", authorization)
      .send({ userId: "", samples: [], workouts: [] })
      .expect(400);
  });

  it("returns 404 for an unknown user", async () => {
    await request(app)
      .get(`/v1/today?userId=unknown&date=${date}`)
      .set("Authorization", authorization)
      .expect(404, { error: "user_not_found" });
  });

  it("syncs idempotently and persists a Today score", async () => {
    const first = await request(app)
      .post("/v1/sync")
      .set("Authorization", authorization)
      .send(syncPayload)
      .expect(200);

    expect(first.body).toEqual({
      ok: true,
      samples: syncPayload.samples.length,
      workouts: 0,
    });

    const updatedPayload = {
      ...syncPayload,
      samples: syncPayload.samples.map((sample) =>
        sample.hkUuid === "hrv-current" ? { ...sample, value: 56 } : sample,
      ),
    };

    await request(app)
      .post("/v1/sync")
      .set("Authorization", authorization)
      .send(updatedPayload)
      .expect(200);

    expect(
      await prisma.healthSample.count({
        where: { userId: syncPayload.userId, hkUuid: "hrv-current" },
      }),
    ).toBe(1);
    expect(
      await prisma.healthSample.findUnique({
        where: {
          userId_hkUuid: {
            userId: syncPayload.userId,
            hkUuid: "hrv-current",
          },
        },
      }),
    ).toMatchObject({ value: 56 });

    const today = await request(app)
      .get(`/v1/today?userId=${syncPayload.userId}&date=${date}`)
      .set("Authorization", authorization)
      .expect(200);

    expect(today.body).toMatchObject({
      date,
      calibrating: false,
      confidence: "high",
      missing: [],
      pillars: {
        sleep: { score: expect.any(Number), drivers: expect.any(Array) },
        recovery: { score: expect.any(Number), drivers: expect.any(Array) },
        load: { score: expect.any(Number), drivers: expect.any(Array) },
      },
      advisor: {
        decision: expect.stringMatching(/^(push|maintain|recover)$/),
        source: "template",
      },
    });
    expect(today.body.readiness).toEqual(expect.any(Number));
    expect(today.body.decision).toMatch(/^(push|maintain|recover)$/);

    expect(
      await prisma.dailyScore.count({
        where: { userId: syncPayload.userId, date: new Date(`${date}T00:00:00.000Z`) },
      }),
    ).toBe(1);
  });

  it("returns 404 deleting an unknown user", async () => {
    await request(app)
      .delete("/v1/user?userId=unknown")
      .set("Authorization", authorization)
      .expect(404, { error: "user_not_found" });
  });

  it("deletes a user and all associated data", async () => {
    const payloadWithWorkout = {
      ...syncPayload,
      workouts: [
        {
          hkUuid: "run-1",
          sport: "running",
          startAt: "2026-07-10T12:00:00.000Z",
          endAt: "2026-07-10T12:30:00.000Z",
          durationMin: 30,
          avgHrBpm: 150,
          calories: 300,
        },
      ],
    };

    await request(app)
      .post("/v1/sync")
      .set("Authorization", authorization)
      .send(payloadWithWorkout)
      .expect(200);
    await request(app)
      .get(`/v1/today?userId=${syncPayload.userId}&date=${date}`)
      .set("Authorization", authorization)
      .expect(200);

    expect(
      await prisma.workout.count({ where: { userId: syncPayload.userId } }),
    ).toBe(1);
    expect(
      await prisma.advisorNote.count({ where: { userId: syncPayload.userId } }),
    ).toBe(1);

    await request(app)
      .delete(`/v1/user?userId=${syncPayload.userId}`)
      .set("Authorization", authorization)
      .expect(200, { ok: true });

    expect(await prisma.user.findUnique({ where: { id: syncPayload.userId } })).toBeNull();
    expect(
      await prisma.healthSample.count({ where: { userId: syncPayload.userId } }),
    ).toBe(0);
    expect(
      await prisma.dailyScore.count({ where: { userId: syncPayload.userId } }),
    ).toBe(0);
    expect(
      await prisma.workout.count({ where: { userId: syncPayload.userId } }),
    ).toBe(0);
    expect(
      await prisma.advisorNote.count({ where: { userId: syncPayload.userId } }),
    ).toBe(0);

    await request(app)
      .delete(`/v1/user?userId=${syncPayload.userId}`)
      .set("Authorization", authorization)
      .expect(404, { error: "user_not_found" });
  });
});
