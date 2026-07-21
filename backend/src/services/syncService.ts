import { z } from "zod";
import type { Prisma } from "@prisma/client";
import { prisma } from "../db.js";
import { estimateWorkoutStrain } from "../scoring/strain.js";
import { assertNotDeleted } from "./userService.js";

export const syncPayloadSchema = z.object({
  userId: z.string().min(1),
  samples: z.array(
    z.object({
      hkUuid: z.string().min(1),
      type: z.enum([
        "heart_rate",
        "resting_heart_rate",
        "hrv_sdnn",
        "sleep_analysis",
        "oxygen_saturation",
      ]),
      startAt: z.string().datetime(),
      endAt: z.string().datetime(),
      value: z.number().nullable().optional(),
      unit: z.string().optional(),
      metadata: z.record(z.unknown()).optional(),
    })
  ),
  workouts: z.array(
    z.object({
      hkUuid: z.string().min(1),
      sport: z.string(),
      startAt: z.string().datetime(),
      endAt: z.string().datetime(),
      durationMin: z.number().nonnegative(),
      avgHrBpm: z.number().optional(),
      calories: z.number().optional(),
    })
  ),
});

export type SyncPayload = z.infer<typeof syncPayloadSchema>;

export interface SyncDefaults {
  restingHrBpm: number;
  maxHrBpm: number;
}

/** Parallel upserts per transaction — keeps large Watch heart-rate dumps under HTTP timeouts. */
const UPSERT_BATCH_SIZE = 50;

async function upsertInBatches<T>(
  items: T[],
  upsertOne: (item: T) => Prisma.PrismaPromise<unknown>
): Promise<void> {
  for (let index = 0; index < items.length; index += UPSERT_BATCH_SIZE) {
    const batch = items.slice(index, index + UPSERT_BATCH_SIZE);
    await prisma.$transaction(batch.map((item) => upsertOne(item)));
  }
}

/**
 * Idempotently merge a batch of HealthKit samples by the stable HealthKit UUID.
 * Validation stays separate so callers can reject malformed payloads before any
 * database mutation.
 */
export async function applySync(
  payload: SyncPayload,
  defaults: SyncDefaults
) {
  await assertNotDeleted(payload.userId);

  await prisma.user.upsert({
    where: { id: payload.userId },
    create: { id: payload.userId },
    update: {},
  });

  await upsertInBatches(payload.samples, (sample) =>
    prisma.healthSample.upsert({
      where: {
        userId_hkUuid: { userId: payload.userId, hkUuid: sample.hkUuid },
      },
      create: {
        userId: payload.userId,
        hkUuid: sample.hkUuid,
        type: sample.type,
        startAt: new Date(sample.startAt),
        endAt: new Date(sample.endAt),
        value: sample.value ?? null,
        unit: sample.unit,
        metadata: sample.metadata as Prisma.InputJsonValue | undefined,
      },
      update: {
        value: sample.value ?? null,
        endAt: new Date(sample.endAt),
        metadata: sample.metadata as Prisma.InputJsonValue | undefined,
      },
    })
  );

  await upsertInBatches(payload.workouts, (workout) => {
    const strain = estimateWorkoutStrain({
      durationMin: workout.durationMin,
      avgHrBpm: workout.avgHrBpm ?? 0,
      restingHrBpm: defaults.restingHrBpm,
      maxHrBpm: defaults.maxHrBpm,
    });

    return prisma.workout.upsert({
      where: {
        userId_hkUuid: { userId: payload.userId, hkUuid: workout.hkUuid },
      },
      create: {
        userId: payload.userId,
        hkUuid: workout.hkUuid,
        sport: workout.sport,
        startAt: new Date(workout.startAt),
        endAt: new Date(workout.endAt),
        durationMin: workout.durationMin,
        avgHrBpm: workout.avgHrBpm,
        calories: workout.calories,
        strain,
      },
      update: {
        sport: workout.sport,
        durationMin: workout.durationMin,
        avgHrBpm: workout.avgHrBpm,
        calories: workout.calories,
        strain,
        endAt: new Date(workout.endAt),
      },
    });
  });

  return {
    ok: true as const,
    samples: payload.samples.length,
    workouts: payload.workouts.length,
  };
}
