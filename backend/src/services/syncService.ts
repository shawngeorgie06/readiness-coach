import { randomUUID } from "node:crypto";
import { z } from "zod";
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

/**
 * Rows per bulk statement. Each statement binds nine arrays of this length, so
 * the cap keeps us well inside PostgreSQL's parameter limits while still making
 * a 5,000-sample chunk cost three round trips instead of 5,000.
 */
const BULK_BATCH_SIZE = 2_000;

function batches<T>(items: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

/**
 * Ids are client-generated because the column has no database-level default —
 * Prisma normally fills `cuid()` in, and raw SQL bypasses that. Only inserts
 * consume the value; on conflict the existing row keeps its id.
 */
function newId(): string {
  return randomUUID();
}

/**
 * Upserts a batch of samples in one statement.
 *
 * `unnest` turns nine parameter arrays into rows, so the whole batch is a single
 * round trip. That is the point: sync is round-trip bound against a remote
 * database, and the previous row-at-a-time upsert paid one trip per sample.
 */
async function upsertSampleBatch(
  userId: string,
  samples: SyncPayload["samples"]
): Promise<void> {
  if (samples.length === 0) return;

  await prisma.$executeRaw`
    INSERT INTO "HealthSample" ("id", "userId", "hkUuid", "type", "startAt", "endAt", "value", "unit", "metadata")
    SELECT * FROM unnest(
      ${samples.map(newId)}::text[],
      ${samples.map(() => userId)}::text[],
      ${samples.map((sample) => sample.hkUuid)}::text[],
      ${samples.map((sample) => sample.type)}::text[],
      ${samples.map((sample) => sample.startAt)}::timestamp[],
      ${samples.map((sample) => sample.endAt)}::timestamp[],
      ${samples.map((sample) => sample.value ?? null)}::double precision[],
      ${samples.map((sample) => sample.unit ?? null)}::text[],
      ${samples.map((sample) =>
        sample.metadata === undefined ? null : JSON.stringify(sample.metadata)
      )}::jsonb[]
    )
    ON CONFLICT ("userId", "hkUuid") DO UPDATE SET
      "value" = EXCLUDED."value",
      "endAt" = EXCLUDED."endAt",
      "metadata" = EXCLUDED."metadata"
  `;
}

/** As `upsertSampleBatch`, with strain computed in JS before the statement runs. */
async function upsertWorkoutBatch(
  userId: string,
  workouts: SyncPayload["workouts"],
  defaults: SyncDefaults
): Promise<void> {
  if (workouts.length === 0) return;

  const strains = workouts.map((workout) =>
    estimateWorkoutStrain({
      durationMin: workout.durationMin,
      avgHrBpm: workout.avgHrBpm ?? 0,
      restingHrBpm: defaults.restingHrBpm,
      maxHrBpm: defaults.maxHrBpm,
    })
  );

  await prisma.$executeRaw`
    INSERT INTO "Workout" ("id", "userId", "hkUuid", "sport", "startAt", "endAt", "durationMin", "avgHrBpm", "calories", "strain")
    SELECT * FROM unnest(
      ${workouts.map(newId)}::text[],
      ${workouts.map(() => userId)}::text[],
      ${workouts.map((workout) => workout.hkUuid)}::text[],
      ${workouts.map((workout) => workout.sport)}::text[],
      ${workouts.map((workout) => workout.startAt)}::timestamp[],
      ${workouts.map((workout) => workout.endAt)}::timestamp[],
      ${workouts.map((workout) => workout.durationMin)}::double precision[],
      ${workouts.map((workout) => workout.avgHrBpm ?? null)}::double precision[],
      ${workouts.map((workout) => workout.calories ?? null)}::double precision[],
      ${strains}::double precision[]
    )
    ON CONFLICT ("userId", "hkUuid") DO UPDATE SET
      "sport" = EXCLUDED."sport",
      "durationMin" = EXCLUDED."durationMin",
      "avgHrBpm" = EXCLUDED."avgHrBpm",
      "calories" = EXCLUDED."calories",
      "strain" = EXCLUDED."strain",
      "endAt" = EXCLUDED."endAt"
  `;
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

  for (const batch of batches(payload.samples, BULK_BATCH_SIZE)) {
    await upsertSampleBatch(payload.userId, batch);
  }

  for (const batch of batches(payload.workouts, BULK_BATCH_SIZE)) {
    await upsertWorkoutBatch(payload.userId, batch, defaults);
  }

  return {
    ok: true as const,
    samples: payload.samples.length,
    workouts: payload.workouts.length,
  };
}
