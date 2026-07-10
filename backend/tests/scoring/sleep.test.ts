import { describe, expect, it } from "vitest";
import { scoreSleep } from "../../src/scoring/sleep.js";

describe("scoreSleep", () => {
  it("scores high when duration meets need with low debt", () => {
    const result = scoreSleep({
      durationHours: 8,
      needHours: 8,
      restorativeHours: 3.2,
      sleepDebtHours: 0.2,
      consistencyStdHours: 0.4,
    });
    expect(result.score).toBeGreaterThanOrEqual(80);
  });

  it("scores low when short sleep and high debt", () => {
    const result = scoreSleep({
      durationHours: 4.5,
      needHours: 8,
      restorativeHours: 1.0,
      sleepDebtHours: 4,
      consistencyStdHours: 1.5,
    });
    expect(result.score).toBeLessThanOrEqual(40);
  });

  it("clamps score to 0-100", () => {
    const result = scoreSleep({
      durationHours: 0,
      needHours: 8,
      restorativeHours: 0,
      sleepDebtHours: 20,
      consistencyStdHours: 5,
    });
    expect(result.score).toBeGreaterThanOrEqual(0);
    expect(result.score).toBeLessThanOrEqual(100);
  });
});
