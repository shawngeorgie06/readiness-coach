import { describe, expect, it } from "vitest";
import { estimateWorkoutStrain } from "../../src/scoring/strain.js";

describe("estimateWorkoutStrain", () => {
  it("returns 0 for empty workout", () => {
    expect(
      estimateWorkoutStrain({
        durationMin: 0,
        avgHrBpm: 0,
        restingHrBpm: 55,
        maxHrBpm: 190,
      })
    ).toBe(0);
  });

  it("increases with duration and intensity", () => {
    const easy = estimateWorkoutStrain({
      durationMin: 30,
      avgHrBpm: 110,
      restingHrBpm: 55,
      maxHrBpm: 190,
    });
    const hard = estimateWorkoutStrain({
      durationMin: 60,
      avgHrBpm: 160,
      restingHrBpm: 55,
      maxHrBpm: 190,
    });
    expect(hard).toBeGreaterThan(easy);
  });
});
