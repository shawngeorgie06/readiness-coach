import { prisma } from "../../src/db.js";

export function requireSafeTestDatabaseUrl(
  value: string | undefined,
): string {
  if (!value) {
    throw new Error("TEST_DATABASE_URL is required for integration tests");
  }

  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error("TEST_DATABASE_URL must be a valid URL");
  }

  if (parsed.protocol !== "postgres:" && parsed.protocol !== "postgresql:") {
    throw new Error("TEST_DATABASE_URL must use PostgreSQL");
  }

  const databaseName = decodeURIComponent(parsed.pathname.replace(/^\/+/, ""));
  if (!databaseName.endsWith("_test")) {
    throw new Error('TEST_DATABASE_URL database name must end with "_test"');
  }

  return value;
}

export async function resetTestDatabase(): Promise<void> {
  requireSafeTestDatabaseUrl(process.env.DATABASE_URL);
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "AdvisorNote", "DailyScore", "Workout", "HealthSample", "User" RESTART IDENTITY CASCADE',
  );
}
