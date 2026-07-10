import { prisma } from "../db.js";
import { rollingMean, stddev } from "../scoring/baselines.js";
import { computeReadiness } from "../scoring/readiness.js";
import type { PillarScore } from "../scoring/types.js";
import { getAdvisorNote, type AdvisorNote } from "./advisorService.js";

export interface TodayResponse {
  date: string;
  readiness: number;
  decision: "push" | "maintain" | "recover";
  calibrating: boolean;
  pillars: {
    sleep: PillarScore;
    recovery: PillarScore;
    load: PillarScore;
  };
  overridesApplied: string[];
  confidence: "high" | "low";
  missing: string[];
  advisor: AdvisorNote;
}

export interface SleepSample {
  startAt: Date;
  endAt: Date;
  metadata?: unknown;
}

export interface SleepSummary {
  durationHours: number;
  restorativeHours: number;
}

export class UserNotFoundError extends Error {
  constructor(userId: string) {
    super(`User ${userId} was not found`);
  }
}

const DAY_MS = 24 * 60 * 60 * 1000;

function clampNonNegative(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0;
}

function round(value: number, digits = 2): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function sleepStage(metadata: unknown): string {
  if (metadata == null || typeof metadata !== "object" || Array.isArray(metadata)) {
    return "";
  }

  const record = metadata as Record<string, unknown>;
  return [record.stage, record.sleepStage, record.category, record.value]
    .find((value) => typeof value === "string")
    ?.toString()
    .toLowerCase()
    .replaceAll(" ", "") ?? "";
}

/** Aggregate a sleep window while excluding HealthKit awake/in-bed intervals. */
export function summarizeSleep(
  samples: SleepSample[],
  windowStart: Date,
  windowEnd: Date,
): SleepSummary {
  let durationMs = 0;
  let restorativeMs = 0;

  for (const sample of samples) {
    const stage = sleepStage(sample.metadata);
    if (stage.includes("awake") || stage.includes("inbed")) continue;

    const start = Math.max(sample.startAt.getTime(), windowStart.getTime());
    const end = Math.min(sample.endAt.getTime(), windowEnd.getTime());
    const overlapMs = Math.max(0, end - start);
    durationMs += overlapMs;
    if (stage.includes("deep") || stage.includes("rem")) restorativeMs += overlapMs;
  }

  return {
    durationHours: round(durationMs / (60 * 60 * 1000)),
    restorativeHours: round(restorativeMs / (60 * 60 * 1000)),
  };
}

/** Last night runs from noon on the previous calendar day through noon today. */
export function sleepWindowForDate(date: Date): { start: Date; end: Date } {
  const end = new Date(date.getTime() + 12 * 60 * 60 * 1000);
  const start = new Date(end.getTime() - DAY_MS);
  return { start, end };
}

export function parseRequestedDate(value: unknown): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error("date must be YYYY-MM-DD");
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw new Error("date must be YYYY-MM-DD");
  }
  return value;
}

/** v1 defaults to the calendar date on the API server, rather than UTC. */
export function defaultRequestedDate(now = new Date()): string {
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function dateStart(date: string): Date {
  return new Date(`${parseRequestedDate(date)}T00:00:00.000Z`);
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * DAY_MS);
}

function average(values: Array<number | null | undefined>, fallback: number): number {
  const usable = values.filter((value): value is number =>
    typeof value === "number" && Number.isFinite(value),
  );
  return usable.length === 0 ? fallback : rollingMean(usable, usable.length);
}

function latestInWindow<T extends { startAt: Date; value: number | null }>(
  samples: T[],
  start: Date,
  end: Date,
): number | undefined {
  return samples
    .filter((sample) =>
      sample.startAt >= start && sample.startAt < end && sample.value != null,
    )
    .sort((a, b) => b.startAt.getTime() - a.startAt.getTime())[0]?.value ?? undefined;
}

function dailyStrain(
  workouts: Array<{ endAt: Date; strain: number }>,
  start: Date,
  days: number,
): number[] {
  return Array.from({ length: days }, (_, index) => {
    const dayStart = addDays(start, index);
    const dayEnd = addDays(dayStart, 1);
    return workouts
      .filter((workout) => workout.endAt >= dayStart && workout.endAt < dayEnd)
      .reduce((total, workout) => total + workout.strain, 0);
  });
}

export function countConsecutiveHighStrain(dailyTotals: number[]): number {
  let count = 0;
  for (let index = dailyTotals.length - 1; index >= 0; index -= 1) {
    if (dailyTotals[index] < 14) break;
    count += 1;
  }
  return count;
}

function sleepHistory(
  samples: SleepSample[],
  targetStart: Date,
  days: number,
): SleepSummary[] {
  return Array.from({ length: days }, (_, index) => {
    const date = addDays(targetStart, index - (days - 1));
    const window = sleepWindowForDate(date);
    return summarizeSleep(samples, window.start, window.end);
  });
}

async function daysOfHistory(userId: string, date: Date): Promise<number> {
  const [sample, workout] = await Promise.all([
    prisma.healthSample.findFirst({ where: { userId }, orderBy: { startAt: "asc" } }),
    prisma.workout.findFirst({ where: { userId }, orderBy: { startAt: "asc" } }),
  ]);
  const first = [sample?.startAt, workout?.startAt]
    .filter((value): value is Date => value != null)
    .sort((a, b) => a.getTime() - b.getTime())[0];
  return first == null ? 0 : Math.max(1, Math.floor((date.getTime() - first.getTime()) / DAY_MS) + 1);
}

/** Compute today from synced raw data and persist its deterministic score. */
export async function getToday(userId: string, requestedDate = defaultRequestedDate()): Promise<TodayResponse> {
  const date = parseRequestedDate(requestedDate);
  const targetStart = dateStart(date);
  const targetEnd = addDays(targetStart, 1);
  const sleepWindow = sleepWindowForDate(targetStart);

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (user == null) throw new UserNotFoundError(userId);

  const [sleepSamples, hrvSamples, rhrSamples, hrSamples, workouts, historyDays] = await Promise.all([
    prisma.healthSample.findMany({
      where: {
        userId,
        type: "sleep_analysis",
        startAt: { lt: sleepWindow.end },
        endAt: { gt: addDays(sleepWindow.start, -7) },
      },
      orderBy: { startAt: "asc" },
    }),
    prisma.healthSample.findMany({
      where: { userId, type: "hrv_sdnn", startAt: { gte: addDays(targetStart, -30), lt: targetEnd } },
      orderBy: { startAt: "asc" },
    }),
    prisma.healthSample.findMany({
      where: { userId, type: "resting_heart_rate", startAt: { gte: addDays(targetStart, -30), lt: targetEnd } },
      orderBy: { startAt: "asc" },
    }),
    prisma.healthSample.findMany({
      where: { userId, type: "heart_rate", startAt: { gte: sleepWindow.start, lt: sleepWindow.end } },
      orderBy: { startAt: "asc" },
    }),
    prisma.workout.findMany({
      where: { userId, endAt: { gte: addDays(targetStart, -28), lt: targetStart } },
      orderBy: { endAt: "asc" },
    }),
    daysOfHistory(userId, targetStart),
  ]);

  const summaries = sleepHistory(sleepSamples, targetStart, 8);
  const lastNight = summaries.at(-1) ?? { durationHours: 0, restorativeHours: 0 };
  const recentSleep = summaries.slice(-7).map((summary) => summary.durationHours);
  const sleepDebtHours = recentSleep.reduce(
    (debt, duration) => debt + Math.max(0, user.sleepNeedHours - duration),
    0,
  );

  const currentHrv = latestInWindow(hrvSamples, targetStart, targetEnd);
  const hrvHistory = hrvSamples
    .filter((sample) => sample.startAt < targetStart)
    .map((sample) => sample.value)
    .filter((value): value is number => value != null);
  const currentRhr = latestInWindow(rhrSamples, targetStart, targetEnd);
  const rhrHistory = rhrSamples
    .filter((sample) => sample.startAt < targetStart)
    .map((sample) => sample.value)
    .filter((value): value is number => value != null);

  const hrv = currentHrv ?? 0;
  const hrvBaseline = hrvHistory.length > 0 ? average(hrvHistory, hrv || 1) : Math.max(hrv, 1);
  const rhr = currentRhr ?? average(rhrHistory, 60);
  const rhrBaseline = rhrHistory.length > 0 ? average(rhrHistory, rhr) : rhr;
  const overnightHr = average(hrSamples.map((sample) => sample.value), Number.NaN);

  const strain28d = dailyStrain(workouts, addDays(targetStart, -28), 28);
  const strain7d = strain28d.slice(-7);
  const sevenDayAverage = average(strain7d, 0);
  const chronicAverage = average(strain28d, 0);
  const acuteChronicRatio = chronicAverage > 0 ? sevenDayAverage / chronicAverage : 1;

  const readiness = computeReadiness({
    sleep: {
      durationHours: clampNonNegative(lastNight.durationHours),
      needHours: user.sleepNeedHours,
      restorativeHours: clampNonNegative(lastNight.restorativeHours),
      sleepDebtHours: round(sleepDebtHours),
      consistencyStdHours: round(stddev(recentSleep)),
    },
    recovery: {
      hrvMs: hrv,
      hrvBaseline30dMs: hrvBaseline,
      restingHrBpm: rhr,
      restingHrBaseline30dBpm: rhrBaseline,
      ...(Number.isFinite(overnightHr) ? { overnightHrBpm: overnightHr } : {}),
    },
    load: {
      yesterdayStrain: strain28d.at(-1) ?? 0,
      strain7dAvg: sevenDayAverage,
      acuteChronicRatio,
    },
    meta: {
      daysOfHistory: historyDays,
      consecutiveHighStrainDays: countConsecutiveHighStrain(strain28d),
    },
  });

  const missing: string[] = [];
  if (lastNight.durationHours <= 0) missing.push("sleep");
  if (currentHrv == null) missing.push("hrv");
  if (currentRhr == null) missing.push("resting_heart_rate");

  await prisma.dailyScore.upsert({
    where: { userId_date: { userId, date: targetStart } },
    create: {
      userId,
      date: targetStart,
      sleepScore: readiness.sleep.score,
      recoveryScore: readiness.recovery.score,
      loadScore: readiness.load.score,
      readiness: readiness.readiness,
      decision: readiness.decision,
      overrides: readiness.overridesApplied,
      calibrating: readiness.calibrating,
      drivers: {
        sleep: readiness.sleep.drivers,
        recovery: readiness.recovery.drivers,
        load: readiness.load.drivers,
      },
    },
    update: {
      sleepScore: readiness.sleep.score,
      recoveryScore: readiness.recovery.score,
      loadScore: readiness.load.score,
      readiness: readiness.readiness,
      decision: readiness.decision,
      overrides: readiness.overridesApplied,
      calibrating: readiness.calibrating,
      drivers: {
        sleep: readiness.sleep.drivers,
        recovery: readiness.recovery.drivers,
        load: readiness.load.drivers,
      },
    },
  });

  const response: Omit<TodayResponse, "advisor"> = {
    date,
    readiness: readiness.readiness,
    decision: readiness.decision,
    calibrating: readiness.calibrating,
    pillars: { sleep: readiness.sleep, recovery: readiness.recovery, load: readiness.load },
    overridesApplied: readiness.overridesApplied,
    confidence: missing.length === 0 ? "high" : "low",
    missing,
  };
  const advisor = await getAdvisorNote(userId, targetStart, response);
  return { ...response, advisor };
}

export async function getSleepDetails(userId: string, days: number, requestedDate = defaultRequestedDate()) {
  const target = dateStart(requestedDate);
  const start = addDays(target, -(days - 1));
  const samples = await prisma.healthSample.findMany({
    where: {
      userId,
      type: "sleep_analysis",
      startAt: { lt: addDays(target, 1) },
      endAt: { gt: addDays(start, -1) },
    },
    orderBy: { startAt: "asc" },
  });
  return {
    days,
    data: Array.from({ length: days }, (_, index) => {
      const day = addDays(start, index);
      const window = sleepWindowForDate(day);
      return { date: day.toISOString().slice(0, 10), ...summarizeSleep(samples, window.start, window.end) };
    }),
  };
}

export async function getTrainingDetails(userId: string, days: number, requestedDate = defaultRequestedDate()) {
  const end = addDays(dateStart(requestedDate), 1);
  const start = addDays(end, -days);
  const workouts = await prisma.workout.findMany({
    where: { userId, endAt: { gte: start, lt: end } },
    orderBy: { startAt: "desc" },
  });
  return {
    days,
    data: workouts.map((workout) => ({
      id: workout.id,
      sport: workout.sport,
      startAt: workout.startAt.toISOString(),
      endAt: workout.endAt.toISOString(),
      durationMin: workout.durationMin,
      avgHrBpm: workout.avgHrBpm,
      calories: workout.calories,
      strain: workout.strain,
    })),
  };
}

export async function getBodyDetails(userId: string, days: number, requestedDate = defaultRequestedDate()) {
  const end = addDays(dateStart(requestedDate), 1);
  const start = addDays(end, -days);
  const samples = await prisma.healthSample.findMany({
    where: {
      userId,
      type: { in: ["hrv_sdnn", "resting_heart_rate", "heart_rate"] },
      startAt: { gte: start, lt: end },
    },
    orderBy: { startAt: "asc" },
  });
  return {
    days,
    data: samples.map((sample) => ({
      type: sample.type,
      startAt: sample.startAt.toISOString(),
      endAt: sample.endAt.toISOString(),
      value: sample.value,
      unit: sample.unit,
    })),
  };
}
