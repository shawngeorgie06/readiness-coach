export type MetricPosition = "below" | "within" | "above";

export interface MetricBaseline {
  today: number | null;
  baseline30d: number | null;
  neutralBand: { low: number; high: number } | null;
  /** Oldest first, exactly 14 entries, null for days without data. */
  recent14d: Array<number | null>;
  /** Which way is good for this metric; "none" = only leaving the band is notable. */
  goodDirection: "up" | "down" | "none";
  /**
   * Where today sits against the band, decided from full-precision values before
   * any rounding, with the same rule as the matching score driver. The rounded
   * numbers above can't decide it: 58.8314 and 58.8316 ms against 56.03 both
   * serialise as 58.83, yet the HRV driver calls one normal and one above.
   * Null without today's value or a 30-day baseline.
   */
  position: MetricPosition | null;
}

export interface TodayBaselines {
  hrv: MetricBaseline;
  restingHr: MetricBaseline;
  sleepHours: MetricBaseline;
  load7d: MetricBaseline;
}

export interface BaselineInput {
  hrvToday: number | null;
  hrvBaseline: number | null;
  hrvDaily14: Array<number | null>;
  rhrToday: number | null;
  rhrBaseline: number | null;
  rhrDaily14: Array<number | null>;
  sleepToday: number | null;
  sleepPrior30: number[];
  sleepDaily14: Array<number | null>;
  sleepNeedHours: number;
  load7dToday: number;
  load28dAvg: number;
  strain28d: number[];
}

const DAYS = 14;

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function roundOrNull(value: number | null): number | null {
  return value == null || !Number.isFinite(value) ? null : round2(value);
}

/** Exactly 14 entries, oldest first: keep the most recent 14, pad the front with null. */
function fit14(series: Array<number | null>): Array<number | null> {
  const tail = series.slice(-DAYS).map(roundOrNull);
  return [...Array<number | null>(DAYS - tail.length).fill(null), ...tail];
}

/** Position against a band centre, mirroring the driver that reads the same numbers. */
type PositionRule = (today: number, center: number) => MetricPosition;

/** scoreRecovery: HRV is "above/below your normal" at an inclusive ±5% of max(baseline, 1). */
const hrvPosition: PositionRule = (today, baseline) => {
  const delta = (today - baseline) / Math.max(baseline, 1);
  return delta >= 0.05 ? "above" : delta <= -0.05 ? "below" : "within";
};

/** scoreRecovery: resting HR is "elevated" only past +3% of max(baseline, 1). */
const restingHrPosition: PositionRule = (today, baseline) => {
  const delta = (today - baseline) / Math.max(baseline, 1);
  return delta > 0.03 ? "above" : delta < -0.03 ? "below" : "within";
};

/** scoreSleep: "below your target" when duration / max(need, 0.1) < 0.9. */
const sleepPosition: PositionRule = (today, need) => {
  const ratio = today / Math.max(need, 0.1);
  return ratio < 0.9 ? "below" : ratio > 1.1 ? "above" : "within";
};

/** scoreLoad: "ramping up" above 1.3×, "backing off" below 0.7×; the service uses 1 with no 28-day load. */
const loadPosition: PositionRule = (today, average) => {
  const ratio = average > 0 ? today / average : 1;
  return ratio > 1.3 ? "above" : ratio < 0.7 ? "below" : "within";
};

function isNumber(value: number | null): value is number {
  return value != null && Number.isFinite(value);
}

function metric(
  today: number | null,
  baseline: number | null,
  bandFraction: number,
  series: Array<number | null>,
  goodDirection: MetricBaseline["goodDirection"],
  positionOf: PositionRule,
  bandCenter: number | null = baseline,
): MetricBaseline {
  return {
    today: roundOrNull(today),
    baseline30d: roundOrNull(baseline),
    neutralBand: bandCenter == null || !Number.isFinite(bandCenter)
      ? null
      : { low: round2(bandCenter * (1 - bandFraction)), high: round2(bandCenter * (1 + bandFraction)) },
    recent14d: fit14(series),
    goodDirection,
    position: isNumber(today) && isNumber(baseline) && isNumber(bandCenter) ? positionOf(today, bandCenter) : null,
  };
}

function rollingSevenDayMeans(strain: number[]): Array<number | null> {
  return strain.map((_, index) => {
    if (index < 6) return null;
    const window = strain.slice(index - 6, index + 1);
    return window.reduce((sum, value) => sum + value, 0) / 7;
  });
}

export function buildBaselines(input: BaselineInput): TodayBaselines {
  const sleepNights = input.sleepPrior30.filter((hours) => Number.isFinite(hours) && hours > 0);
  const sleepBaseline = sleepNights.length === 0
    ? null
    : sleepNights.reduce((sum, hours) => sum + hours, 0) / sleepNights.length;

  return {
    hrv: metric(input.hrvToday, input.hrvBaseline, 0.05, input.hrvDaily14, "up", hrvPosition),
    restingHr: metric(input.rhrToday, input.rhrBaseline, 0.03, input.rhrDaily14, "down", restingHrPosition),
    // Sleep is scored against the nightly target, not the personal average, so the
    // band sits on the target's 0.9 cut and can't contradict the duration driver.
    sleepHours: metric(
      input.sleepToday, sleepBaseline, 0.1, input.sleepDaily14, "up", sleepPosition, input.sleepNeedHours,
    ),
    load7d: metric(input.load7dToday, input.load28dAvg, 0.3, rollingSevenDayMeans(input.strain28d), "none", loadPosition),
  };
}
