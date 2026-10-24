import type { Prisma } from "@prisma/client";

const DAY_MS = 24 * 60 * 60 * 1000;
const MIN_MS = 60 * 1000;
const HOUR_MS = 60 * MIN_MS;
const userId = "perf-user";
const days = 90;
const batchSize = 5000;

function databaseName(url: string | undefined): string {
  if (!url) return "";
  try {
    return decodeURIComponent(new URL(url).pathname.replace(/^\//, ""));
  } catch {
    return "";
  }
}

type SampleRow = Prisma.HealthSampleCreateManyInput;

function utcMidnight(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

/** One staged night of about 7 h: five sleep cycles of core/deep/rem plus short awake gaps. */
function sleepStages(day: Date, stamp: string): SampleRow[] {
  const rows: SampleRow[] = [];
  let cursor = day.getTime() - HOUR_MS; // 23:00 the previous evening
  const cycle: Array<{ stage: string; minutes: number }> = [
    { stage: "core", minutes: 40 },
    { stage: "deep", minutes: 20 },
    { stage: "core", minutes: 15 },
    { stage: "rem", minutes: 10 },
    { stage: "awake", minutes: 2 },
  ];
  for (let c = 0; c < 5; c += 1) {
    cycle.forEach((segment, index) => {
      const startAt = new Date(cursor);
      cursor += segment.minutes * MIN_MS;
      rows.push({
        userId,
        hkUuid: `perf-sleep-${stamp}-${c}-${index}`,
        type: "sleep_analysis",
        startAt,
        endAt: new Date(cursor),
        metadata: { stage: segment.stage },
      });
    });
  }
  return rows;
}

function buildSamples(today: Date): SampleRow[] {
  const rows: SampleRow[] = [];
  for (let offset = 0; offset < days; offset += 1) {
    const day = new Date(today.getTime() - offset * DAY_MS);
    const stamp = day.toISOString().slice(0, 10);

    for (let slot = 0; slot < 288; slot += 1) {
      const at = new Date(day.getTime() + slot * 5 * MIN_MS);
      if (at.getTime() > Date.now()) break;
      rows.push({
        userId,
        hkUuid: `perf-hr-${stamp}-${slot}`,
        type: "heart_rate",
        startAt: at,
        endAt: at,
        value: 58 + ((slot * 7 + offset) % 40),
        unit: "count/min",
      });
    }

    for (let i = 0; i < 6; i += 1) {
      const at = new Date(day.getTime() + (2 + i * 3) * HOUR_MS);
      rows.push({
        userId,
        hkUuid: `perf-hrv-${stamp}-${i}`,
        type: "hrv_sdnn",
        startAt: at,
        endAt: at,
        value: 45 + ((offset + i) % 15),
        unit: "ms",
      });
    }

    const rhrAt = new Date(day.getTime() + 8 * HOUR_MS);
    rows.push({
      userId,
      hkUuid: `perf-rhr-${stamp}`,
      type: "resting_heart_rate",
      startAt: rhrAt,
      endAt: rhrAt,
      value: 54 + (offset % 3),
      unit: "count/min",
    });

    rows.push(...sleepStages(day, stamp));
  }
  return rows;
}

function buildWorkouts(today: Date): Prisma.WorkoutCreateManyInput[] {
  const rows: Prisma.WorkoutCreateManyInput[] = [];
  const sports = ["functional_strength_training", "running", "cycling", "hiit"];
  for (let offset = 0; offset < days; offset += 1) {
    // 4 per week: days 0, 2, 4, 5 of each 7-day block.
    if (![0, 2, 4, 5].includes(offset % 7)) continue;
    const day = new Date(today.getTime() - offset * DAY_MS);
    const stamp = day.toISOString().slice(0, 10);
    const startAt = new Date(day.getTime() + 17 * HOUR_MS);
    if (startAt.getTime() > Date.now()) continue;
    rows.push({
      userId,
      hkUuid: `perf-workout-${stamp}`,
      sport: sports[offset % sports.length],
      startAt,
      endAt: new Date(startAt.getTime() + 45 * MIN_MS),
      durationMin: 45,
      avgHrBpm: 135 + (offset % 10),
      calories: 300 + (offset % 5) * 20,
      strain: 8.5,
    });
  }
  return rows;
}

async function main() {
  const name = databaseName(process.env.DATABASE_URL);
  if (!name.endsWith("_test") && !name.endsWith("_perf")) {
    throw new Error(`Refusing to seed: database "${name}" must end in _test or _perf`);
  }
  const { prisma } = await import("../src/db.js");
  try {
    const today = utcMidnight(new Date());
    await prisma.user.upsert({
      where: { id: userId },
      create: { id: userId, goal: "recomp", sleepNeedHours: 8 },
      update: { goal: "recomp", sleepNeedHours: 8 },
    });

    const samples = buildSamples(today);
    for (let i = 0; i < samples.length; i += batchSize) {
      await prisma.healthSample.createMany({ data: samples.slice(i, i + batchSize), skipDuplicates: true });
    }
    const workouts = buildWorkouts(today);
    await prisma.workout.createMany({ data: workouts, skipDuplicates: true });

    console.log(`Seeded ${userId} in ${name}: ${samples.length} samples, ${workouts.length} workouts over ${days} days`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
