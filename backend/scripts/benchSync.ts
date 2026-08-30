/**
 * Times applySync at backfill volume against TEST_DATABASE_URL.
 *
 * Local Postgres understates the win: the cost this measures is per-statement
 * round trips, and a loopback round trip is ~50x cheaper than one to Neon.
 * Read the statement count as much as the wall time.
 *
 *   TEST_DATABASE_URL=... npx tsx scripts/benchSync.ts [sampleCount]
 */
import { prisma } from "../src/db.js";
import { applySync } from "../src/services/syncService.js";
import { requireSafeTestDatabaseUrl } from "../tests/helpers/testDatabase.js";

const count = Number(process.argv[2] ?? 5_000);
const userId = "bench-user";

requireSafeTestDatabaseUrl(process.env.DATABASE_URL);

const base = Date.parse("2026-07-01T00:00:00.000Z");
const samples = Array.from({ length: count }, (_, index) => {
  const at = new Date(base + index * 1_000).toISOString();
  return {
    hkUuid: `bench-hr-${index}`,
    type: "heart_rate" as const,
    startAt: at,
    endAt: at,
    value: 60 + (index % 40),
    unit: "count/min",
    metadata: { source: "watch" },
  };
});

await prisma.healthSample.deleteMany({ where: { userId } });
await prisma.workout.deleteMany({ where: { userId } });

const insertStart = performance.now();
await applySync({ userId, samples, workouts: [] }, { restingHrBpm: 55, maxHrBpm: 190 });
const insertMs = performance.now() - insertStart;

const updateStart = performance.now();
await applySync({ userId, samples, workouts: [] }, { restingHrBpm: 55, maxHrBpm: 190 });
const updateMs = performance.now() - updateStart;

console.log(`${count} samples`);
console.log(`  cold insert: ${insertMs.toFixed(0)} ms`);
console.log(`  re-upsert:   ${updateMs.toFixed(0)} ms`);

await prisma.healthSample.deleteMany({ where: { userId } });
await prisma.$disconnect();
