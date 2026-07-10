# Backend Integration Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify the real Express-to-PostgreSQL backend path and add database readiness and graceful-shutdown safeguards without changing product behavior.

**Architecture:** Extract Express construction into an app factory while keeping process startup in `index.ts`. Run a separate Supertest integration suite against a dedicated migrated PostgreSQL database, with a hard safety check before truncating data. Keep existing unit tests database-free.

**Tech Stack:** Node.js 20, TypeScript, Express, Prisma, PostgreSQL 16, Vitest, Supertest

**Spec:** `docs/superpowers/specs/2026-07-10-backend-integration-hardening-design.md`

---

## File structure

```text
backend/
├── package.json                              # integration scripts and Supertest dependency
├── package-lock.json                         # dependency lock update
├── vitest.integration.config.ts              # isolated serial integration suite
├── .env.example                              # TEST_DATABASE_URL example
├── README.md                                 # test database and verification instructions
├── scripts/
│   └── runIntegrationTests.ts                # safe env setup, migrate deploy, run Vitest
├── src/
│   ├── app.ts                                # Express app factory and DB-aware /health
│   ├── index.ts                              # production startup and signal registration
│   └── shutdown.ts                           # idempotent graceful-shutdown primitive
└── tests/
    ├── app.test.ts                           # app factory, health, and auth unit tests
    ├── shutdown.test.ts                      # shutdown sequencing and idempotency
    ├── helpers/
    │   ├── testDatabase.ts                   # URL guard and table cleanup
    │   └── testDatabase.test.ts              # destructive-cleanup safety tests
    └── integration/
        └── api.test.ts                       # real HTTP + Prisma + PostgreSQL flow
```

---

### Task 1: Safe integration-test harness

**Files:**
- Create: `backend/tests/helpers/testDatabase.test.ts`
- Create: `backend/tests/helpers/testDatabase.ts`
- Create: `backend/scripts/runIntegrationTests.ts`
- Create: `backend/vitest.integration.config.ts`
- Modify: `backend/package.json`
- Modify: `backend/package-lock.json`
- Modify: `backend/.env.example`

- [ ] **Step 1: Write failing tests for the test-database URL guard**

Create `backend/tests/helpers/testDatabase.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { requireSafeTestDatabaseUrl } from "./testDatabase.js";

describe("requireSafeTestDatabaseUrl", () => {
  it("accepts a PostgreSQL database whose name ends in _test", () => {
    const value =
      "postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach_test";

    expect(requireSafeTestDatabaseUrl(value)).toBe(value);
  });

  it("rejects a missing URL", () => {
    expect(() => requireSafeTestDatabaseUrl(undefined)).toThrow(
      "TEST_DATABASE_URL is required",
    );
  });

  it("rejects a non-test database", () => {
    expect(() =>
      requireSafeTestDatabaseUrl(
        "postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach",
      ),
    ).toThrow('must end with "_test"');
  });

  it("rejects a non-PostgreSQL URL", () => {
    expect(() =>
      requireSafeTestDatabaseUrl("https://example.com/readiness_coach_test"),
    ).toThrow("must use PostgreSQL");
  });
});
```

- [ ] **Step 2: Run the guard test and verify it fails**

Run:

```powershell
cd backend
npm test -- tests/helpers/testDatabase.test.ts
```

Expected: FAIL because `tests/helpers/testDatabase.ts` does not exist.

- [ ] **Step 3: Implement the URL guard and cleanup helper**

Create `backend/tests/helpers/testDatabase.ts`:

```ts
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
```

- [ ] **Step 4: Run the guard tests and verify they pass**

Run:

```powershell
npm test -- tests/helpers/testDatabase.test.ts
```

Expected: 4 tests pass.

- [ ] **Step 5: Install Supertest**

Run:

```powershell
npm install --save-dev supertest @types/supertest
```

Expected: `package.json` and `package-lock.json` add both development dependencies.

- [ ] **Step 6: Add integration scripts**

Add these entries to `backend/package.json` under `scripts`:

```json
"test:integration": "tsx scripts/runIntegrationTests.ts",
"test:all": "npm test && npm run test:integration"
```

Keep the existing `test` and `test:watch` scripts unchanged.

- [ ] **Step 7: Add the isolated Vitest integration configuration**

Create `backend/vitest.integration.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/integration/**/*.test.ts"],
    fileParallelism: false,
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
```

- [ ] **Step 8: Add the cross-platform integration runner**

Create `backend/scripts/runIntegrationTests.ts`:

```ts
import { spawnSync } from "node:child_process";
import { requireSafeTestDatabaseUrl } from "../tests/helpers/testDatabase.js";

const testDatabaseUrl = requireSafeTestDatabaseUrl(
  process.env.TEST_DATABASE_URL,
);
const npx = process.platform === "win32" ? "npx.cmd" : "npx";
const env: NodeJS.ProcessEnv = {
  ...process.env,
  NODE_ENV: "test",
  DATABASE_URL: testDatabaseUrl,
  API_TOKEN: process.env.API_TOKEN ?? "integration-test-token",
  LLM_API_KEY: "",
  LLM_BASE_URL: process.env.LLM_BASE_URL ?? "https://api.openai.com/v1",
  LLM_MODEL: process.env.LLM_MODEL ?? "gpt-4o-mini",
};

function run(args: string[]): void {
  const result = spawnSync(npx, args, {
    cwd: process.cwd(),
    env,
    stdio: "inherit",
  });

  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

run(["prisma", "migrate", "deploy"]);
run(["vitest", "run", "--config", "vitest.integration.config.ts"]);
```

- [ ] **Step 9: Document the test database environment variable**

Append to `backend/.env.example`:

```env
TEST_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach_test
```

Do not change the production `DATABASE_URL` default as part of this task.

- [ ] **Step 10: Verify the existing unit suite remains green**

Run:

```powershell
npm test
```

Expected: all existing tests plus the 4 guard tests pass without requiring PostgreSQL.

- [ ] **Step 11: Commit the harness**

```powershell
git add backend/package.json backend/package-lock.json backend/vitest.integration.config.ts backend/scripts/runIntegrationTests.ts backend/tests/helpers backend/.env.example
git commit -m "test: add safe postgres integration harness"
```

---

### Task 2: App factory and database-aware health

**Files:**
- Create: `backend/tests/app.test.ts`
- Create: `backend/src/app.ts`
- Modify: `backend/src/index.ts`

- [ ] **Step 1: Write failing app-factory tests**

Create `backend/tests/app.test.ts`:

```ts
import request from "supertest";
import { describe, expect, it, vi } from "vitest";
import { createApp } from "../src/app.js";

describe("createApp", () => {
  it("reports ready when the database probe succeeds", async () => {
    const app = createApp({
      apiToken: "test-api-token",
      checkDatabase: async () => 1,
    });

    await request(app).get("/health").expect(200, { ok: true });
  });

  it("reports unavailable without leaking the database error", async () => {
    const error = new Error("password=secret");
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    const app = createApp({
      apiToken: "test-api-token",
      checkDatabase: async () => {
        throw error;
      },
    });

    const response = await request(app).get("/health").expect(503);

    expect(response.body).toEqual({ ok: false });
    expect(JSON.stringify(response.body)).not.toContain("secret");
    expect(consoleError).toHaveBeenCalledWith("Database health check failed", error);
    consoleError.mockRestore();
  });

  it("rejects missing and invalid bearer tokens", async () => {
    const app = createApp({
      apiToken: "test-api-token",
      checkDatabase: async () => 1,
    });

    await request(app).get("/v1/today?userId=missing").expect(401, {
      error: "unauthorized",
    });
    await request(app)
      .get("/v1/today?userId=missing")
      .set("Authorization", "Bearer wrong-token")
      .expect(401, { error: "unauthorized" });
  });

  it("allows a valid token to reach route validation", async () => {
    const app = createApp({
      apiToken: "test-api-token",
      checkDatabase: async () => 1,
    });

    await request(app)
      .get("/v1/today")
      .set("Authorization", "Bearer test-api-token")
      .expect(400, { error: "userId_required" });
  });
});
```

- [ ] **Step 2: Run the app test and verify it fails**

Run:

```powershell
npm test -- tests/app.test.ts
```

Expected: FAIL because `src/app.ts` does not exist.

- [ ] **Step 3: Implement the Express app factory**

Create `backend/src/app.ts`:

```ts
import cors from "cors";
import express from "express";
import { prisma } from "./db.js";
import { requireToken } from "./middleware/auth.js";
import { bodyRouter } from "./routes/body.js";
import { coachRouter } from "./routes/coach.js";
import { sleepRouter } from "./routes/sleep.js";
import { syncRouter } from "./routes/sync.js";
import { todayRouter } from "./routes/today.js";
import { trainRouter } from "./routes/train.js";

export interface AppOptions {
  apiToken: string;
  checkDatabase?: () => Promise<unknown>;
}

export function createApp({
  apiToken,
  checkDatabase = () => prisma.$queryRaw`SELECT 1`,
}: AppOptions) {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: "2mb" }));

  app.get("/health", async (_req, res) => {
    try {
      await checkDatabase();
      res.json({ ok: true });
    } catch (error) {
      console.error("Database health check failed", error);
      res.status(503).json({ ok: false });
    }
  });

  app.use("/v1", requireToken(apiToken));
  app.use("/v1/sync", syncRouter);
  app.use("/v1/today", todayRouter);
  app.use("/v1/sleep", sleepRouter);
  app.use("/v1/train", trainRouter);
  app.use("/v1/body", bodyRouter);
  app.use("/v1/coach", coachRouter);

  return app;
}
```

- [ ] **Step 4: Reduce `index.ts` to production startup**

Replace `backend/src/index.ts` with:

```ts
import { createApp } from "./app.js";
import { loadEnv } from "./env.js";

const env = loadEnv();
const app = createApp({ apiToken: env.API_TOKEN });

const server = app.listen(env.PORT, () => {
  console.log(`readiness-coach API on :${env.PORT}`);
});

export { app, server };
```

Graceful shutdown is added in Task 4. Exporting `app` and `server` preserves a testable startup seam.

- [ ] **Step 5: Run the focused and full unit suites**

Run:

```powershell
npm test -- tests/app.test.ts
npm test
npx tsc --noEmit
```

Expected: 4 app tests pass, the full unit suite passes, and TypeScript reports no errors.

- [ ] **Step 6: Commit the app factory**

```powershell
git add backend/src/app.ts backend/src/index.ts backend/tests/app.test.ts
git commit -m "feat: add database-aware app health"
```

---

### Task 3: PostgreSQL-backed API integration flow

**Files:**
- Create: `backend/tests/integration/api.test.ts`

- [ ] **Step 1: Create the dedicated local test database**

From the repository root, with Docker Compose Postgres running:

```powershell
docker compose exec db createdb -U postgres readiness_coach_test
```

Expected: exit 0. If PostgreSQL reports that the database already exists, keep the existing test database and continue.

- [ ] **Step 2: Write the integration tests**

Create `backend/tests/integration/api.test.ts`:

```ts
import request from "supertest";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createApp } from "../../src/app.js";
import { prisma } from "../../src/db.js";
import { resetTestDatabase } from "../helpers/testDatabase.js";

const TOKEN = process.env.API_TOKEN ?? "integration-test-token";
const authorization = `Bearer ${TOKEN}`;
const app = createApp({ apiToken: TOKEN });
const date = "2026-07-10";

const syncPayload = {
  userId: "integration-user",
  samples: [
    {
      hkUuid: "sleep-core",
      type: "sleep_analysis",
      startAt: "2026-07-09T22:00:00.000Z",
      endAt: "2026-07-10T02:00:00.000Z",
      metadata: { stage: "core" },
    },
    {
      hkUuid: "sleep-deep",
      type: "sleep_analysis",
      startAt: "2026-07-10T02:00:00.000Z",
      endAt: "2026-07-10T04:00:00.000Z",
      metadata: { stage: "deep" },
    },
    {
      hkUuid: "sleep-rem",
      type: "sleep_analysis",
      startAt: "2026-07-10T04:00:00.000Z",
      endAt: "2026-07-10T06:00:00.000Z",
      metadata: { stage: "rem" },
    },
    {
      hkUuid: "hrv-baseline",
      type: "hrv_sdnn",
      startAt: "2026-06-15T07:00:00.000Z",
      endAt: "2026-06-15T07:00:00.000Z",
      value: 50,
      unit: "ms",
    },
    {
      hkUuid: "hrv-current",
      type: "hrv_sdnn",
      startAt: "2026-07-10T07:00:00.000Z",
      endAt: "2026-07-10T07:00:00.000Z",
      value: 55,
      unit: "ms",
    },
    {
      hkUuid: "rhr-baseline",
      type: "resting_heart_rate",
      startAt: "2026-06-15T07:05:00.000Z",
      endAt: "2026-06-15T07:05:00.000Z",
      value: 54,
      unit: "count/min",
    },
    {
      hkUuid: "rhr-current",
      type: "resting_heart_rate",
      startAt: "2026-07-10T07:05:00.000Z",
      endAt: "2026-07-10T07:05:00.000Z",
      value: 53,
      unit: "count/min",
    },
  ],
  workouts: [],
};

beforeEach(async () => {
  await resetTestDatabase();
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe("backend API integration", () => {
  it("reports healthy with the real PostgreSQL connection", async () => {
    await request(app).get("/health").expect(200, { ok: true });
  });

  it("enforces bearer authentication", async () => {
    await request(app).get(`/v1/today?userId=integration-user&date=${date}`).expect(401);
    await request(app)
      .get(`/v1/today?userId=integration-user&date=${date}`)
      .set("Authorization", "Bearer invalid")
      .expect(401);
  });

  it("rejects invalid sync input", async () => {
    await request(app)
      .post("/v1/sync")
      .set("Authorization", authorization)
      .send({ userId: "", samples: [], workouts: [] })
      .expect(400);
  });

  it("returns 404 for an unknown user", async () => {
    await request(app)
      .get(`/v1/today?userId=unknown&date=${date}`)
      .set("Authorization", authorization)
      .expect(404, { error: "user_not_found" });
  });

  it("syncs idempotently and persists a Today score", async () => {
    const first = await request(app)
      .post("/v1/sync")
      .set("Authorization", authorization)
      .send(syncPayload)
      .expect(200);

    expect(first.body).toEqual({
      ok: true,
      samples: syncPayload.samples.length,
      workouts: 0,
    });

    const updatedPayload = {
      ...syncPayload,
      samples: syncPayload.samples.map((sample) =>
        sample.hkUuid === "hrv-current" ? { ...sample, value: 56 } : sample,
      ),
    };

    await request(app)
      .post("/v1/sync")
      .set("Authorization", authorization)
      .send(updatedPayload)
      .expect(200);

    expect(
      await prisma.healthSample.count({
        where: { userId: syncPayload.userId, hkUuid: "hrv-current" },
      }),
    ).toBe(1);
    expect(
      await prisma.healthSample.findUnique({
        where: {
          userId_hkUuid: {
            userId: syncPayload.userId,
            hkUuid: "hrv-current",
          },
        },
      }),
    ).toMatchObject({ value: 56 });

    const today = await request(app)
      .get(`/v1/today?userId=${syncPayload.userId}&date=${date}`)
      .set("Authorization", authorization)
      .expect(200);

    expect(today.body).toMatchObject({
      date,
      calibrating: false,
      confidence: "high",
      missing: [],
      pillars: {
        sleep: { score: expect.any(Number), drivers: expect.any(Array) },
        recovery: { score: expect.any(Number), drivers: expect.any(Array) },
        load: { score: expect.any(Number), drivers: expect.any(Array) },
      },
      advisor: {
        decision: expect.stringMatching(/^(push|maintain|recover)$/),
        source: "template",
      },
    });
    expect(today.body.readiness).toEqual(expect.any(Number));
    expect(today.body.decision).toMatch(/^(push|maintain|recover)$/);

    expect(
      await prisma.dailyScore.count({
        where: { userId: syncPayload.userId, date: new Date(`${date}T00:00:00.000Z`) },
      }),
    ).toBe(1);
  });
});
```

- [ ] **Step 3: Run the integration suite**

Run:

```powershell
$env:TEST_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach_test"
npm run test:integration
```

Expected: Prisma reports the migration is applied and 5 integration tests pass.

- [ ] **Step 4: Prove the cleanup guard blocks the development database**

Run:

```powershell
$env:TEST_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach"
npm run test:integration
```

Expected: command exits nonzero with `TEST_DATABASE_URL database name must end with "_test"` before migrations or cleanup run.

Restore the safe value before continuing:

```powershell
$env:TEST_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach_test"
```

- [ ] **Step 5: Run all backend tests together**

Run:

```powershell
npm run test:all
```

Expected: unit and integration suites both pass.

- [ ] **Step 6: Commit the integration flow**

```powershell
git add backend/tests/integration/api.test.ts
git commit -m "test: cover sync and today against postgres"
```

---

### Task 4: Idempotent graceful shutdown and operating docs

**Files:**
- Create: `backend/tests/shutdown.test.ts`
- Create: `backend/src/shutdown.ts`
- Modify: `backend/src/index.ts`
- Modify: `backend/README.md`

- [ ] **Step 1: Write failing shutdown tests**

Create `backend/tests/shutdown.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { createGracefulShutdown } from "../src/shutdown.js";

describe("createGracefulShutdown", () => {
  it("closes HTTP before disconnecting Prisma and runs only once", async () => {
    const events: string[] = [];
    const closeServer = vi.fn(async () => {
      events.push("http");
    });
    const disconnectDatabase = vi.fn(async () => {
      events.push("database");
    });
    const shutdown = createGracefulShutdown({
      closeServer,
      disconnectDatabase,
      onError: vi.fn(),
    });

    await Promise.all([shutdown(), shutdown()]);

    expect(events).toEqual(["http", "database"]);
    expect(closeServer).toHaveBeenCalledTimes(1);
    expect(disconnectDatabase).toHaveBeenCalledTimes(1);
  });

  it("reports and rethrows shutdown failures", async () => {
    const error = new Error("close failed");
    const onError = vi.fn();
    const shutdown = createGracefulShutdown({
      closeServer: vi.fn().mockRejectedValue(error),
      disconnectDatabase: vi.fn(),
      onError,
    });

    await expect(shutdown()).rejects.toThrow("close failed");
    expect(onError).toHaveBeenCalledWith(error);
  });
});
```

- [ ] **Step 2: Run the shutdown test and verify it fails**

Run:

```powershell
npm test -- tests/shutdown.test.ts
```

Expected: FAIL because `src/shutdown.ts` does not exist.

- [ ] **Step 3: Implement the idempotent shutdown primitive**

Create `backend/src/shutdown.ts`:

```ts
export interface ShutdownDependencies {
  closeServer: () => Promise<void>;
  disconnectDatabase: () => Promise<void>;
  onError: (error: unknown) => void;
}

export function createGracefulShutdown({
  closeServer,
  disconnectDatabase,
  onError,
}: ShutdownDependencies): () => Promise<void> {
  let shutdownPromise: Promise<void> | undefined;

  return () => {
    shutdownPromise ??= (async () => {
      try {
        await closeServer();
        await disconnectDatabase();
      } catch (error) {
        onError(error);
        throw error;
      }
    })();

    return shutdownPromise;
  };
}
```

- [ ] **Step 4: Register shutdown in the production entry point**

Replace `backend/src/index.ts` with:

```ts
import { createApp } from "./app.js";
import { prisma } from "./db.js";
import { loadEnv } from "./env.js";
import { createGracefulShutdown } from "./shutdown.js";

const env = loadEnv();
const app = createApp({ apiToken: env.API_TOKEN });
const server = app.listen(env.PORT, () => {
  console.log(`readiness-coach API on :${env.PORT}`);
});

const shutdown = createGracefulShutdown({
  closeServer: () =>
    new Promise<void>((resolve, reject) => {
      server.close((error) => {
        if (error) reject(error);
        else resolve();
      });
    }),
  disconnectDatabase: () => prisma.$disconnect(),
  onError: (error) => {
    console.error("Graceful shutdown failed", error);
  },
});

function handleSignal(): void {
  void shutdown().catch(() => {
    process.exitCode = 1;
  });
}

process.once("SIGINT", handleSignal);
process.once("SIGTERM", handleSignal);

export { app, server };
```

- [ ] **Step 5: Run shutdown and type checks**

Run:

```powershell
npm test -- tests/shutdown.test.ts
npm test
npx tsc --noEmit
```

Expected: 2 shutdown tests pass, all unit tests pass, and TypeScript reports no errors.

- [ ] **Step 6: Document local integration setup and commands**

Replace `backend/README.md` with:

```md
# Readiness Coach Backend

## Prerequisites

- Node.js 20 or newer
- Docker Desktop or PostgreSQL 16

## Development setup

1. Copy `.env.example` to `.env`.
2. Set `DATABASE_URL` and a private `API_TOKEN`.
3. On Windows, use `127.0.0.1` instead of `localhost` if Prisma cannot reach PostgreSQL.
4. Run `npm install`.
5. From the repository root, run `docker compose up -d`.
6. In `backend`, run `npx prisma migrate deploy`.
7. Start the API with `npm run dev`.

## Tests

Unit tests do not require PostgreSQL:

```powershell
npm test
```

Create the dedicated integration database once:

```powershell
docker compose exec db createdb -U postgres readiness_coach_test
```

Set the safe test URL and run integration tests:

```powershell
$env:TEST_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach_test"
npm run test:integration
```

Run all tests and TypeScript:

```powershell
npm run test:all
npx tsc --noEmit
```

The integration harness refuses to run destructive cleanup unless the database
name ends with `_test`.
```

- [ ] **Step 7: Run final verification**

Run:

```powershell
$env:TEST_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach_test"
npm run test:all
npx tsc --noEmit
$env:DATABASE_URL=$env:TEST_DATABASE_URL
npx prisma migrate status
```

Expected:

- Unit suite passes.
- 5 integration tests pass.
- TypeScript reports no errors.
- Prisma reports `Database schema is up to date!`.

- [ ] **Step 8: Commit graceful shutdown and docs**

```powershell
git add backend/src/index.ts backend/src/shutdown.ts backend/tests/shutdown.test.ts backend/README.md
git commit -m "feat: add graceful backend shutdown"
```

---

## Plan self-review

### Spec coverage

- Real HTTP → route → service → Prisma → PostgreSQL flow: Task 3
- Dedicated `_test` database guard: Tasks 1 and 3
- Migration deployment before integration tests: Task 1
- Auth, validation, idempotent sync, unknown user, and Today persistence: Tasks 2 and 3
- DB-aware `200`/`503` health behavior: Task 2
- Idempotent HTTP-close then Prisma-disconnect shutdown: Task 4
- Separate unit, integration, and combined commands: Tasks 1 and 4
- Windows `127.0.0.1` setup: Tasks 1, 3, and 4
- Deferred rate limits, Helmet, CORS restrictions, logging, CI, and LLM integration: intentionally excluded

### Placeholder scan

No implementation placeholders remain. Every code-changing step includes exact content, commands, and expected outcomes.

### Type consistency

- `createApp` consistently accepts `{ apiToken, checkDatabase? }`.
- `createGracefulShutdown` consistently accepts async close/disconnect functions and an error callback.
- Integration setup maps `TEST_DATABASE_URL` to Prisma's required `DATABASE_URL`.
- All API tests use the existing `integration-test-token` bearer-token contract.

