import { describe, expect, it } from "vitest";
import { buildBaselines, type BaselineInput } from "../../src/services/todayBaselines.js";

const empty14 = Array<number | null>(14).fill(null);

function input(overrides: Partial<BaselineInput> = {}): BaselineInput {
  return {
    hrvToday: 62, hrvBaseline: 60, hrvDaily14: empty14,
    rhrToday: 50, rhrBaseline: 50, rhrDaily14: empty14,
    sleepToday: 7.5, sleepPrior30: [7, 8], sleepDaily14: empty14, sleepNeedHours: 8,
    load7dToday: 3, load28dAvg: 4, strain28d: Array(28).fill(0),
    ...overrides,
  };
}

describe("buildBaselines", () => {
  it("hrv band is ±5% of baseline and direction up", () => {
    const { hrv } = buildBaselines(input({ hrvBaseline: 60 }));
    expect(hrv.neutralBand).toEqual({ low: 57, high: 63 });
    expect(hrv.goodDirection).toBe("up");
    expect(hrv.baseline30d).toBe(60);
    expect(hrv.today).toBe(62);
  });

  it("rhr band is ±3% and direction down", () => {
    const { restingHr } = buildBaselines(input({ rhrBaseline: 50 }));
    expect(restingHr.neutralBand).toEqual({ low: 48.5, high: 51.5 });
    expect(restingHr.goodDirection).toBe("down");
  });

  it("null baseline gives null band", () => {
    const result = buildBaselines(input({ hrvBaseline: null, rhrBaseline: null, sleepPrior30: [] }));
    expect(result.hrv.neutralBand).toBeNull();
    expect(result.hrv.baseline30d).toBeNull();
    expect(result.restingHr.neutralBand).toBeNull();
    expect(result.sleepHours.baseline30d).toBeNull();
  });

  it("sleep band is ±10% of the scoring target, not the 30-day average", () => {
    // Averaging 5h, a 6h night beats the average but is still short of the 8h target the driver cites.
    const { sleepHours } = buildBaselines(input({ sleepPrior30: [5, 5], sleepToday: 6, sleepNeedHours: 8 }));
    expect(sleepHours.baseline30d).toBe(5);
    expect(sleepHours.neutralBand).toEqual({ low: 7.2, high: 8.8 });
    expect(sleepHours.today! < sleepHours.neutralBand!.low).toBe(true);
  });

  it("sleep band comes from the target even without history", () => {
    const { sleepHours } = buildBaselines(input({ sleepPrior30: [], sleepNeedHours: 7.5 }));
    expect(sleepHours.baseline30d).toBeNull();
    expect(sleepHours.neutralBand).toEqual({ low: 6.75, high: 8.25 });
  });

  it("sleep baseline ignores zero nights", () => {
    const { sleepHours } = buildBaselines(input({ sleepPrior30: [7, 0, 8] }));
    expect(sleepHours.baseline30d).toBe(7.5);
    expect(sleepHours.goodDirection).toBe("up");
  });

  it("load7d series is a 7-day rolling mean", () => {
    const strain28d = [...Array(21).fill(0), ...Array(7).fill(7)];
    const { load7d } = buildBaselines(input({ strain28d, load7dToday: 7, load28dAvg: 2 }));
    expect(load7d.recent14d.at(-1)).toBe(7);
    // The window ending on the first 7 (21st day) holds one 7 out of seven days.
    expect(load7d.recent14d[7]).toBe(1);
    expect(load7d.recent14d[6]).toBe(0);
    expect(load7d.goodDirection).toBe("none");
    expect(load7d.neutralBand).toEqual({ low: 1.4, high: 2.6 });
  });

  it("recent14d always has 14 entries", () => {
    const short = buildBaselines(input({ hrvDaily14: [1, 2, 3], sleepDaily14: [], strain28d: [1, 2, 3] }));
    expect(short.hrv.recent14d).toHaveLength(14);
    expect(short.hrv.recent14d.slice(-3)).toEqual([1, 2, 3]);
    expect(short.sleepHours.recent14d).toHaveLength(14);
    expect(short.load7d.recent14d).toHaveLength(14);
    const long = buildBaselines(input({ rhrDaily14: Array(20).fill(5) }));
    expect(long.restingHr.recent14d).toHaveLength(14);
  });
});
