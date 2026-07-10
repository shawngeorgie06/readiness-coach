import { describe, expect, it } from "vitest";
import { computeReadiness } from "../../src/scoring/readiness.js";

const healthy = {
  sleep: {
    durationHours: 8,
    needHours: 8,
    restorativeHours: 3,
    sleepDebtHours: 0.3,
    consistencyStdHours: 0.4,
  },
  recovery: {
    hrvMs: 52,
    hrvBaseline30dMs: 50,
    restingHrBpm: 54,
    restingHrBaseline30dBpm: 54,
  },
  load: {
    yesterdayStrain: 8,
    strain7dAvg: 9,
    acuteChronicRatio: 1.05,
  },
  meta: {
    daysOfHistory: 30,
    consecutiveHighStrainDays: 0,
  },
};

describe("computeReadiness", () => {
  it("returns push for a strong day", () => {
    const result = computeReadiness(healthy);

    expect(result.readiness).toBeGreaterThanOrEqual(75);
    expect(result.decision).toBe("push");
    expect(result.calibrating).toBe(false);
  });

  it("uses the push, maintain, and recover score bands", () => {
    const maintain = computeReadiness({
      ...healthy,
      recovery: { ...healthy.recovery, hrvMs: 48, restingHrBpm: 55 },
    });
    const recover = computeReadiness({
      ...healthy,
      sleep: {
        ...healthy.sleep,
        durationHours: 5,
        restorativeHours: 0.5,
        sleepDebtHours: 6,
        consistencyStdHours: 2,
      },
      recovery: { ...healthy.recovery, hrvMs: 41, restingHrBpm: 63 },
      load: {
        yesterdayStrain: 18,
        strain7dAvg: 10,
        acuteChronicRatio: 1.6,
      },
    });

    expect(maintain.readiness).toBeGreaterThanOrEqual(50);
    expect(maintain.readiness).toBeLessThan(75);
    expect(maintain.decision).toBe("maintain");
    expect(recover.readiness).toBeLessThan(50);
    expect(recover.decision).toBe("recover");
    expect(recover.overridesApplied).toHaveLength(0);
  });

  it("uses recomp weights of 0.35/0.40/0.25", () => {
    const result = computeReadiness(healthy);
    const expected = Math.round(
      result.sleep.score * 0.35 +
        result.recovery.score * 0.4 +
        result.load.score * 0.25,
    );

    expect(result.readiness).toBe(expected);
  });

  it("forces recover when sleep is under 5h", () => {
    const result = computeReadiness({
      ...healthy,
      sleep: { ...healthy.sleep, durationHours: 4.5, sleepDebtHours: 3 },
    });

    expect(result.decision).toBe("recover");
    expect(result.overridesApplied).toContain("sleep_under_5h");
  });

  it("forces recover when HRV is down at least 20% and RHR is elevated", () => {
    const result = computeReadiness({
      ...healthy,
      recovery: {
        hrvMs: 38,
        hrvBaseline30dMs: 50,
        restingHrBpm: 60,
        restingHrBaseline30dBpm: 54,
      },
    });

    expect(result.decision).toBe("recover");
    expect(result.overridesApplied).toContain("hrv_rhr_stress");
  });

  it("forces recover on back-to-back high-strain days", () => {
    const result = computeReadiness({
      ...healthy,
      load: {
        yesterdayStrain: 16,
        strain7dAvg: 10,
        acuteChronicRatio: 1.4,
      },
      meta: { daysOfHistory: 30, consecutiveHighStrainDays: 2 },
    });

    expect(result.decision).toBe("recover");
    expect(result.overridesApplied).toContain("back_to_back_high_strain");
  });

  it("caps a calibrating strong day at maintain", () => {
    const result = computeReadiness({
      ...healthy,
      meta: { daysOfHistory: 5, consecutiveHighStrainDays: 0 },
    });

    expect(result.calibrating).toBe(true);
    expect(result.decision).toBe("maintain");
    expect(result.overridesApplied).toContain("calibrating_cap");
  });
});
