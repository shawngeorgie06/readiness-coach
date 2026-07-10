# Readiness Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a HealthKit-backed readiness system: deterministic Push/Maintain/Recover scoring, hybrid strict cloud advisor, iPhone app sync + Today UI, and a light web dashboard on the same API.

**Architecture:** Native-first. SwiftUI reads HealthKit and syncs samples to a TypeScript backend (Postgres). Backend computes baselines/scores/decisions, calls a cloud LLM only to write advisor copy and answer Ask Coach (decision is locked). Web dashboard is a thin read-only client of the same REST API.

**Tech Stack:** SwiftUI + HealthKit (iOS 17+), Node.js 20 + TypeScript + Express, Prisma + PostgreSQL, Vitest, OpenAI-compatible chat API (pluggable), Vite + React (web dashboard).

**Spec:** `docs/superpowers/specs/2026-07-10-readiness-coach-design.md`

**Execution note:** Tasks 1–8 (backend + web) can run fully in this Linux environment. Tasks 9–12 (iOS) require a Mac with Xcode and a physical iPhone + Apple Watch for HealthKit verification.

---

## File structure

```
readiness-coach/
├── docs/superpowers/...
├── backend/
│   ├── package.json
│   ├── tsconfig.json
│   ├── vitest.config.ts
│   ├── prisma/
│   │   └── schema.prisma
│   ├── src/
│   │   ├── index.ts                 # Express app entry
│   │   ├── env.ts                   # env validation
│   │   ├── db.ts                    # Prisma client
│   │   ├── middleware/auth.ts       # personal bearer token
│   │   ├── scoring/
│   │   │   ├── types.ts
│   │   │   ├── baselines.ts
│   │   │   ├── sleep.ts
│   │   │   ├── recovery.ts
│   │   │   ├── load.ts
│   │   │   ├── readiness.ts         # composite + bands + overrides
│   │   │   └── strain.ts
│   │   ├── services/
│   │   │   ├── syncService.ts
│   │   │   ├── todayService.ts
│   │   │   ├── advisorService.ts
│   │   │   └── llmClient.ts
│   │   └── routes/
│   │       ├── sync.ts
│   │       ├── today.ts
│   │       ├── sleep.ts
│   │       ├── train.ts
│   │       ├── body.ts
│   │       └── coach.ts
│   └── tests/
│       ├── scoring/
│       │   ├── sleep.test.ts
│       │   ├── recovery.test.ts
│       │   ├── load.test.ts
│       │   ├── strain.test.ts
│       │   └── readiness.test.ts
│       ├── services/
│       │   ├── syncService.test.ts
│       │   └── advisorService.test.ts
│       └── fixtures/
│           └── sampleDay.ts
├── web/
│   ├── package.json
│   ├── vite.config.ts
│   ├── index.html
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── api.ts
│       └── pages/TodayPage.tsx
└── ios/
    └── ReadinessCoach/
        ├── ReadinessCoachApp.swift
        ├── Info.plist (+ HealthKit entitlements)
        ├── Models/
        ├── Services/
        │   ├── HealthKitService.swift
        │   ├── SyncService.swift
        │   └── APIClient.swift
        └── Views/
            ├── OnboardingView.swift
            ├── TodayView.swift
            ├── SleepView.swift
            ├── TrainView.swift
            ├── BodyView.swift
            ├── AskCoachView.swift
            └── SettingsView.swift
```

---

### Task 1: Backend scaffold + Vitest

**Files:**
- Create: `backend/package.json`
- Create: `backend/tsconfig.json`
- Create: `backend/vitest.config.ts`
- Create: `backend/src/env.ts`
- Create: `backend/src/index.ts`
- Create: `backend/README.md`

- [ ] **Step 1: Create `backend/package.json`**

```json
{
  "name": "readiness-coach-backend",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "test": "vitest run",
    "test:watch": "vitest",
    "prisma:generate": "prisma generate",
    "prisma:migrate": "prisma migrate dev"
  },
  "dependencies": {
    "@prisma/client": "^6.5.0",
    "cors": "^2.8.5",
    "express": "^4.21.2",
    "zod": "^3.24.2"
  },
  "devDependencies": {
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^22.13.10",
    "prisma": "^6.5.0",
    "tsx": "^4.19.3",
    "typescript": "^5.8.2",
    "vitest": "^3.0.9"
  }
}
```

- [ ] **Step 2: Create `backend/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

- [ ] **Step 3: Create `backend/vitest.config.ts`**

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
  },
});
```

- [ ] **Step 4: Create `backend/src/env.ts`**

```ts
import { z } from "zod";

const envSchema = z.object({
  PORT: z.coerce.number().default(4000),
  DATABASE_URL: z.string().min(1),
  API_TOKEN: z.string().min(8),
  LLM_API_KEY: z.string().optional(),
  LLM_BASE_URL: z.string().url().default("https://api.openai.com/v1"),
  LLM_MODEL: z.string().default("gpt-4o-mini"),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(raw: NodeJS.ProcessEnv = process.env): Env {
  const parsed = envSchema.safeParse(raw);
  if (!parsed.success) {
    throw new Error(`Invalid env: ${parsed.error.message}`);
  }
  return parsed.data;
}
```

- [ ] **Step 5: Create minimal `backend/src/index.ts` health server**

```ts
import express from "express";
import cors from "cors";

const app = express();
app.use(cors());
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

const port = Number(process.env.PORT ?? 4000);
if (process.env.NODE_ENV !== "test") {
  app.listen(port, () => {
    console.log(`readiness-coach API on :${port}`);
  });
}

export { app };
```

- [ ] **Step 6: Create `backend/README.md` with setup notes**

Include: Node 20+, Postgres, copy `.env.example`, `npm install`, `npm test`, `npm run dev`.

- [ ] **Step 7: Create `backend/.env.example`**

```env
PORT=4000
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/readiness_coach
API_TOKEN=dev-token-change-me
LLM_API_KEY=
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini
```

- [ ] **Step 8: Install and verify health**

```bash
cd backend && npm install
npx tsc --noEmit
npx tsx -e "import { app } from './src/index.ts'"
```

Expected: install succeeds; `tsc` has no errors (or only unused until routes land).

- [ ] **Step 9: Commit**

```bash
git add backend
git commit -m "chore: scaffold readiness-coach backend"
```

---

### Task 2: Scoring types + sleep pillar (TDD)

**Files:**
- Create: `backend/src/scoring/types.ts`
- Create: `backend/src/scoring/sleep.ts`
- Create: `backend/tests/scoring/sleep.test.ts`
- Create: `backend/tests/fixtures/sampleDay.ts`

- [ ] **Step 1: Create shared types `backend/src/scoring/types.ts`**

```ts
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

export interface PillarScore {
  score: number; // 0-100
  drivers: string[];
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
```

- [ ] **Step 2: Write failing sleep tests**

```ts
// backend/tests/scoring/sleep.test.ts
import { describe, expect, it } from "vitest";
import { scoreSleep } from "../../src/scoring/sleep.js";

describe("scoreSleep", () => {
  it("scores high when duration meets need with low debt", () => {
    const result = scoreSleep({
      durationHours: 8,
      needHours: 8,
      restorativeHours: 3.2,
      sleepDebtHours: 0.2,
      consistencyStdHours: 0.4,
    });
    expect(result.score).toBeGreaterThanOrEqual(80);
  });

  it("scores low when short sleep and high debt", () => {
    const result = scoreSleep({
      durationHours: 4.5,
      needHours: 8,
      restorativeHours: 1.0,
      sleepDebtHours: 4,
      consistencyStdHours: 1.5,
    });
    expect(result.score).toBeLessThanOrEqual(40);
  });

  it("clamps score to 0-100", () => {
    const result = scoreSleep({
      durationHours: 0,
      needHours: 8,
      restorativeHours: 0,
      sleepDebtHours: 20,
      consistencyStdHours: 5,
    });
    expect(result.score).toBeGreaterThanOrEqual(0);
    expect(result.score).toBeLessThanOrEqual(100);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd backend && npm test -- tests/scoring/sleep.test.ts
```

Expected: FAIL — `scoreSleep` not found / cannot resolve module.

- [ ] **Step 4: Implement `backend/src/scoring/sleep.ts`**

```ts
import type { PillarScore, SleepInput } from "./types.js";

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

export function scoreSleep(input: SleepInput): PillarScore {
  const durationRatio = input.durationHours / Math.max(input.needHours, 0.1);
  const durationScore = clamp(durationRatio * 100);

  const restorativeTarget = Math.max(input.needHours * 0.35, 0.1);
  const restorativeScore = clamp((input.restorativeHours / restorativeTarget) * 100);

  const debtPenalty = clamp(input.sleepDebtHours * 12, 0, 50);
  const consistencyPenalty = clamp(input.consistencyStdHours * 15, 0, 25);

  const raw =
    durationScore * 0.45 +
    restorativeScore * 0.25 +
    (100 - debtPenalty) * 0.2 +
    (100 - consistencyPenalty) * 0.1;

  const drivers: string[] = [];
  if (durationRatio < 0.9) drivers.push(`Sleep ${input.durationHours.toFixed(1)}h vs need ${input.needHours}h`);
  if (input.sleepDebtHours >= 1) drivers.push(`Sleep debt ${input.sleepDebtHours.toFixed(1)}h`);
  if (input.consistencyStdHours >= 1) drivers.push("Inconsistent sleep timing/duration");
  if (drivers.length === 0) drivers.push("Sleep on target");

  return { score: Math.round(clamp(raw)), drivers };
}
```

- [ ] **Step 5: Run tests to verify pass**

```bash
cd backend && npm test -- tests/scoring/sleep.test.ts
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/src/scoring backend/tests
git commit -m "feat: add sleep pillar scoring"
```

---

### Task 3: Recovery + load + strain pillars (TDD)

**Files:**
- Create: `backend/src/scoring/recovery.ts`
- Create: `backend/src/scoring/load.ts`
- Create: `backend/src/scoring/strain.ts`
- Create: `backend/tests/scoring/recovery.test.ts`
- Create: `backend/tests/scoring/load.test.ts`
- Create: `backend/tests/scoring/strain.test.ts`

- [ ] **Step 1: Write failing recovery tests**

```ts
// backend/tests/scoring/recovery.test.ts
import { describe, expect, it } from "vitest";
import { scoreRecovery } from "../../src/scoring/recovery.js";

describe("scoreRecovery", () => {
  it("scores high when HRV at/above baseline and RHR stable", () => {
    const result = scoreRecovery({
      hrvMs: 55,
      hrvBaseline30dMs: 50,
      restingHrBpm: 52,
      restingHrBaseline30dBpm: 54,
    });
    expect(result.score).toBeGreaterThanOrEqual(75);
  });

  it("scores low when HRV deeply suppressed and RHR elevated", () => {
    const result = scoreRecovery({
      hrvMs: 35,
      hrvBaseline30dMs: 50,
      restingHrBpm: 62,
      restingHrBaseline30dBpm: 54,
    });
    expect(result.score).toBeLessThanOrEqual(45);
  });
});
```

- [ ] **Step 2: Implement `recovery.ts`**

```ts
import type { PillarScore, RecoveryInput } from "./types.js";

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

export function scoreRecovery(input: RecoveryInput): PillarScore {
  const hrvDelta =
    (input.hrvMs - input.hrvBaseline30dMs) / Math.max(input.hrvBaseline30dMs, 1);
  // +20% HRV → ~100, -20% → ~0 on this component
  const hrvScore = clamp(50 + hrvDelta * 250);

  const rhrDelta =
    (input.restingHrBpm - input.restingHrBaseline30dBpm) /
    Math.max(input.restingHrBaseline30dBpm, 1);
  // elevated RHR hurts
  const rhrScore = clamp(50 - rhrDelta * 400);

  let overnightScore = 70;
  if (input.overnightHrBpm != null) {
    const overnightDelta =
      (input.overnightHrBpm - input.restingHrBaseline30dBpm) /
      Math.max(input.restingHrBaseline30dBpm, 1);
    overnightScore = clamp(60 - overnightDelta * 300);
  }

  const raw = hrvScore * 0.55 + rhrScore * 0.3 + overnightScore * 0.15;
  const drivers: string[] = [];
  const hrvPct = hrvDelta * 100;
  drivers.push(`HRV ${hrvPct >= 0 ? "+" : ""}${hrvPct.toFixed(0)}% vs 30d baseline`);
  if (rhrDelta > 0.03) drivers.push("Resting HR elevated vs baseline");
  if (hrvDelta >= 0 && rhrDelta <= 0) drivers.push("Recovery markers stable");

  return { score: Math.round(clamp(raw)), drivers };
}
```

- [ ] **Step 3: Write failing strain + load tests**

```ts
// backend/tests/scoring/strain.test.ts
import { describe, expect, it } from "vitest";
import { estimateWorkoutStrain } from "../../src/scoring/strain.js";

describe("estimateWorkoutStrain", () => {
  it("returns 0 for empty workout", () => {
    expect(
      estimateWorkoutStrain({
        durationMin: 0,
        avgHrBpm: 0,
        restingHrBpm: 55,
        maxHrBpm: 190,
      })
    ).toBe(0);
  });

  it("increases with duration and intensity", () => {
    const easy = estimateWorkoutStrain({
      durationMin: 30,
      avgHrBpm: 110,
      restingHrBpm: 55,
      maxHrBpm: 190,
    });
    const hard = estimateWorkoutStrain({
      durationMin: 60,
      avgHrBpm: 160,
      restingHrBpm: 55,
      maxHrBpm: 190,
    });
    expect(hard).toBeGreaterThan(easy);
  });
});
```

```ts
// backend/tests/scoring/load.test.ts
import { describe, expect, it } from "vitest";
import { scoreLoad } from "../../src/scoring/load.js";

describe("scoreLoad", () => {
  it("scores higher when yesterday strain is moderate vs weekly avg", () => {
    const result = scoreLoad({
      yesterdayStrain: 8,
      strain7dAvg: 9,
      acuteChronicRatio: 1.0,
    });
    expect(result.score).toBeGreaterThanOrEqual(60);
  });

  it("scores lower when acute:chronic is spiked", () => {
    const result = scoreLoad({
      yesterdayStrain: 18,
      strain7dAvg: 10,
      acuteChronicRatio: 1.6,
    });
    expect(result.score).toBeLessThan(55);
  });
});
```

- [ ] **Step 4: Implement strain + load**

```ts
// backend/src/scoring/strain.ts
export interface WorkoutStrainInput {
  durationMin: number;
  avgHrBpm: number;
  restingHrBpm: number;
  maxHrBpm: number;
}

/** Deterministic 0-21-ish strain proxy (Whoop-like scale, not identical). */
export function estimateWorkoutStrain(input: WorkoutStrainInput): number {
  if (input.durationMin <= 0 || input.avgHrBpm <= 0) return 0;
  const reserve = Math.max(input.maxHrBpm - input.restingHrBpm, 1);
  const intensity = Math.max(
    0,
    Math.min(1, (input.avgHrBpm - input.restingHrBpm) / reserve)
  );
  const raw = (input.durationMin / 60) * (1 + intensity * 4) * 6;
  return Math.round(Math.min(21, raw) * 10) / 10;
}
```

```ts
// backend/src/scoring/load.ts
import type { LoadInput, PillarScore } from "./types.js";

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

export function scoreLoad(input: LoadInput): PillarScore {
  // Freshness: lower yesterday strain relative to capacity → higher score
  const relative =
    input.yesterdayStrain / Math.max(input.strain7dAvg || input.yesterdayStrain || 1, 1);
  const freshness = clamp(100 - (relative - 0.6) * 80);

  // ACR: ideal ~0.8-1.3
  let acrScore = 80;
  if (input.acuteChronicRatio > 1.3) {
    acrScore = clamp(80 - (input.acuteChronicRatio - 1.3) * 100);
  } else if (input.acuteChronicRatio < 0.7) {
    acrScore = clamp(70 - (0.7 - input.acuteChronicRatio) * 40);
  }

  const raw = freshness * 0.55 + acrScore * 0.45;
  const drivers: string[] = [];
  drivers.push(`Yesterday strain ${input.yesterdayStrain.toFixed(1)}`);
  drivers.push(`Acute:chronic ${input.acuteChronicRatio.toFixed(2)}`);
  if (input.acuteChronicRatio > 1.3) drivers.push("Training load spiked vs chronic baseline");

  return { score: Math.round(clamp(raw)), drivers };
}
```

- [ ] **Step 5: Run pillar tests**

```bash
cd backend && npm test -- tests/scoring/
```

Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add backend/src/scoring backend/tests/scoring
git commit -m "feat: add recovery, load, and strain scoring"
```

---

### Task 4: Composite readiness + hard overrides (TDD)

**Files:**
- Create: `backend/src/scoring/readiness.ts`
- Create: `backend/src/scoring/baselines.ts`
- Create: `backend/tests/scoring/readiness.test.ts`

- [ ] **Step 1: Write failing readiness tests covering bands + overrides**

```ts
// backend/tests/scoring/readiness.test.ts
import { describe, expect, it } from "vitest";
import { computeReadiness } from "../../src/scoring/readiness.js";

const healthy = {
  sleep: {
    durationHours: 8,
    needHours: 8,
    restorativeHours: 3,
    sleepDebtHours: 0.3,
    consistencyStdHours: 0.4,
  },
  recovery: {
    hrvMs: 52,
    hrvBaseline30dMs: 50,
    restingHrBpm: 54,
    restingHrBaseline30dBpm: 54,
  },
  load: {
    yesterdayStrain: 8,
    strain7dAvg: 9,
    acuteChronicRatio: 1.05,
  },
  meta: {
    daysOfHistory: 30,
    consecutiveHighStrainDays: 0,
  },
};

describe("computeReadiness", () => {
  it("returns push on a strong day", () => {
    const result = computeReadiness(healthy);
    expect(result.readiness).toBeGreaterThanOrEqual(75);
    expect(result.decision).toBe("push");
    expect(result.calibrating).toBe(false);
  });

  it("forces recover when sleep under 5h", () => {
    const result = computeReadiness({
      ...healthy,
      sleep: { ...healthy.sleep, durationHours: 4.5, sleepDebtHours: 3 },
    });
    expect(result.decision).toBe("recover");
    expect(result.overridesApplied).toContain("sleep_under_5h");
  });

  it("forces recover when HRV <= -20% and RHR elevated", () => {
    const result = computeReadiness({
      ...healthy,
      recovery: {
        hrvMs: 38,
        hrvBaseline30dMs: 50,
        restingHrBpm: 60,
        restingHrBaseline30dBpm: 54,
      },
    });
    expect(result.decision).toBe("recover");
    expect(result.overridesApplied).toContain("hrv_rhr_stress");
  });

  it("forces recover on back-to-back high strain", () => {
    const result = computeReadiness({
      ...healthy,
      load: {
        yesterdayStrain: 16,
        strain7dAvg: 10,
        acuteChronicRatio: 1.4,
      },
      meta: { daysOfHistory: 30, consecutiveHighStrainDays: 2 },
    });
    expect(result.decision).toBe("recover");
    expect(result.overridesApplied).toContain("back_to_back_high_strain");
  });

  it("marks calibrating under 14 days of history", () => {
    const result = computeReadiness({
      ...healthy,
      meta: { daysOfHistory: 5, consecutiveHighStrainDays: 0 },
    });
    expect(result.calibrating).toBe(true);
  });

  it("uses recomp weights 0.35/0.40/0.25", () => {
    const result = computeReadiness(healthy);
    const expected = Math.round(
      result.sleep.score * 0.35 +
        result.recovery.score * 0.4 +
        result.load.score * 0.25
    );
    expect(result.readiness).toBe(expected);
  });
});
```

- [ ] **Step 2: Run to verify fail**

```bash
cd backend && npm test -- tests/scoring/readiness.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement `readiness.ts` + minimal `baselines.ts`**

```ts
// backend/src/scoring/baselines.ts
export function mean(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

export function stddev(values: number[]): number {
  if (values.length < 2) return 0;
  const m = mean(values);
  const v = mean(values.map((x) => (x - m) ** 2));
  return Math.sqrt(v);
}

export function rollingMean(values: number[], window: number): number {
  return mean(values.slice(-window));
}
```

```ts
// backend/src/scoring/readiness.ts
import { scoreLoad } from "./load.js";
import { scoreRecovery } from "./recovery.js";
import { scoreSleep } from "./sleep.js";
import type {
  Decision,
  LoadInput,
  ReadinessResult,
  RecoveryInput,
  SleepInput,
} from "./types.js";

export interface ReadinessInput {
  sleep: SleepInput;
  recovery: RecoveryInput;
  load: LoadInput;
  meta: {
    daysOfHistory: number;
    consecutiveHighStrainDays: number;
  };
}

function decisionFromScore(score: number): Decision {
  if (score >= 75) return "push";
  if (score >= 50) return "maintain";
  return "recover";
}

const DECISION_RANK: Record<Decision, number> = {
  push: 2,
  maintain: 1,
  recover: 0,
};

function moreConservative(a: Decision, b: Decision): Decision {
  return DECISION_RANK[a] <= DECISION_RANK[b] ? a : b;
}

export function computeReadiness(input: ReadinessInput): ReadinessResult {
  const sleep = scoreSleep(input.sleep);
  const recovery = scoreRecovery(input.recovery);
  const load = scoreLoad(input.load);

  const readiness = Math.round(
    sleep.score * 0.35 + recovery.score * 0.4 + load.score * 0.25
  );

  let decision = decisionFromScore(readiness);
  const overridesApplied: string[] = [];

  if (input.sleep.durationHours < 5) {
    decision = moreConservative(decision, "recover");
    overridesApplied.push("sleep_under_5h");
  }

  const hrvDelta =
    (input.recovery.hrvMs - input.recovery.hrvBaseline30dMs) /
    Math.max(input.recovery.hrvBaseline30dMs, 1);
  const rhrElevated =
    input.recovery.restingHrBpm > input.recovery.restingHrBaseline30dBpm * 1.03;
  if (hrvDelta <= -0.2 && rhrElevated) {
    decision = moreConservative(decision, "recover");
    overridesApplied.push("hrv_rhr_stress");
  }

  if (input.meta.consecutiveHighStrainDays >= 2) {
    decision = moreConservative(decision, "recover");
    overridesApplied.push("back_to_back_high_strain");
  }

  // During calibration, never allow Push
  const calibrating = input.meta.daysOfHistory < 14;
  if (calibrating && decision === "push") {
    decision = "maintain";
    overridesApplied.push("calibrating_cap");
  }

  return {
    sleep,
    recovery,
    load,
    readiness,
    decision,
    overridesApplied,
    calibrating,
  };
}
```

- [ ] **Step 4: Run readiness tests**

```bash
cd backend && npm test -- tests/scoring/readiness.test.ts
```

Expected: PASS. If the “strong day → push” case fails, adjust fixture HRV/sleep slightly upward — do **not** weaken override tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/scoring backend/tests/scoring
git commit -m "feat: add composite readiness score and hard overrides"
```

---

### Task 5: Prisma schema + DB client

**Files:**
- Create: `backend/prisma/schema.prisma`
- Create: `backend/src/db.ts`
- Create: `docker-compose.yml` (repo root, Postgres only)

- [ ] **Step 1: Add root `docker-compose.yml`**

```yaml
services:
  db:
    image: postgres:16
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: readiness_coach
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
```

- [ ] **Step 2: Create Prisma schema**

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(cuid())
  createdAt DateTime @default(now())
  goal      String   @default("recomp")
  sleepNeedHours Float @default(8)
  samples   HealthSample[]
  workouts  Workout[]
  dailyScores DailyScore[]
  advisorNotes AdvisorNote[]
  settings  Json?
}

model HealthSample {
  id         String   @id @default(cuid())
  userId     String
  user       User     @relation(fields: [userId], references: [id])
  hkUuid     String
  type       String
  startAt    DateTime
  endAt      DateTime
  value      Float?
  unit       String?
  metadata   Json?
  createdAt  DateTime @default(now())

  @@unique([userId, hkUuid])
  @@index([userId, type, startAt])
}

model Workout {
  id           String   @id @default(cuid())
  userId       String
  user         User     @relation(fields: [userId], references: [id])
  hkUuid       String
  sport        String
  startAt      DateTime
  endAt        DateTime
  durationMin  Float
  avgHrBpm     Float?
  calories     Float?
  strain       Float
  createdAt    DateTime @default(now())

  @@unique([userId, hkUuid])
  @@index([userId, startAt])
}

model DailyScore {
  id            String   @id @default(cuid())
  userId        String
  user          User     @relation(fields: [userId], references: [id])
  date          DateTime @db.Date
  sleepScore    Int
  recoveryScore Int
  loadScore     Int
  readiness     Int
  decision      String
  overrides     Json
  calibrating   Boolean
  drivers       Json
  createdAt     DateTime @default(now())
  updatedAt     DateTime @updatedAt

  @@unique([userId, date])
}

model AdvisorNote {
  id        String   @id @default(cuid())
  userId    String
  user      User     @relation(fields: [userId], references: [id])
  date      DateTime @db.Date
  decision  String
  noteJson  Json
  source    String   // "llm" | "template"
  createdAt DateTime @default(now())

  @@unique([userId, date])
}
```

- [ ] **Step 3: Create `backend/src/db.ts`**

```ts
import { PrismaClient } from "@prisma/client";

export const prisma = new PrismaClient();
```

- [ ] **Step 4: Start DB and migrate**

```bash
docker compose up -d
cd backend
cp .env.example .env
npx prisma migrate dev --name init
```

Expected: migration applied; Prisma client generated.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml backend/prisma backend/src/db.ts backend/.env.example
git commit -m "feat: add postgres schema for health samples and scores"
```

---

### Task 6: Auth middleware + sync API (TDD service)

**Files:**
- Create: `backend/src/middleware/auth.ts`
- Create: `backend/src/services/syncService.ts`
- Create: `backend/src/routes/sync.ts`
- Create: `backend/tests/services/syncService.test.ts`
- Modify: `backend/src/index.ts`

- [ ] **Step 1: Auth middleware**

```ts
// backend/src/middleware/auth.ts
import type { Request, Response, NextFunction } from "express";

export function requireToken(expected: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    const header = req.header("authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token || token !== expected) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }
    next();
  };
}
```

- [ ] **Step 2: Write sync service tests with an in-memory fake (no DB required for pure merge logic)**

Prefer testing pure helpers first:

```ts
// backend/src/services/syncService.ts (helpers + service)
import { z } from "zod";
import { estimateWorkoutStrain } from "../scoring/strain.js";
import { prisma } from "../db.js";

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

export async function applySync(payload: SyncPayload, defaults: {
  restingHrBpm: number;
  maxHrBpm: number;
}) {
  await prisma.user.upsert({
    where: { id: payload.userId },
    create: { id: payload.userId },
    update: {},
  });

  for (const s of payload.samples) {
    await prisma.healthSample.upsert({
      where: { userId_hkUuid: { userId: payload.userId, hkUuid: s.hkUuid } },
      create: {
        userId: payload.userId,
        hkUuid: s.hkUuid,
        type: s.type,
        startAt: new Date(s.startAt),
        endAt: new Date(s.endAt),
        value: s.value ?? null,
        unit: s.unit,
        metadata: s.metadata ?? undefined,
      },
      update: {
        value: s.value ?? null,
        endAt: new Date(s.endAt),
        metadata: s.metadata ?? undefined,
      },
    });
  }

  for (const w of payload.workouts) {
    const strain = estimateWorkoutStrain({
      durationMin: w.durationMin,
      avgHrBpm: w.avgHrBpm ?? 0,
      restingHrBpm: defaults.restingHrBpm,
      maxHrBpm: defaults.maxHrBpm,
    });
    await prisma.workout.upsert({
      where: { userId_hkUuid: { userId: payload.userId, hkUuid: w.hkUuid } },
      create: {
        userId: payload.userId,
        hkUuid: w.hkUuid,
        sport: w.sport,
        startAt: new Date(w.startAt),
        endAt: new Date(w.endAt),
        durationMin: w.durationMin,
        avgHrBpm: w.avgHrBpm,
        calories: w.calories,
        strain,
      },
      update: {
        durationMin: w.durationMin,
        avgHrBpm: w.avgHrBpm,
        calories: w.calories,
        strain,
        endAt: new Date(w.endAt),
      },
    });
  }

  return { ok: true as const, samples: payload.samples.length, workouts: payload.workouts.length };
}
```

- [ ] **Step 3: Unit-test payload validation**

```ts
// backend/tests/services/syncService.test.ts
import { describe, expect, it } from "vitest";
import { syncPayloadSchema } from "../../src/services/syncService.js";

describe("syncPayloadSchema", () => {
  it("accepts a minimal valid payload", () => {
    const parsed = syncPayloadSchema.parse({
      userId: "user_1",
      samples: [
        {
          hkUuid: "abc",
          type: "hrv_sdnn",
          startAt: "2026-07-09T08:00:00.000Z",
          endAt: "2026-07-09T08:00:00.000Z",
          value: 48,
          unit: "ms",
        },
      ],
      workouts: [],
    });
    expect(parsed.samples).toHaveLength(1);
  });

  it("rejects unknown sample types", () => {
    expect(() =>
      syncPayloadSchema.parse({
        userId: "user_1",
        samples: [
          {
            hkUuid: "x",
            type: "steps",
            startAt: "2026-07-09T08:00:00.000Z",
            endAt: "2026-07-09T08:00:00.000Z",
            value: 1,
          },
        ],
        workouts: [],
      })
    ).toThrow();
  });
});
```

- [ ] **Step 4: Wire route**

```ts
// backend/src/routes/sync.ts
import { Router } from "express";
import { applySync, syncPayloadSchema } from "../services/syncService.js";

export const syncRouter = Router();

syncRouter.post("/", async (req, res) => {
  const parsed = syncPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  try {
    const result = await applySync(parsed.data, {
      restingHrBpm: 55,
      maxHrBpm: 190,
    });
    res.json(result);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "sync_failed" });
  }
});
```

Update `index.ts` to `loadEnv`, mount `requireToken(env.API_TOKEN)` on `/v1/*`, and `app.use("/v1/sync", syncRouter)`.

- [ ] **Step 5: Manual smoke (optional if DB up)**

```bash
curl -s -X POST localhost:4000/v1/sync \
  -H "Authorization: Bearer dev-token-change-me" \
  -H "Content-Type: application/json" \
  -d '{"userId":"user_1","samples":[],"workouts":[]}'
```

Expected: `{"ok":true,"samples":0,"workouts":0}`

- [ ] **Step 6: Commit**

```bash
git add backend/src backend/tests
git commit -m "feat: add authenticated health sync endpoint"
```

---

### Task 7: Today service — aggregate metrics → score → persist

**Files:**
- Create: `backend/src/services/todayService.ts`
- Create: `backend/src/routes/today.ts`
- Create: `backend/src/routes/sleep.ts`
- Create: `backend/src/routes/train.ts`
- Create: `backend/src/routes/body.ts`
- Create: `backend/tests/fixtures/sampleDay.ts`

- [ ] **Step 1: Implement aggregation helpers in `todayService.ts`**

Responsibilities:
- Load last night sleep samples → duration, restorative hours, debt, consistency
- Load latest HRV / RHR vs 30d means (`rollingMean`)
- Load workouts → yesterday strain, 7d avg, 7d/28d acute:chronic, consecutive high-strain days (strain ≥ 14)
- Call `computeReadiness`
- Upsert `DailyScore` for today (UTC date or user-local date; v1 use America/New_York fixed or store timezone on user later — **v1: use `YYYY-MM-DD` from client query `?date=` defaulting to server local date**)

Return shape:

```ts
export interface TodayResponse {
  date: string;
  readiness: number;
  decision: "push" | "maintain" | "recover";
  calibrating: boolean;
  pillars: {
    sleep: { score: number; drivers: string[] };
    recovery: { score: number; drivers: string[] };
    load: { score: number; drivers: string[] };
  };
  overridesApplied: string[];
  confidence: "high" | "low";
  missing: string[];
}
```

If sleep or HRV missing → `confidence: "low"`, add to `missing`, still compute with conservative defaults (sleep duration 0 → override recover; HRV baseline = current if no history).

- [ ] **Step 2: Routes**

- `GET /v1/today?userId=&date=`
- `GET /v1/sleep?userId=&days=30`
- `GET /v1/train?userId=&days=28`
- `GET /v1/body?userId=&days=30`

Each requires bearer auth.

- [ ] **Step 3: Seed fixture script (dev)**

Add `backend/scripts/seedDemo.ts` that inserts a user + synthetic samples so web/iOS can demo without Watch.

- [ ] **Step 4: Manual verify**

```bash
npm run dev
curl -s localhost:4000/v1/today?userId=user_1 -H "Authorization: Bearer dev-token-change-me" | jq .
```

Expected: JSON with `decision` and pillar scores.

- [ ] **Step 5: Commit**

```bash
git add backend
git commit -m "feat: compute and expose today readiness payload"
```

---

### Task 8: Advisor service (hybrid LLM) + Ask Coach

**Files:**
- Create: `backend/src/services/llmClient.ts`
- Create: `backend/src/services/advisorService.ts`
- Create: `backend/src/routes/coach.ts`
- Create: `backend/tests/services/advisorService.test.ts`

- [ ] **Step 1: Write failing tests for decision lock + template fallback**

```ts
// backend/tests/services/advisorService.test.ts
import { describe, expect, it } from "vitest";
import {
  buildTemplateNote,
  enforceDecisionLock,
  type AdvisorNoteBody,
} from "../../src/services/advisorService.js";

describe("enforceDecisionLock", () => {
  it("keeps recover even if model text says push", () => {
    const body: AdvisorNoteBody = {
      decision: "push",
      why: ["made up"],
      prescription: "PR day",
      ifIgnored: "whatever",
    };
    const locked = enforceDecisionLock("recover", body);
    expect(locked.decision).toBe("recover");
  });
});

describe("buildTemplateNote", () => {
  it("returns strict structure without LLM", () => {
    const note = buildTemplateNote({
      decision: "maintain",
      drivers: ["HRV -12% vs baseline", "Sleep debt 1.6h"],
    });
    expect(note.decision).toBe("maintain");
    expect(note.why.length).toBeGreaterThan(0);
    expect(note.prescription.length).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: Implement advisor helpers + service**

```ts
// backend/src/services/advisorService.ts
export type Decision = "push" | "maintain" | "recover";

export interface AdvisorNoteBody {
  decision: Decision;
  why: string[];
  prescription: string;
  ifIgnored: string;
}

const RANK: Record<Decision, number> = { push: 2, maintain: 1, recover: 0 };

export function enforceDecisionLock(
  locked: Decision,
  body: AdvisorNoteBody
): AdvisorNoteBody {
  const decision = RANK[body.decision] < RANK[locked] ? body.decision : locked;
  // Never allow more aggressive than locked
  const finalDecision = RANK[decision] <= RANK[locked] ? decision : locked;
  return { ...body, decision: finalDecision };
}

export function buildTemplateNote(input: {
  decision: Decision;
  drivers: string[];
}): AdvisorNoteBody {
  const prescription =
    input.decision === "push"
      ? "Hard session allowed. Keep form quality high; stop if performance falls off a cliff."
      : input.decision === "maintain"
        ? "Train, but cap intensity (RPE ≤7). No PR attempts. Prefer moderate lift or Zone 2."
        : "Recover. Walk, mobility, or full rest. Do not stack another hard session.";

  const ifIgnored =
    input.decision === "recover"
      ? "Ignore this and you will dig a deeper hole into the next 48 hours."
      : input.decision === "maintain"
        ? "Ignore this and you risk turning a maintain day into forced recovery tomorrow."
        : "Ignore recovery signals later in the week if you blow past technique for ego PRs.";

  return {
    decision: input.decision,
    why: input.drivers.slice(0, 4),
    prescription,
    ifIgnored,
  };
}
```

Implement `generateAdvisorNote(today, llm?)`:
1. Build metric summary object (scores, drivers, overrides, missing).
2. If no `LLM_API_KEY`, return template + `source: "template"`.
3. Else call `llmClient.chat` with system prompt: strict advisor, JSON only matching `AdvisorNoteBody`, must use provided decision.
4. Parse JSON → `enforceDecisionLock` → persist `AdvisorNote`.

Ask Coach: `POST /v1/coach/ask` `{ userId, question }` loads today’s locked decision + summary; LLM answers; if model suggests harder training than locked decision, append correction server-side.

- [ ] **Step 3: `llmClient.ts`**

Minimal OpenAI-compatible `POST /chat/completions` fetch wrapper with timeout + error throw.

- [ ] **Step 4: Run tests**

```bash
cd backend && npm test -- tests/services/advisorService.test.ts
```

Expected: PASS

- [ ] **Step 5: Wire `GET /v1/today` to include `advisor` field (generate-on-read once per day)**

- [ ] **Step 6: Commit**

```bash
git add backend
git commit -m "feat: add hybrid strict advisor and ask-coach API"
```

---

### Task 9: Light web dashboard

**Files:**
- Create: `web/package.json`, `web/vite.config.ts`, `web/index.html`, `web/src/*`

- [ ] **Step 1: Scaffold Vite React TS app in `web/`**

```bash
cd /agent/repos/readiness-coach
npm create vite@latest web -- --template react-ts
cd web && npm install
```

- [ ] **Step 2: `web/src/api.ts`**

Fetch helpers using `VITE_API_URL` + `VITE_API_TOKEN`.

- [ ] **Step 3: `TodayPage`**

Show readiness number, decision color, three pillars, advisor note blocks (`why`, `prescription`, `ifIgnored`), last sync time if present. Match the §1 wireframe hierarchy — not a dense dashboard.

- [ ] **Step 4: Run locally against backend**

```bash
# terminal 1
cd backend && npm run dev
# terminal 2
cd web && VITE_API_URL=http://localhost:4000 VITE_API_TOKEN=dev-token-change-me npm run dev
```

Expected: Today page renders demo user data.

- [ ] **Step 5: Commit**

```bash
git add web
git commit -m "feat: add light web today dashboard"
```

---

### Task 10: iOS app scaffold + API client (Mac)

**Files:**
- Create Xcode project `ios/ReadinessCoach`

- [ ] **Step 1: Create new iOS App (SwiftUI, Swift, iOS 17)** named ReadinessCoach

- [ ] **Step 2: Enable HealthKit capability; add usage strings to Info.plist**

```xml
<key>NSHealthShareUsageDescription</key>
<string>Readiness Coach reads your heart rate, HRV, sleep, and workouts to compute readiness and coaching.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Readiness Coach does not write health data.</string>
```

- [ ] **Step 3: `APIClient.swift`**

```swift
import Foundation

struct APIClient {
  var baseURL: URL
  var token: String
  var userId: String

  func getToday() async throws -> TodayDTO {
    var req = URLRequest(url: baseURL.appendingPathComponent("v1/today"))
    // add userId query
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(TodayDTO.self, from: data)
  }
}
```

Define `TodayDTO` matching backend JSON (decision as string).

- [ ] **Step 4: Settings storage** via `UserDefaults` / `@AppStorage` for `apiBaseURL`, `apiToken`, `userId`.

- [ ] **Step 5: Commit Xcode project** (after verifying it builds on simulator without HealthKit calls yet)

```bash
git add ios
git commit -m "feat: scaffold iOS app and API client"
```

---

### Task 11: HealthKitService + sync from iPhone (Mac + device)

**Files:**
- Create: `ios/ReadinessCoach/Services/HealthKitService.swift`
- Create: `ios/ReadinessCoach/Services/SyncService.swift`
- Create: `ios/ReadinessCoach/Views/OnboardingView.swift`

- [ ] **Step 1: Request read auth for**

`heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`, `sleepAnalysis`, `workoutType`

- [ ] **Step 2: Query samples since `lastSyncAt`** (store locally). Map to backend sync payload types/ISO8601 dates. Sleep stages → metadata + duration aggregation can be refined server-side from interval samples.

- [ ] **Step 3: `SyncService.syncNow()`** posts to `/v1/sync`, then fetches `/v1/today`.

- [ ] **Step 4: Onboarding** — explain permissions → request HealthKit → save API settings → first sync.

- [ ] **Step 5: Device test**

On physical iPhone with Watch data: grant permissions, sync, confirm backend received samples (`prisma studio` or SQL count).

- [ ] **Step 6: Commit**

```bash
git add ios
git commit -m "feat: sync HealthKit samples to readiness API"
```

---

### Task 12: iOS Today + detail tabs + Ask Coach

**Files:**
- Create: Today/Sleep/Train/Body/AskCoach/Settings views + `TabView`

- [ ] **Step 1: `TodayView`** — readiness, decision, pillars, advisor card, button to Ask Coach. Show calibrating banner when `calibrating == true`. Show missing-data warning when `confidence == low`.

- [ ] **Step 2: Detail tabs** call `/v1/sleep`, `/v1/train`, `/v1/body` and render simple charts (Swift Charts).

- [ ] **Step 3: `AskCoachView`** — text field → `POST /v1/coach/ask` → show answer; always display locked decision chip so user sees constraint.

- [ ] **Step 4: Settings** — sync now, token/URL, delete local settings, link to account data deletion endpoint `DELETE /v1/user` (add thin route that deletes user cascade).

- [ ] **Step 5: Manual acceptance checklist**

1. Morning open → Today score + decision  
2. Advisor cites real deltas  
3. Ask Coach does not contradict Recover  
4. Web shows same Today  

- [ ] **Step 6: Commit**

```bash
git add ios backend
git commit -m "feat: ship iOS today experience with strict advisor"
```

---

## Plan self-review

### Spec coverage

| Spec item | Task(s) |
|-----------|---------|
| HealthKit sync HR/HRV/RHR/sleep/workouts | 6, 11 |
| Personal baselines 14/30d | 4 (`baselines.ts`), 7 |
| Readiness weights + bands | 4 |
| Hard overrides | 4 |
| Hybrid cloud advisor + lock | 8 |
| Ask Coach | 8, 12 |
| Tabs Today/Sleep/Train/Body | 7, 9, 12 |
| Backend + light web | 5–9 |
| Privacy / token auth / delete | 6, 12 |
| Calibrating mode | 4, 7, 12 |
| Error/missing data behavior | 7, 8, 12 |
| No Watch app / no local LLM | respected (non-goals) |

### Placeholder scan

No TBD implementation steps; open product-name / hosting choices remain in spec “Open decisions” and do not block coding.

### Type consistency

- Decision union: `"push" | "maintain" | "recover"` everywhere (API + scoring + advisor).
- Pillar scores: `{ score, drivers }` from scoring through Today response.
- Sync sample types enum aligned between Zod schema and iOS mapper.

---

## Parallelization note

Safe to split across agents after Task 1:
- Agent A: Tasks 2–4 (scoring, pure TDD)
- Agent B: Tasks 5–6 (DB + sync) after Task 1
- Then join at Task 7
- Web (9) after Task 7–8
- iOS (10–12) after Task 8 API contract is stable
