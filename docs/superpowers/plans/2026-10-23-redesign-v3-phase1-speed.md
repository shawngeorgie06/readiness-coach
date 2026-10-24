# Redesign v3 · Phase 1 (Speed) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every section open instantly from cache and refresh quietly, with no visual change, and prove it with before/after numbers.

**Architecture:** On the server we add request timing, a per-user in-process memo of `getToday`, an additive `baselines` field, a `tz` parameter on history, SQL aggregation for `/v1/body`, and `ETag` plus `Cache-Control: private, no-store` on reads. On iOS, one `@Observable` `AppStore` owns every screen's data as `Resource<T>` values. The store is backed by a protected disk cache, revalidates with `If-None-Match`, and prefetches the pillar tabs after Today loads. `SyncService` keeps sync and upload and writes Today into the store. The pillar views stop owning network state.

**Tech Stack:** Node 20 / TypeScript / Express 4 / Prisma 6 / PostgreSQL 16 / Vitest; SwiftUI on iOS 17 (`Observation`, `OSSignposter`) / XCTest.

**Spec:** `docs/superpowers/specs/2026-10-23-redesign-v3-performance-design.md` (Phase 1 in "Phasing"; "Data and performance architecture"; "Performance targets").

**Branch:** work in the worktree `/Users/shawngeorgie/readiness-coach-v3` on a branch `redesign-v3-phase1` cut from `redesign-v3-spec` (which holds the spec and this plan). One PR to `main`. Merging to `main` auto-deploys the backend to Family Host, so the PR merges only after the gates in Task 12.

## Global Constraints

- **Additive API only.** No field the current app reads is removed or retyped. New query params default to today's behavior. The build already on Shawn's phone must keep working.
- **Scoring is unchanged.** Do not change `computeReadiness`, pillar formulas, cutoffs (push ≥75, maintain ≥50) or the decision lock. Every existing scoring test must pass unmodified.
- **No visual change in Phase 1.** Views keep their current layout and styling. Only where data comes from changes.
- **Cached health data on disk** uses `.completeFileProtection` and `isExcludedFromBackup = true`, and is cleared on sign-out and account deletion.
- **Read endpoints** send `Cache-Control: private, no-store` and a weak `ETag`, and answer `If-None-Match` with 304.
- **Timing log:** `METHOD /path STATUS Nms`, with the path taken without its query string. Never log user IDs, tokens, query strings or bodies.
- **iOS timeouts:** reads use a 15 s request timeout. Sync uploads keep their 120 s per-request timeout. A read retries once, immediately, only on a transport error. No `wakeServer`, no fixed 2.5 s sleeps.
- **Revalidation:** a resource refetches on appear only if it is missing, older than 300 s, from a different local day, or older than the last sample upload.
- **Memo:** `getToday` entries expire at the earliest of 10 min, the end of that date's sleep window (if the night is still in progress), any sync for the user, or account deletion. Keep at most 500 entries, evicting least recently used.
- **Family Host runs one API instance.** `family-host inspect readiness-coach-api` shows no replica setting. If that changes, the memo must fall back to TTL only.
- **Checks:**
  - Backend: `cd backend && npx tsc --noEmit && npm test && npm run test:integration`. Integration tests need `TEST_DATABASE_URL` pointing at a database whose name ends in `_test`.
  - iOS: `xcodebuild test -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- **Drop rule (from the spec):** if a fix's measured interval is already under its target, or the fix would cut less than 10% of the measured time, skip it and record the measurement in `docs/perf/2026-10-23-phase1.md`.
- New Swift files go under `ios/ReadinessCoach/…`. The project uses synchronized folder groups, so no `project.pbxproj` edits are needed.

## Review Focus

1. **Account switch or sign-out.** User A's cached Recovery, Sleep or Train data must never appear for user B, even for one frame. Task 8 has `testCacheFromAnotherUserIsIgnored`. Task 10 has `testResetClearsMemoryAndDisk`.
2. **App left open across midnight.** Yesterday's cached Today and pillar data must revalidate when the local day changes, even when they are less than 5 minutes old. Task 8 has `testDifferentLocalDayNeedsRevalidation`.
3. **ETag without a body.** If the cache file was wiped, or the value failed to decode, the app must not send `If-None-Match`. Otherwise it gets a 304 with nothing to show. Task 9 has `testNoIfNoneMatchWithoutCachedValue`.
4. **Sync landing while Today is being computed.** A `getToday` that started before a sync and finished after its invalidation must not be stored in the memo. Task 4 has `does not store a result computed across an invalidation`.
5. **Launch with the network off.** Cached tabs render immediately. Today shows the existing stale/offline status line. No tab spins forever, and a refresh error never replaces cached content. Task 10 has `testErrorKeepsCachedValue`. Task 12 covers it in the device check.

---

### Task 1: Request timing log, `Cache-Control` and ETag on reads

**Files:**
- Create: `backend/src/middleware/timing.ts`
- Modify: `backend/src/app.ts` (register timing first after `helmet`; set read headers on `/v1` GETs)
- Test: `backend/tests/middleware/timing.test.ts`, `backend/tests/integration/api.test.ts` (add cases)

**Interfaces:**
- Produces: `createRequestTimer(log?: (line: string) => void, now?: () => number): RequestHandler` (defaults: `console.log`, `performance.now`).

- [ ] **Step 1: Write the failing tests**

```ts
// tests/middleware/timing.test.ts
it("logs method, path without query, status and whole ms", async () => {
  const lines: string[] = [];
  let t = 1000;
  const app = express();
  app.use(createRequestTimer((l) => lines.push(l), () => (t += 12.4)));
  app.get("/v1/today", (_q, r) => r.json({ ok: true }));
  await request(app).get("/v1/today?userId=secret-user&tz=-240");
  expect(lines).toEqual(["GET /v1/today 200 12ms"]);
  expect(lines.join()).not.toContain("secret-user");
});
```

```ts
// tests/integration/api.test.ts (after the existing sync setup)
it("returns private no-store, a weak ETag, and 304 on If-None-Match", async () => {
  const first = await request(app).get(`/v1/today?date=${date}`).set("Authorization", authorization);
  expect(first.headers["cache-control"]).toBe("private, no-store");
  expect(first.headers.etag).toMatch(/^W\//);
  const second = await request(app).get(`/v1/today?date=${date}`)
    .set("Authorization", authorization).set("If-None-Match", first.headers.etag);
  expect(second.status).toBe(304);
});
```

- [ ] **Step 2: Run them and confirm they fail.** Run `npx vitest run tests/middleware/timing.test.ts`; it should fail on the missing module. Then run `npm run test:integration -- -t "no-store"`; the cache-control assertion should fail.
- [ ] **Step 3: Implement.** Log on `res.on("finish")` using `req.originalUrl.split("?")[0]` and `Math.round(now() - start)`. In `app.ts`, add a `/v1` middleware after `requireSession` that sets `Cache-Control: private, no-store` for `GET`. Leave Express's default weak `etag` setting on, since `res.json` already answers fresh requests with 304.
- [ ] **Step 4: Re-run both tests and confirm they pass.** Then run the full backend check from Global Constraints.
- [ ] **Step 5: Commit** with message `Log request timing and send ETag/no-store on reads`.

### Task 2: Production-shaped seed and the "before" measurement

**Files:**
- Create: `backend/scripts/seedPerf.ts`, `backend/scripts/measureApi.ts`, `docs/perf/2026-10-23-phase1.md`
- Modify: `backend/package.json` (scripts `seed:perf`, `measure:api`)

**Interfaces:**
- Produces:
  - `npm run seed:perf`: seeds user `perf-user` with 90 days ending today. It writes one `heart_rate` sample every 5 minutes, 6 `hrv_sdnn` and 1 `resting_heart_rate` per day, a staged night of about 7 h (core/deep/rem/awake metadata like `seedDemo.ts`), and 4 workouts per week. It refuses to run unless `DATABASE_URL`'s database name ends in `_test` or `_perf`.
  - `npm run measure:api -- --base http://127.0.0.1:3000 --token <API_TOKEN> --runs 30`: prints a table of endpoint, p50, p95 and bytes. It covers `/v1/today`, `/v1/body?days=30`, `/v1/sleep?days=7|30|90`, `/v1/train?days=28` and `/v1/history?days=30|90`, all with `tz=-240`.

- [ ] **Step 1: Write both scripts.** For the seed, reuse the `upsertSample` shape from `seedDemo.ts` but use `createMany({ skipDuplicates: true })` in batches of 5,000. `measureApi.ts` uses `fetch` with `Authorization: Bearer`, does one warm-up call per endpoint, then runs N sequential timed calls.
- [ ] **Step 2: Seed a local `readiness_coach_perf` database and start the API against it.** Use `API_TOKEN_USER_ID=perf-user` and an empty `LLM_API_KEY`, so the advisor uses its template.
- [ ] **Step 3: Record the "before" numbers.** Run `npm run measure:api` and paste the table into `docs/perf/2026-10-23-phase1.md` under "Server, before". Also record the `/v1/body` and `/v1/sleep?days=90` byte counts.
- [ ] **Step 4: Check the sleep-trim gate.** If `/v1/sleep?days=90` has p95 ≥ 300 ms or is ≥ 200 KB, stop and report it so a sleep-timeline task can be added to the plan. Otherwise write "Sleep trim not needed: <numbers>" in the doc.
- [ ] **Step 5: Commit** with message `Add production-shaped perf seed and API measurement`.

### Task 3: Aggregate `/v1/body` in SQL

**Files:**
- Modify: `backend/src/services/todayService.ts` (`getBodyDetails`; keep `aggregateBodyDaily` exported for the parity test)
- Test: `backend/tests/integration/bodyAggregation.test.ts`

**Interfaces:**
- Produces: `aggregateBodyDailySql(userId: string, start: Date, end: Date, tzOffsetMinutes: number): Promise<BodyDailyBucket[]>`. `getBodyDetails` returns `{ days, daily: await aggregateBodyDailySql(...) }`, so the response shape is unchanged.

- [ ] **Step 1: Write the failing parity test.** Seed about 3 days of mixed `hrv_sdnn`, `resting_heart_rate` and `heart_rate` samples with distinct timestamps. Include one at 23:30 local and one at 00:10 local for `tz=-240`, and one sample with `value: null`.

```ts
it("matches the JS aggregation exactly for a non-UTC tz", async () => {
  const rows = await prisma.healthSample.findMany({ where: { userId }, orderBy: { startAt: "asc" } });
  const js = aggregateBodyDaily(rows.filter((r) => types.includes(r.type)), -240);
  const sql = await aggregateBodyDailySql(userId, start, end, -240);
  expect(sql).toEqual(js);
});
```

- [ ] **Step 2: Run it and confirm it fails.** Run `npm run test:integration -- -t "JS aggregation"`. It should fail because `aggregateBodyDailySql` is not exported.
- [ ] **Step 3: Implement it with one `prisma.$queryRaw`.** The spec suggests `DISTINCT ON` for latest; `array_agg(… ORDER BY … DESC)[1]` does the same in one pass, and either is fine if parity holds. The query below lets Postgres do the grouping. Then map each row through the existing `round(…, 2)` for `min`, `avg`, `max` and `latest`.

```sql
SELECT type,
       to_char("startAt" + make_interval(mins => ${Math.round(tz)}), 'YYYY-MM-DD') AS date,
       min(value) AS min, avg(value) AS avg, max(value) AS max, count(*)::int AS count,
       (array_agg(value ORDER BY "startAt" DESC))[1] AS latest
FROM "HealthSample"
WHERE "userId" = ${userId} AND type IN ('hrv_sdnn','resting_heart_rate','heart_rate')
  AND "startAt" >= ${start} AND "startAt" < ${end} AND value IS NOT NULL
GROUP BY 1, 2 ORDER BY 1, 2
```

- [ ] **Step 4: Re-run the parity test and the full backend check, and confirm they pass.**
- [ ] **Step 5: Commit** with message `Aggregate body metrics in SQL instead of Node`.

### Task 4: Memoize `getToday` with full invalidation

**Files:**
- Create: `backend/src/services/todayMemo.ts`
- Modify:
  - `backend/src/services/todayService.ts` (`getToday` wraps the memo; export `invalidateTodayMemo(userId)`)
  - `backend/src/routes/sync.ts` (invalidate after a successful `applySync`)
  - `backend/src/routes/user.ts` (invalidate after `deleteUser`)
- Test: `backend/tests/services/todayMemo.test.ts`, `backend/tests/integration/api.test.ts` (add a case)

**Interfaces:**
- Produces:
  - `createTodayMemo<V>(opts?: { ttlMs?: number; maxEntries?: number; now?: () => number })`, returning `{ get(userId, date, tz): V | undefined; set(userId, date, tz, value: V, expiresAt: number): void; generation(userId): number; invalidateUser(userId): void; clear(): void }`. Defaults are `ttlMs` 600 000, `maxEntries` 500 and `Date.now`.
  - `invalidateTodayMemo(userId: string): void`
  - `resetTodayMemoForTests(): void`

- [ ] **Step 1: Write the failing unit tests.** Each one uses a fake `now`.
  - `returns a hit before expiry and a miss at expiresAt`
  - `invalidateUser drops only that user's entries and bumps generation`
  - `evicts the least recently used entry beyond maxEntries` (use maxEntries 2: set a, set b, get a, set c, so b is gone)
  - `expires at the end of the sleep window while the night is in progress`: store at 5 min before the window end; expect a hit 1 min before the end and a miss at the end, so the window decides, not the 10 min TTL.
  - `does not store a result computed across an invalidation` (read `generation`, call `invalidateUser`, then `getToday`'s store step must skip because the generation changed). Test this through an exported `storeIfCurrent(memo, key, gen, value, expiresAt)` helper or through `getToday` with a stubbed compute.
- [ ] **Step 2: Run them and confirm they fail.** Run `npx vitest run tests/services/todayMemo.test.ts`.
- [ ] **Step 3: Implement.**
  - The memo is a `Map` keyed `${userId}|${date}|${tz}`, plus a per-user generation counter. A `get` re-inserts the key to keep LRU order.
  - In `getToday`, normalize the date with `parseRequestedDate`. On a hit, return it. Otherwise read the generation, compute as today, and store only if the generation is unchanged.
  - Set `expiresAt = min(now + ttl, nightEnd)`, where `nightEnd = sleepWindowForDate(dateStart(date), tz).end` if `now < nightEnd`.
  - Call `invalidateTodayMemo` in `sync.ts` right after `applySync` resolves, and in `user.ts` right after `deleteUser` resolves.
  - `sleepNeedHours` has no write path in the API, so it needs no hook. Note this in a code comment on the memo.
- [ ] **Step 4: Write the integration test** `sync invalidates the memoized Today`. GET Today, then POST a sync with a new `hrv_sdnn` for `date` at a higher value, then GET Today again. Expect `pillars.recovery.score` to change. Add `account deletion invalidates the memoized Today`: GET Today, DELETE the user, then confirm the memo holds no entry for that user (`memo.get` is `undefined`). Call `resetTodayMemoForTests()` in `beforeEach`.
- [ ] **Step 5: Run the unit and integration tests and confirm they pass.** Then run the full backend check.
- [ ] **Step 6: Commit** with message `Memoize getToday per user, date and tz with sync/delete invalidation`.

### Task 5: Additive `baselines` on `/v1/today`

**Files:**
- Create: `backend/src/services/todayBaselines.ts`
- Modify:
  - `backend/src/services/todayService.ts` (`TodayResponse.baselines`)
  - `computeScore`: widen the sleep sample lookback from 7 to 31 days before `sleepWindow.start`, and build baselines from values it already computes. Scoring inputs stay unchanged.
- Test: `backend/tests/services/todayBaselines.test.ts`, `backend/tests/integration/api.test.ts` (add a case)

**Interfaces:**
- Produces:

```ts
export interface MetricBaseline {
  today: number | null;
  baseline30d: number | null;
  neutralBand: { low: number; high: number } | null;
  /** Oldest first, exactly 14 entries, null for days without data. */
  recent14d: Array<number | null>;
  /** Which way is good for this metric; "none" = only leaving the band is notable. */
  goodDirection: "up" | "down" | "none";
}
export interface TodayBaselines { hrv: MetricBaseline; restingHr: MetricBaseline; sleepHours: MetricBaseline; load7d: MetricBaseline }
export function buildBaselines(input: {
  hrvToday: number | null; hrvBaseline: number | null; hrvDaily14: Array<number | null>;
  rhrToday: number | null; rhrBaseline: number | null; rhrDaily14: Array<number | null>;
  sleepToday: number | null; sleepPrior30: number[]; sleepDaily14: Array<number | null>; sleepNeedHours: number;
  load7dToday: number; load28dAvg: number; strain28d: number[];
}): TodayBaselines
```

- **Band and series rules.** These are my calls, taken from the existing driver thresholds:
  - **HRV:** band is baseline ±5% (the "above/below your normal" cut). Good direction is up.
  - **Resting HR:** band is baseline ±3% (the "elevated" cut). Good direction is down.
  - **Sleep:** baseline is the mean of the prior 30 nights with more than 0 h. The band is ±10% of the user's nightly target (`sleepNeedHours`), not of that average, because the sleep score's duration driver fires below 0.9 × target; centring the band on the average could show a night as normal while the driver calls it short. Good direction is up.
  - **Load:** `today` is the 7-day average strain and `baseline30d` is the 28-day average (the scoring's chronic window). The band is 0.7×–1.3× of the baseline, the ACR cuts in `load.ts`, and good direction is `"none"`. `recent14d[i]` is the 7-day rolling average ending on each of the last 14 days of `strain28d`.
  - **Null bands:** the HRV, resting HR and load bands are `null` whenever their baseline is `null`. The sleep band follows the target, so it stays set when the sleep baseline is `null`.
  - **Rounding:** all numbers are rounded to 2 dp.
  - **HRV and RHR daily series:** use `latestInWindow` per UTC day, matching how `computeScore` picks today's value. The sleep series uses `sleepHistory(…, 14, tz)` durations, with `0` becoming `null`.

- [ ] **Step 1: Write the failing unit tests** in `todayBaselines.test.ts`.
  - `hrv band is ±5% of baseline and direction up`: with `hrvBaseline: 60`, expect `neutralBand` `{ low: 57, high: 63 }` and `goodDirection` `"up"`.
  - `rhr band is ±3% and direction down`: with `rhrBaseline: 50`, expect the band `{ low: 48.5, high: 51.5 }`.
  - `null baseline gives null band`.
  - `sleep baseline ignores zero nights`: with `sleepPrior30: [7, 0, 8]`, expect `baseline30d` 7.5.
  - `sleep band is ±10% of the scoring target, not the 30-day average`: with `sleepPrior30: [5, 5]`, `sleepToday: 6` and `sleepNeedHours: 8`, expect `baseline30d` 5 and band `{ low: 7.2, high: 8.8 }`, so tonight's 6 h falls below the band.
  - `sleep band comes from the target even without history`: with `sleepPrior30: []` and `sleepNeedHours: 7.5`, expect `baseline30d` `null` and band `{ low: 6.75, high: 8.25 }`.
  - `load7d series is a 7-day rolling mean`: `strain28d` is 21 zeros followed by 7 sevens. The last `recent14d` entry is 7. `recent14d[7]`, the window ending on the first 7 (six days before the final day), is 1. `recent14d[6]`, seven days before the final day, is 0.
  - `recent14d always has 14 entries`.
- [ ] **Step 2: Run them and confirm they fail.** Run `npx vitest run tests/services/todayBaselines.test.ts`.
- [ ] **Step 3: Implement** `buildBaselines` and wire it into `computeScore`'s returned response. The pending-night fallback already returns the previous day's full response, so baselines follow it.
- [ ] **Step 4: Write the integration test** `baselines agree with the recovery driver`. Using the existing sync fixture, compute `Math.round(baselines.hrv.baseline30d)`. Expect it to equal the integer parsed from the HRV driver's `detail` ("30-day average of Nms"). Also expect `baselines.hrv.recent14d.length` to be 14.
- [ ] **Step 5: Run the tests and the full backend check, and confirm they pass.** Every existing scoring test must pass unmodified.
- [ ] **Step 6: Commit** with message `Add additive baselines (today, 30d normal, band, 14-day series) to /v1/today`.

### Task 6: History uses the caller's tz

**Files:**
- Modify:
  - `backend/src/services/todayService.ts`: add a `tzOffsetMinutes = 0` parameter to `getReadinessHistory` and pass it to the backfill `computeScore`.
  - `backend/src/routes/history.ts`: parse `tz` exactly like `today.ts`.
- Test: `backend/tests/integration/api.test.ts` (add a case)

**Interfaces:**
- Produces: `getReadinessHistory(userId: string, days: number, requestedDate?: string, tzOffsetMinutes?: number)`

- [ ] **Step 1: Write the failing test** `history and today agree for tz=-240`. Sync a night that falls on different days under UTC noon and EDT noon. Use the 7h52 Watch night shape from `todayService.test.ts`: 05:00–12:52Z. Then:

```ts
const today = await request(app).get(`/v1/today?date=${date}&tz=-240`).set("Authorization", authorization);
await prisma.dailyScore.deleteMany({}); // force the history backfill path
const history = await request(app).get(`/v1/history?days=1&date=${date}&tz=-240`).set("Authorization", authorization);
expect(history.body.data.at(-1).readiness).toBe(today.body.readiness);
```

- [ ] **Step 2: Run it and confirm it fails.** The backfill currently computes at tz 0.
- [ ] **Step 3: Implement it, then re-run the test and the full backend check, and confirm they pass.**
- [ ] **Step 4: Commit** with message `Score History backfill in the caller's timezone`.

### Task 7: iOS measurement hooks and the "before" app numbers

**Files:**
- Create: `ios/ReadinessCoach/Services/PerfSignpost.swift`, `ios/Fixtures/server.mjs`, `ios/Fixtures/README.md`
- Modify:
  - `ios/ReadinessCoach/ReadinessCoachApp.swift`: begin the `LaunchToToday` interval in `ReadinessCoachApp.init` when not a unit-test host.
  - `ios/ReadinessCoach/Views/RootView.swift`: begin `TabSwitch` on `tabs.selection` change.
  - `TodayView`, `BodyView`, `SleepView`, `TrainView`: end the interval when content, not a spinner, first appears.
  - `docs/perf/2026-10-23-phase1.md`

**Interfaces:**
- Produces:
  - `enum PerfSignpost { static func beginLaunch(); static func endLaunchIfNeeded(); static func beginTabSwitch(to tab: String); static func endTabSwitchIfNeeded(tab: String) }`. It uses `OSSignposter(subsystem: "com.readinesscoach.ReadinessCoach", category: "perf")` and logs `perf <name> <ms>ms` through `Logger` on the same subsystem, so `log stream` can read it. Each end call is idempotent.
  - `node ios/Fixtures/server.mjs` listens on `127.0.0.1:8787` and accepts `FIXTURE_SCENARIO` and `FIXTURE_LATENCY_MS`.
    - Scenarios: `normal`, `empty`, `error`, `lowconf`, `calibrating`, `pending`.
    - Endpoints: `/health`, `/v1/today`, `/v1/body`, `/v1/sleep`, `/v1/train`, `/v1/history` and `/v1/coach/ask`.
    - It returns deterministic synthetic JSON matching the DTOs, including `baselines`. It honors `If-None-Match` with a weak ETag of the body hash. Any bearer token is accepted.

- [ ] **Step 1: Write the fixture server.** It uses only `node:http` and `node:crypto`, with no dependencies. The README explains how to point the simulator app at it: onboarding → Advanced → URL `http://127.0.0.1:8787`, any token, and user `fixture-user`. `NSAllowsLocalNetworking` is already set in `Info.plist`.
- [ ] **Step 2: Add `PerfSignpost` and the begin/end calls.** No layout changes.
- [ ] **Step 3: Build and run in the iPhone 17 Pro simulator against the fixture.** Use `FIXTURE_LATENCY_MS=250` to approximate production. While running, collect `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.readinesscoach.ReadinessCoach"'`.
- [ ] **Step 4: Record "App, before" in the perf doc.** Note the median of 5 cold launches to Today, and the median of 10 switches into each pillar tab.
- [ ] **Step 5: Measure "before" on Shawn's iPhone 15 Pro against production.** Stop the running app, install this build with `xcrun devicectl device install app`, and record the same medians from the device log. This build only adds signposts, so it changes nothing the user sees.
- [ ] **Step 6: Commit** with message `Add perf signposts and a localhost fixture API for the app`.

### Task 8: `Resource`, `ResourceKey` and the protected disk cache

**Files:**
- Create: `ios/ReadinessCoach/Store/Resource.swift`, `ios/ReadinessCoach/Store/ResourceDiskCache.swift`
- Test: `ios/ReadinessCoachTests/ResourceCacheTests.swift`

**Interfaces:**
- Produces:

```swift
enum ResourceKey: Hashable { case today, body, train, sleep(days: Int), history(days: Int)
    var fileName: String }               // "today", "body", "train", "sleep-30", "history-90"
struct Resource<Value> {
    var value: Value?; var day: String?; var fetchedAt: Date?; var etag: String?
    var dataVersion = 0; var isRefreshing = false; var error: String?
    func needsRevalidation(now: Date, today: String, currentDataVersion: Int, maxAge: TimeInterval = 300) -> Bool
}
struct CachedEnvelope<Value: Codable>: Codable { let userId: String; let day: String; let fetchedAt: Date; let etag: String?; let value: Value }
final class ResourceDiskCache {
    init(directory: URL)                 // live: Application Support/resource-cache
    func load<V: Codable>(_ key: ResourceKey, userId: String, as: V.Type) -> CachedEnvelope<V>?
    func save<V: Codable>(_ key: ResourceKey, _ envelope: CachedEnvelope<V>)
    func removeAll()
}
```

- [ ] **Step 1: Write the failing tests.** Each test uses a temporary directory.
  - `testRoundTripKeepsValueEtagAndDay`
  - `testCacheFromAnotherUserIsIgnored`: save as `"a"` and load as `"b"`, which returns `nil`.
  - `testCorruptFileLoadsAsNil`
  - `testSavedFileIsExcludedFromBackupAndProtected`: assert `isExcludedFromBackup == true`. Assert `FileAttributeKey.protectionKey == .complete` when the attribute is present on the simulator.
  - `testNeedsRevalidationWhenMissingOrOld`: a nil value returns true. At 299 s it returns false. At 301 s it returns true.
  - `testDifferentLocalDayNeedsRevalidation`: with `day "2026-10-22"`, `today "2026-10-23"` and age 10 s, it returns true.
  - `testUploadNewerThanFetchNeedsRevalidation`: with `dataVersion 1` and `currentDataVersion 2`, it returns true.
  - `testRemoveAllDeletesEverything`
  - Legacy `cached-today.json` is deleted, never migrated. It holds a bare `TodayDTO` with no record of whose data it is, so copying it into the signed-in user's slot could show user A's Today to user B. `StoreActivation.activate` deletes it on every activation (signed in or not) and `StoreActivation.reset` deletes it with the user-scoped cache. Tests: `testValidLegacyTodayNeverReachesSignedInUser` (a valid user-A file reaches neither user B's memory nor disk), `testLegacyTodayWithoutUserIsDeleted`, `testCorruptLegacyTodayIsDeletedAndWritesNothing`, `testMissingLegacyTodayStillLoadsUserCache`, `testUserScopedCacheSurvivesLegacyRemoval` and `testResetDeletesLegacyTodayAndUserCache`. Tradeoff: the first launch after upgrading has no cached Today and waits for the network once.
- [ ] **Step 2: Run them and confirm they fail.** Run `xcodebuild test … -only-testing:ReadinessCoachTests/ResourceCacheTests`.
- [ ] **Step 3: Implement.** Write with `[.atomic, .completeFileProtection]`, then set `isExcludedFromBackup`, which is the same sequence `SyncService.didRefresh` uses today. Use a shared static `JSONEncoder` and `JSONDecoder` with `.iso8601` dates.
- [ ] **Step 4: Re-run the tests and confirm they pass.**
- [ ] **Step 5: Commit** with message `Add Resource and a protected per-user disk cache`.

### Task 9: `APIClient`: conditional reads, 15 s timeout, no Render leftovers

**Files:**
- Modify:
  - `ios/ReadinessCoach/Networking/APIClient.swift`
  - `ios/ReadinessCoach/Models/DTOs.swift`: add an optional `baselines: TodayBaselinesDTO?` on `TodayDTO`, mirroring Task 5. Field names match the JSON; `goodDirection` is a `String`.
- Test: `ios/ReadinessCoachTests/APIClientTests.swift` (uses a `URLProtocol` stub)

**Interfaces:**
- Consumes: the Task 5 JSON shape.
- Produces:

```swift
enum Fetch<T> { case fresh(T, etag: String?), notModified }
protocol ReadAPI {
    func today(etag: String?) async throws -> Fetch<TodayDTO>
    func body(days: Int, etag: String?) async throws -> Fetch<BodyResponse>
    func sleep(days: Int, etag: String?) async throws -> Fetch<SleepDetailResponse>
    func train(days: Int, etag: String?) async throws -> Fetch<TrainResponse>
    func history(days: Int, etag: String?) async throws -> Fetch<ReadinessHistoryResponse>
}
extension APIClient: ReadAPI {}
// APIClient gains `init(baseURL:token:userId:session: URLSession = APIClient.liveSession)`
// History requests now also send `tz` (dateQuery already does) — the Task 6 param.
```

- [ ] **Step 1: Write the failing tests.**
  - `testSendsIfNoneMatchAndMaps304ToNotModified`
  - `testNoIfNoneMatchWithoutCachedValue`: `today(etag: nil)` sends no `If-None-Match` header.
  - `testReadTimeoutIs15Seconds`: assert the stubbed request's `timeoutInterval == 15`.
  - `testTransportErrorRetriesOnceImmediately`: the first call fails with `URLError(.networkConnectionLost)` and the second succeeds. Expect 2 requests and an elapsed time under 0.5 s.
  - `testHttpErrorIsNotRetried`: a 500 produces one request.
  - `testTodayDecodesWithAndWithoutBaselines`
  - `testDeviceLocalDateUsesSharedFormatter`: `deviceLocalDate(now:)` returns the same value as before for a fixed date in `America/New_York`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
  - Delete `wakeServer`, `getTodayWithRetry` and the 2.5 s sleep in `syncChunk`. Replace them with a single immediate retry on `.transport`, for both reads and `syncChunk`.
  - Set the session `timeoutIntervalForRequest` to 15 and `timeoutIntervalForResource` to 300. Reads default to 15 s, and `postSync` keeps 120 s.
  - Have `requestData` return `(Data, HTTPURLResponse)` so the ETag can be read. A 304 maps to `.notModified`.
  - Replace every `get…` caller with the new protocol methods, keeping the old names only if `TrendsView` or tests still need them for one task. Remove the old names once Task 11 lands.
  - Make the `deviceLocalDate` formatter a static one. Remove Render comments.
- [ ] **Step 4: Re-run the tests and the full iOS test suite, and confirm they pass.**
- [ ] **Step 5: Commit** with message `Conditional reads, 15 s timeout, drop Render wake-and-retry`.

### Task 10: `AppStore`

**Files:**
- Create: `ios/ReadinessCoach/Store/AppStore.swift`
- Test: `ios/ReadinessCoachTests/AppStoreTests.swift` (with a `FakeReadAPI` that records calls and returns scripted `Fetch` values)

**Interfaces:**
- Consumes: `Resource`, `ResourceKey`, `ResourceDiskCache` (Task 8); `ReadAPI` and `Fetch` (Task 9).
- Produces:

```swift
@MainActor @Observable final class AppStore {
    init(cache: ResourceDiskCache, now: @escaping () -> Date = Date.init,
         localDay: @escaping () -> String = { APIClient.deviceLocalDate() })
    var today: Resource<TodayDTO>; var body: Resource<BodyResponse>; var train: Resource<TrainResponse>
    var sleep: [Int: Resource<SleepDetailResponse>]; var history: [Int: Resource<ReadinessHistoryResponse>]
    private(set) var dataVersion: Int
    /// Loads every cached resource for `userId` from disk; sets the API used by refreshes.
    func activate(userId: String, api: ReadAPI?)
    /// Fetches `key` unless fresh (or `force`), deduping concurrent calls per key. Returns success.
    @discardableResult func refresh(_ key: ResourceKey, force: Bool = false) async -> Bool
    /// Background, non-awaited: body, sleep(30), train — each only if it needs revalidation.
    func prefetchPillars()
    /// Called by SyncService after an upload stored new samples.
    func noteUploadedSamples()
    /// Sign-out / account deletion: clears memory and disk.
    func reset()
}
```

- [ ] **Step 1: Write the failing tests.**
  - `testActivateShowsCachedValuesWithoutNetwork`: the fake records zero calls.
  - `testFreshResourceIsNotRefetched`, then `testStaleResourceIsRefetched`, both using the injected `now`.
  - `testForceRefetchesFreshResource`
  - `testConcurrentRefreshesShareOneRequest`: two `async let` refreshes of `.body` produce one fake call.
  - `testNotModifiedKeepsValueAndBumpsFetchedAt`
  - `testErrorKeepsCachedValue`: the value is unchanged, `error` is non-nil, and `isRefreshing` is false.
  - `testSuccessfulTodayRefreshPrefetchesPillars`: after `refresh(.today, force: true)`, the fake eventually sees `body`, `sleep(30)` and `train`.
  - `testUploadMakesResourcesStale`: after `noteUploadedSamples()`, a fresh `.body` refetches.
  - `testIfNoneMatchOnlyWithCachedValue`: the fake sees `etag == nil` when `value == nil`.
  - `testResetClearsMemoryAndDisk`
  - `testActivateDifferentUserClearsPreviousUsersValues`
  - `testRefreshCompletingAfterUserSwitchDoesNotWrite`: a fetch for the old user is held, the store activates a new user, then the old fetch completes; neither memory nor disk gets the old user's result.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
  - Keep in-flight tasks in `[ResourceKey: Task<Bool, Never>]`.
  - Activating a different user, or `reset`, clears memory, cancels in-flight tasks and bumps a session generation. Each fetch records the generation it started under and checks it again before writing to memory or disk, so a result for the previous user is dropped.
  - Persist every `.fresh` result with `day = localDay()`.
  - `dataVersion` starts at 0 per session. A resource stores the `dataVersion` it was fetched at.
  - `refresh(.today)` calls `prefetchPillars()` on success.
- [ ] **Step 4: Re-run the tests and confirm they pass.**
- [ ] **Step 5: Commit** with message `Add AppStore with stale-while-revalidate, dedupe and prefetch`.

### Task 11: Wire the store into the app and views, with no visual change

**Files:**
- Modify:
  - `ios/ReadinessCoach/ReadinessCoachApp.swift`: `LiveAppRoot` owns the `AppStore`, injects it with `.environment(store)`, and calls `store.activate` when `settings.userId` and `isReady` change.
  - `ios/ReadinessCoach/Services/SyncService.swift`:
    - It takes `store` in `init`. `today` becomes a computed `store.today.value`. `refreshToday` and `performSync` call `store.refresh(.today, force: true)`.
    - `errorMessage` comes from `store.today.error` when the refresh fails.
    - After `uploadHealth` returns true, call `store.noteUploadedSamples()` before the refresh.
    - Remove the `wakeTask`, the `cached-today.json` code (the file itself is deleted on activation; see Task 8) and `didRefresh`'s file writing. Keep `settings.lastRefreshAt`.
  - `ios/ReadinessCoach/Views/SettingsView.swift`: replace `sync.today = nil` with `store.reset()`.
  - `BodyView.swift`, `SleepView.swift`, `TrainView.swift`, `TrendsView.swift`:
    - Read data from `@Environment(AppStore.self)`, drop `@EnvironmentObject settings`, and drop the private `response`, `isLoading` and `error` state.
    - On appear, run `.task(id: key) { await store.refresh(key) }`. Pull to refresh uses `.refreshable { await store.refresh(key, force: true) }`.
    - Show a spinner only when `value == nil && isRefreshing`. Show an `ErrorCard` only when `value == nil && error != nil`.
    - `BodyView` takes pillars from `store.today.value?.pillars` and no longer calls `getToday()`.
  - `TrainView.swift`, `SleepView.swift`, `StatusLine.swift`, `RootView.swift`: move the per-call `ISO8601DateFormatter()` and `DateFormatter()` into `static let` instances. `HealthKitService` too, if it is on a hot path.
  - Chart views: move series derivation (point arrays, min/max, averages) out of `body` into values computed once when the resource changes, for example a `private var series` built in `.onChange(of: resource.fetchedAt)` or a small view-model struct initialized from the value. Output must render identically.
  - `BodyView.swift`, `TrainView.swift`, `TrendsView.swift`: if a workout or history list renders more than about 20 rows, replace `VStack` with `LazyVStack` without changing the look.
- Test: `ios/ReadinessCoachTests/RedesignRegressionTests.swift` (add a case)

- [ ] **Step 1: Write the failing test** `testPillarViewsDoNotObserveSettingsOrSync`. Use a source-level guard that reads the four view files from the bundle's source path through `#filePath` and asserts that none contains `@EnvironmentObject private var settings` or `@EnvironmentObject private var sync`. Upload ticks write `settings.lastSyncAt` and `sync.uploadingCount`, so a view that observes them re-renders its charts during an upload.
- [ ] **Step 2: Run it and confirm it fails.**
- [ ] **Step 3: Make the wiring changes above.** Then confirm that `grep -rn "wakeServer\|getTodayWithRetry\|cached-today" ios/ReadinessCoach` prints nothing.
- [ ] **Step 4: Re-run the full iOS test suite and confirm all of it passes.**
- [ ] **Step 5: Simulator check against the fixture.**
  - With the `normal` scenario, every tab looks as it did before. Compare screenshots at the iPhone 17 Pro default size against screenshots taken at the start of this task.
  - With `error`, the cached tabs still show content.
  - With `empty`, the existing empty states appear.
- [ ] **Step 6: Commit** with message `Read every screen from AppStore; pillar tabs open from cache`.

### Task 12: "After" numbers, device check, review and PR

**Files:**
- Modify: `docs/perf/2026-10-23-phase1.md`

- [ ] **Step 1: Re-measure the server.** Re-run `npm run measure:api` against the same perf database and add "Server, after". Each read endpoint must have p95 < 300 ms, and `/v1/body?days=30` must be < 50 KB. For any target that is missed, record it and stop to report it.
- [ ] **Step 2: Re-measure the app.** Re-run the Task 7 simulator measurement and add "App, after". A cached tab switch must be < 100 ms with no spinner, and a cold launch to cached Today must be < 1 s.
- [ ] **Step 3: Device check on Shawn's iPhone 15 Pro** (`00008130-001859980EB9401C`).
  - First stop the running app, then build, install with `xcrun devicectl device install app`, and launch.
  - Confirm the installed build has the change. Look for `perf LaunchToToday` lines in the device log.
  - Record the launch and tab-switch timings against production.
  - Turn on airplane mode and confirm every tab still shows cached content and Today shows the offline status line.
  - Turn airplane mode off, run a full sync from Settings, and confirm Today updates.
- [ ] **Step 4: Run every check in Global Constraints and confirm they pass.** Run `git diff main --stat` and confirm no files outside this plan changed.
- [ ] **Step 5: Push `redesign-v3-phase1` and open the PR to `main`.** The body should include the before/after table and the verification record. Link it in T3 Code.
- [ ] **Step 6: Get the independent review.** Request a high-effort Astra (`gpt-6-astra`) cross-family review of the PR diff, with the spec and this plan. Fix the findings that hold up, then re-run the affected checks.
- [ ] **Step 7: Confirm the PR is ready to merge.** CI must be green, the review done and there must be no conflicts. Ask Shawn before merging, because merging deploys the backend.
