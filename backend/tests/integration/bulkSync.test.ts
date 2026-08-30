import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/db.js";
import { applySync } from "../../src/services/syncService.js";
import { resetTestDatabase } from "../helpers/testDatabase.js";

const USER_ID = "bulk-user";
const DEFAULTS = { restingHrBpm: 55, maxHrBpm: 190 };
const SAMPLE_COUNT = 3_000;

/** A day of dense Watch heart-rate data, the shape a backfill chunk actually has. */
function buildSamples(count: number, valueOffset = 0) {
  const base = Date.parse("2026-07-01T00:00:00.000Z");
  return Array.from({ length: count }, (_, index) => {
    const at = new Date(base + index * 1_000).toISOString();
    return {
      hkUuid: `hr-${index}`,
      type: "heart_rate" as const,
      startAt: at,
      endAt: at,
      value: 60 + (index % 40) + valueOffset,
      unit: "count/min",
      metadata: { source: "watch", index },
    };
  });
}

function buildWorkouts(count: number, durationOffset = 0) {
  const base = Date.parse("2026-07-01T12:00:00.000Z");
  return Array.from({ length: count }, (_, index) => ({
    hkUuid: `workout-${index}`,
    sport: "running",
    startAt: new Date(base + index * 3_600_000).toISOString(),
    endAt: new Date(base + index * 3_600_000 + 1_800_000).toISOString(),
    durationMin: 30 + durationOffset,
    avgHrBpm: 150,
    calories: 300,
  }));
}

beforeEach(async () => {
  await resetTestDatabase();
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe("applySync at backfill volume", () => {
  it("inserts a large batch, then re-applies it without duplicating rows", async () => {
    const first = await applySync(
      {
        userId: USER_ID,
        samples: buildSamples(SAMPLE_COUNT),
        workouts: buildWorkouts(20),
      },
      DEFAULTS,
    );

    expect(first).toEqual({ ok: true, samples: SAMPLE_COUNT, workouts: 20 });
    expect(await prisma.healthSample.count({ where: { userId: USER_ID } })).toBe(
      SAMPLE_COUNT,
    );
    expect(await prisma.workout.count({ where: { userId: USER_ID } })).toBe(20);

    // The same UUIDs with changed values: an upsert, not a second insert.
    await applySync(
      {
        userId: USER_ID,
        samples: buildSamples(SAMPLE_COUNT, 5),
        workouts: buildWorkouts(20, 15),
      },
      DEFAULTS,
    );

    expect(await prisma.healthSample.count({ where: { userId: USER_ID } })).toBe(
      SAMPLE_COUNT,
    );
    expect(await prisma.workout.count({ where: { userId: USER_ID } })).toBe(20);

    const updated = await prisma.healthSample.findUnique({
      where: { userId_hkUuid: { userId: USER_ID, hkUuid: "hr-7" } },
    });
    expect(updated?.value).toBe(60 + 7 + 5);
    expect(updated?.metadata).toEqual({ source: "watch", index: 7 });

    const workout = await prisma.workout.findUnique({
      where: { userId_hkUuid: { userId: USER_ID, hkUuid: "workout-3" } },
    });
    expect(workout?.durationMin).toBe(45);
    // Strain is recomputed from the new duration rather than left stale.
    expect(workout?.strain).toBeGreaterThan(0);
  });

  it("preserves timestamps, nulls and absent metadata exactly", async () => {
    await applySync(
      {
        userId: USER_ID,
        samples: [
          {
            hkUuid: "sleep-core",
            type: "sleep_analysis",
            startAt: "2026-07-09T22:00:00.000Z",
            endAt: "2026-07-10T02:30:45.123Z",
            metadata: { stage: "core" },
          },
          {
            hkUuid: "hrv-no-unit",
            type: "hrv_sdnn",
            startAt: "2026-07-09T07:00:00.000Z",
            endAt: "2026-07-09T07:00:00.000Z",
            value: 48,
          },
        ],
        workouts: [],
      },
      DEFAULTS,
    );

    const sleep = await prisma.healthSample.findUnique({
      where: { userId_hkUuid: { userId: USER_ID, hkUuid: "sleep-core" } },
    });
    expect(sleep?.startAt.toISOString()).toBe("2026-07-09T22:00:00.000Z");
    expect(sleep?.endAt.toISOString()).toBe("2026-07-10T02:30:45.123Z");
    expect(sleep?.value).toBeNull();
    expect(sleep?.unit).toBeNull();

    const hrv = await prisma.healthSample.findUnique({
      where: { userId_hkUuid: { userId: USER_ID, hkUuid: "hrv-no-unit" } },
    });
    expect(hrv?.metadata).toBeNull();
    expect(hrv?.unit).toBeNull();
  });

  it("creates the user row when a sync arrives before any other write", async () => {
    await applySync(
      { userId: "brand-new-user", samples: buildSamples(3), workouts: [] },
      DEFAULTS,
    );

    expect(
      await prisma.user.findUnique({ where: { id: "brand-new-user" } }),
    ).not.toBeNull();
  });
});
