export type Decision = "push" | "maintain" | "recover";

export interface SleepInput {
  /** Hours slept last night */
  durationHours: number;
  /** Personal sleep need target, default 8 */
  needHours: number;
  /** Deep + REM hours last night (0 if unknown) */
  restorativeHours: number;
  /** Rolling sleep debt in hours (positive = owed) */
  sleepDebtHours: number;
  /** Stddev of last 7 night durations; lower is better */
  consistencyStdHours: number;
}

export interface RecoveryInput {
  hrvMs: number;
  hrvBaseline30dMs: number;
  restingHrBpm: number;
  restingHrBaseline30dBpm: number;
  /** Optional overnight avg HR; omit if unknown */
  overnightHrBpm?: number;
}

export interface LoadInput {
  yesterdayStrain: number;
  strain7dAvg: number;
  /** Acute load (7d) / chronic load (28d); 1.0 = balanced */
  acuteChronicRatio: number;
}

export type Driver = {
  /** Concise, plain-language card line, e.g. "3h catch-up owed this week". */
  text: string;
  /** Exact explanation with units/timeframe for the tap sheet. */
  detail?: string;
};

export interface PillarScore {
  score: number; // 0-100
  drivers: Driver[];
}

export interface ReadinessResult {
  sleep: PillarScore;
  recovery: PillarScore;
  load: PillarScore;
  readiness: number;
  decision: Decision;
  overridesApplied: string[];
  calibrating: boolean;
}
