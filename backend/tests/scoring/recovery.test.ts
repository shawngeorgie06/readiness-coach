import { describe, expect, it } from "vitest";
import { scoreRecovery } from "../../src/scoring/recovery.js";

describe("scoreRecovery", () => {
  it("scores high when HRV at/above baseline and RHR stable", () => {
    const result = scoreRecovery({
      hrvMs: 55,
      hrvBaseline30dMs: 50,
      restingHrBpm: 52,
      restingHrBaseline30dBpm: 54,
    });
    expect(result.score).toBeGreaterThanOrEqual(75);
  });

  it("scores low when HRV deeply suppressed and RHR elevated", () => {
    const result = scoreRecovery({
      hrvMs: 35,
      hrvBaseline30dMs: 50,
      restingHrBpm: 62,
      restingHrBaseline30dBpm: 54,
    });
    expect(result.score).toBeLessThanOrEqual(45);
    expect(result.drivers[0].text).toMatch(/^HRV \d+ms · below your normal$/);
    expect(result.drivers.some((d) => d.text.includes("Resting pulse"))).toBe(true);
  });
});
