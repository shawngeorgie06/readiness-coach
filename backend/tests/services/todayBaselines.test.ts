import { describe, expect, it } from "vitest";
import { buildBaselines, type BaselineInput, type MetricBaseline } from "../../src/services/todayBaselines.js";
import { scoreLoad } from "../../src/scoring/load.js";
import { scoreRecovery } from "../../src/scoring/recovery.js";
import { scoreSleep } from "../../src/scoring/sleep.js";

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

  describe("position", () => {
    /** The numbers a client sees after JSON rounding, without the status. */
    const shown = (m: MetricBaseline) => JSON.stringify({ today: m.today, baseline30d: m.baseline30d, neutralBand: m.neutralBand });
    const hrvDriver = (hrvMs: number, hrvBaseline30dMs: number) =>
      scoreRecovery({ hrvMs, hrvBaseline30dMs, restingHrBpm: 50, restingHrBaseline30dBpm: 50 }).drivers[0].text;

    it("follows the HRV driver when rounded payloads are identical", () => {
      const within = buildBaselines(input({ hrvToday: 58.8314, hrvBaseline: 56.03 })).hrv;
      const above = buildBaselines(input({ hrvToday: 58.8316, hrvBaseline: 56.03 })).hrv;
      expect(shown(within)).toBe(shown(above));
      expect(within).toMatchObject({ today: 58.83, baseline30d: 56.03, neutralBand: { low: 53.23, high: 58.83 } });

      expect(hrvDriver(58.8314, 56.03)).toContain("normal for you");
      expect(within.position).toBe("within");
      expect(hrvDriver(58.8316, 56.03)).toContain("above your normal");
      expect(above.position).toBe("above");
    });

    it("keeps an exactly-2-decimal HRV of 58.83 against 56.03 within normal", () => {
      expect(hrvDriver(58.83, 56.03)).toContain("normal for you");
      expect(buildBaselines(input({ hrvToday: 58.83, hrvBaseline: 56.03 })).hrv.position).toBe("within");
    });

    it("counts HRV at exactly ±5% as outside, like the driver", () => {
      const at = (hrvToday: number) => buildBaselines(input({ hrvToday, hrvBaseline: 100 })).hrv.position;
      expect(hrvDriver(105, 100)).toContain("above your normal");
      expect(at(105)).toBe("above");
      expect(hrvDriver(95, 100)).toContain("below your normal");
      expect(at(95)).toBe("below");
      expect(at(104.99)).toBe("within");
      expect(at(95.01)).toBe("within");
    });

    it("divides HRV by at least 1, like the driver", () => {
      // Against the ±5% band (0.475–0.525) 0.53 looks above; the driver's delta is 0.03.
      const at = (hrvToday: number) => buildBaselines(input({ hrvToday, hrvBaseline: 0.5 })).hrv.position;
      expect(hrvDriver(0.53, 0.5)).toContain("normal for you");
      expect(at(0.53)).toBe("within");
      expect(hrvDriver(0.56, 0.5)).toContain("above your normal");
      expect(at(0.56)).toBe("above");
    });

    it("flags resting HR only past +3%, before rounding", () => {
      const elevated = (restingHrBpm: number) =>
        scoreRecovery({ hrvMs: 60, hrvBaseline30dMs: 60, restingHrBpm, restingHrBaseline30dBpm: 52.004 })
          .drivers.some((d) => d.text.includes("elevated"));
      const under = buildBaselines(input({ rhrToday: 53.564, rhrBaseline: 52.004 })).restingHr;
      const over = buildBaselines(input({ rhrToday: 53.5645, rhrBaseline: 52.004 })).restingHr;
      expect(shown(under)).toBe(shown(over));
      expect(elevated(53.564)).toBe(false);
      expect(under.position).toBe("within");
      expect(elevated(53.5645)).toBe(true);
      expect(over.position).toBe("above");
      expect(buildBaselines(input({ rhrToday: 50.43, rhrBaseline: 52.004 })).restingHr.position).toBe("below");
      expect(buildBaselines(input({ rhrToday: 103, rhrBaseline: 100 })).restingHr.position).toBe("within");
      expect(buildBaselines(input({ rhrToday: 97, rhrBaseline: 100 })).restingHr.position).toBe("within");
    });

    it("puts sleep below target exactly when the duration driver does", () => {
      const belowDriver = (durationHours: number) =>
        scoreSleep({ durationHours, needHours: 8, restorativeHours: 2, sleepDebtHours: 0, consistencyStdHours: 0 })
          .drivers.some((d) => d.text.includes("below your 8h target"));
      const short = buildBaselines(input({ sleepToday: 7.1996, sleepNeedHours: 8 })).sleepHours;
      const enough = buildBaselines(input({ sleepToday: 7.2004, sleepNeedHours: 8 })).sleepHours;
      expect(shown(short)).toBe(shown(enough));
      expect(belowDriver(7.1996)).toBe(true);
      expect(short.position).toBe("below");
      expect(belowDriver(7.2004)).toBe(false);
      expect(enough.position).toBe("within");
      expect(buildBaselines(input({ sleepToday: 7.2, sleepNeedHours: 8 })).sleepHours.position).toBe("within");
      expect(buildBaselines(input({ sleepToday: 8.81, sleepNeedHours: 8 })).sleepHours.position).toBe("above");
    });

    it("marks load ramping or backing off exactly when the load driver does", () => {
      const balance = (acuteChronicRatio: number) =>
        scoreLoad({ yesterdayStrain: 5, strain7dAvg: 5, acuteChronicRatio }).drivers.find((d) => d.text.startsWith("Training load"))!.text;
      const steady = buildBaselines(input({ load7dToday: 5.1996, load28dAvg: 4 })).load7d;
      const ramping = buildBaselines(input({ load7dToday: 5.2004, load28dAvg: 4 })).load7d;
      expect(shown(steady)).toBe(shown(ramping));
      expect(balance(5.1996 / 4)).toBe("Training load balanced");
      expect(steady.position).toBe("within");
      expect(balance(5.2004 / 4)).toBe("Training load ramping up");
      expect(ramping.position).toBe("above");
      expect(balance(2.7996 / 4)).toBe("Training load backing off");
      expect(buildBaselines(input({ load7dToday: 2.7996, load28dAvg: 4 })).load7d.position).toBe("below");
      // No 28-day load: the service's ratio is 1, so the driver says balanced.
      expect(buildBaselines(input({ load7dToday: 0, load28dAvg: 0 })).load7d.position).toBe("within");
    });

    it("has no status without today's value or a baseline", () => {
      const result = buildBaselines(input({
        hrvToday: null, rhrBaseline: null, sleepPrior30: [], load7dToday: Number.NaN,
      }));
      expect(result.hrv.position).toBeNull();
      expect(result.restingHr.position).toBeNull();
      // The target band exists, but there's no 30-day normal yet.
      expect(result.sleepHours.neutralBand).not.toBeNull();
      expect(result.sleepHours.position).toBeNull();
      expect(result.load7d.position).toBeNull();
      expect(buildBaselines(input({ sleepToday: null })).sleepHours.position).toBeNull();
    });

    it("serialises position as a field on every metric", () => {
      const json = JSON.parse(JSON.stringify(buildBaselines(input({ hrvToday: null }))));
      for (const key of ["hrv", "restingHr", "sleepHours", "load7d"]) expect(json[key]).toHaveProperty("position");
      expect(json.hrv.position).toBeNull();
    });
  });
});
