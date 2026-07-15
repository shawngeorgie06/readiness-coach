import { describe, expect, it } from "vitest";
import { syncPayloadSchema } from "../../src/services/syncService.js";

describe("syncPayloadSchema", () => {
  it("accepts a minimal valid payload", () => {
    const parsed = syncPayloadSchema.parse({
      userId: "user_1",
      samples: [
        {
          hkUuid: "abc",
          type: "hrv_sdnn",
          startAt: "2026-07-09T08:00:00.000Z",
          endAt: "2026-07-09T08:00:00.000Z",
          value: 48,
          unit: "ms",
        },
      ],
      workouts: [],
    });

    expect(parsed.samples).toHaveLength(1);
  });

  it("rejects unknown sample types", () => {
    expect(() =>
      syncPayloadSchema.parse({
        userId: "user_1",
        samples: [
          {
            hkUuid: "x",
            type: "steps",
            startAt: "2026-07-09T08:00:00.000Z",
            endAt: "2026-07-09T08:00:00.000Z",
            value: 1,
          },
        ],
        workouts: [],
      })
    ).toThrow();
  });

  it("accepts workouts with sport keys so re-sync can refresh activity names", () => {
    const parsed = syncPayloadSchema.parse({
      userId: "user_1",
      samples: [],
      workouts: [
        {
          hkUuid: "w1",
          sport: "functional_strength",
          startAt: "2026-07-09T12:00:00.000Z",
          endAt: "2026-07-09T12:45:00.000Z",
          durationMin: 45,
          avgHrBpm: 120,
          calories: 300,
        },
      ],
    });
    expect(parsed.workouts[0]?.sport).toBe("functional_strength");
  });
});
