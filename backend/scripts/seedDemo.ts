import type { Prisma } from "@prisma/client";
import { prisma } from "../src/db.js";
import { defaultRequestedDate, dateStart } from "../src/services/todayService.js";

const DAY_MS = 24 * 60 * 60 * 1000;
const userId = "user_1";

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * DAY_MS);
}

async function upsertSample(input: {
  hkUuid: string;
  type: string;
  startAt: Date;
  endAt: Date;
  value?: number;
  unit?: string;
  metadata?: Prisma.InputJsonValue;
}) {
  await prisma.healthSample.upsert({
    where: { userId_hkUuid: { userId, hkUuid: input.hkUuid } },
    create: { userId, ...input },
    update: {
      endAt: input.endAt,
      value: input.value,
      unit: input.unit,
      metadata: input.metadata,
    },
  });
}

async function main() {
  const today = dateStart(defaultRequestedDate());
  await prisma.user.upsert({
    where: { id: userId },
    create: { id: userId, goal: "recomp", sleepNeedHours: 8 },
    update: { goal: "recomp", sleepNeedHours: 8 },
  });

  for (let offset = 0; offset < 35; offset += 1) {
    const day = addDays(today, -offset);
    const sleepStart = addDays(day, -1);
    sleepStart.setUTCHours(23, 0, 0, 0);
    const coreEnd = new Date(sleepStart.getTime() + 4.8 * 60 * 60 * 1000);
    const deepEnd = new Date(coreEnd.getTime() + 1.5 * 60 * 60 * 1000);
    const remEnd = new Date(deepEnd.getTime() + 1.7 * 60 * 60 * 1000);
    const stamp = day.toISOString().slice(0, 10);

    await Promise.all([
      upsertSample({ hkUuid: `demo-core-${stamp}`, type: "sleep_analysis", startAt: sleepStart, endAt: coreEnd, metadata: { stage: "core" } }),
      upsertSample({ hkUuid: `demo-deep-${stamp}`, type: "sleep_analysis", startAt: coreEnd, endAt: deepEnd, metadata: { stage: "deep" } }),
      upsertSample({ hkUuid: `demo-rem-${stamp}`, type: "sleep_analysis", startAt: deepEnd, endAt: remEnd, metadata: { stage: "rem" } }),
      upsertSample({ hkUuid: `demo-hrv-${stamp}`, type: "hrv_sdnn", startAt: new Date(day.getTime() + 8 * 60 * 60 * 1000), endAt: new Date(day.getTime() + 8 * 60 * 60 * 1000), value: 52 + (offset % 3), unit: "ms" }),
      upsertSample({ hkUuid: `demo-rhr-${stamp}`, type: "resting_heart_rate", startAt: new Date(day.getTime() + 8 * 60 * 60 * 1000), endAt: new Date(day.getTime() + 8 * 60 * 60 * 1000), value: 54 + (offset % 2), unit: "count/min" }),
    ]);

    if (offset > 0 && offset % 2 === 0) {
      const workoutStart = new Date(day.getTime() + 17 * 60 * 60 * 1000);
      const workoutEnd = new Date(workoutStart.getTime() + 45 * 60 * 1000);
      await prisma.workout.upsert({
        where: { userId_hkUuid: { userId, hkUuid: `demo-workout-${stamp}` } },
        create: {
          userId,
          hkUuid: `demo-workout-${stamp}`,
          sport: "functional_strength_training",
          startAt: workoutStart,
          endAt: workoutEnd,
          durationMin: 45,
          avgHrBpm: 135,
          calories: 300,
          strain: 8.5,
        },
        update: {},
      });
    }
  }

  console.log(`Seeded ${userId}; request /v1/today?userId=${userId}`);
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => prisma.$disconnect());
