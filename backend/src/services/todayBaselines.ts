export interface MetricBaseline {
  today: number | null;
  baseline30d: number | null;
  neutralBand: { low: number; high: number } | null;
  /** Oldest first, exactly 14 entries, null for days without data. */
  recent14d: Array<number | null>;
  /** Which way is good for this metric; "none" = only leaving the band is notable. */
  goodDirection: "up" | "down" | "none";
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

function metric(
  today: number | null,
  baseline: number | null,
  bandFraction: number,
  series: Array<number | null>,
  goodDirection: MetricBaseline["goodDirection"],
): MetricBaseline {
  const base = roundOrNull(baseline);
  return {
    today: roundOrNull(today),
    baseline30d: base,
    neutralBand: baseline == null || base == null
      ? null
      : { low: round2(baseline * (1 - bandFraction)), high: round2(baseline * (1 + bandFraction)) },
    recent14d: fit14(series),
    goodDirection,
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
    hrv: metric(input.hrvToday, input.hrvBaseline, 0.05, input.hrvDaily14, "up"),
    restingHr: metric(input.rhrToday, input.rhrBaseline, 0.03, input.rhrDaily14, "down"),
    sleepHours: metric(input.sleepToday, sleepBaseline, 0.1, input.sleepDaily14, "up"),
    load7d: metric(input.load7dToday, input.load28dAvg, 0.3, rollingSevenDayMeans(input.strain28d), "none"),
  };
}
