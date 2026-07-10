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
});
