// Dependency-free fixture API for measuring and exercising the iOS app.
// Usage: FIXTURE_SCENARIO=normal FIXTURE_LATENCY_MS=250 node ios/Fixtures/server.mjs
// Deterministic synthetic JSON only; no real data. Any bearer token is accepted.
import { createServer } from "node:http";
import { createHash } from "node:crypto";

const PORT = Number(process.env.FIXTURE_PORT ?? 8787);
const SCENARIO = process.env.FIXTURE_SCENARIO ?? "normal";
const LATENCY_MS = Number(process.env.FIXTURE_LATENCY_MS ?? 0);
const SCENARIOS = ["normal", "empty", "error", "lowconf", "calibrating", "pending"];
if (!SCENARIOS.includes(SCENARIO)) {
  console.error(`Unknown FIXTURE_SCENARIO "${SCENARIO}". Use one of: ${SCENARIOS.join(", ")}`);
  process.exit(1);
}

// --- deterministic helpers -------------------------------------------------

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const round = (n, d = 1) => Math.round(n * 10 ** d) / 10 ** d;
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));
const hash = (s) => [...s].reduce((h, c) => (Math.imul(h, 31) + c.charCodeAt(0)) >>> 0, 7);

function isoDay(d) {
  return d.toISOString().slice(0, 10);
}
function localToday() {
  const d = new Date();
  return isoDay(new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())));
}
function addDays(day, n) {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return isoDay(d);
}
/** The last `n` days ending at `end`, oldest first. */
function dayRange(end, n) {
  return Array.from({ length: n }, (_, i) => addDays(end, i - (n - 1)));
}

// Per-day synthetic physiology, stable for a given calendar day.
function dayStats(day) {
  const r = rng(hash(day));
  const dow = new Date(`${day}T00:00:00Z`).getUTCDay();
  const hrv = round(58 + 9 * Math.sin(hash(day) / 7) + (r() - 0.5) * 8);
  const rhr = round(54 + 2.5 * Math.cos(hash(day) / 9) + (r() - 0.5) * 3);
  const sleep = round(clamp(7.2 + (r() - 0.5) * 2.2 - (dow === 5 ? 0.6 : 0), 5.2, 9.1), 2);
  return { hrv, rhr, sleep, r };
}

// --- payload builders ------------------------------------------------------

function metric(today, base, band, series, goodDirection) {
  return {
    today,
    baseline30d: base,
    neutralBand: base == null ? null : { low: round(base * (1 - band), 2), high: round(base * (1 + band), 2) },
    recent14d: series,
    goodDirection,
  };
}

function workoutsFor(end, days) {
  const sports = ["Running", "Traditional Strength Training", "Cycling", "Running", "Functional Strength Training"];
  const out = [];
  for (const day of dayRange(end, days)) {
    const r = rng(hash(`w${day}`));
    const dow = new Date(`${day}T00:00:00Z`).getUTCDay();
    if (![1, 3, 4, 6].includes(dow)) continue;
    const sport = sports[Math.floor(r() * sports.length)];
    const durationMin = round(32 + r() * 38);
    const avg = round(126 + r() * 30);
    const hour = dow === 6 ? 9 : 18;
    const start = new Date(`${day}T${String(hour).padStart(2, "0")}:10:00Z`);
    const zones = [0.1, 0.3, 0.35, 0.2, 0.05].map((f) => round(durationMin * f));
    out.push({
      id: `fixture-workout-${day}`,
      sport,
      startAt: start.toISOString(),
      endAt: new Date(start.getTime() + durationMin * 60000).toISOString(),
      durationMin,
      avgHrBpm: avg,
      maxHrBpm: round(avg + 28 + r() * 12),
      calories: round(durationMin * (8 + r() * 4)),
      strain: round(clamp(durationMin * (avg - 90) / 260, 2, 18)),
      hrZonesMin: zones,
    });
  }
  return out;
}

function sleepDay(day) {
  const { sleep, r } = dayStats(day);
  const deep = round(sleep * (0.14 + r() * 0.05), 2);
  const rem = round(sleep * (0.2 + r() * 0.05), 2);
  const awake = round(0.25 + r() * 0.4, 2);
  const core = round(Math.max(sleep - deep - rem, 0.5), 2);
  const start = new Date(`${addDays(day, -1)}T${r() < 0.5 ? "22" : "23"}:${String(Math.floor(r() * 50)).padStart(2, "0")}:00Z`);
  const end = new Date(start.getTime() + (sleep + awake) * 3600000);
  // Cycles of core/deep/core/rem/awake, like real staged HealthKit nights.
  const pattern = [["core", core * 0.3], ["deep", deep * 0.6], ["core", core * 0.2], ["rem", rem * 0.4], ["awake", awake * 0.2],
    ["core", core * 0.25], ["deep", deep * 0.4], ["core", core * 0.25], ["rem", rem * 0.6], ["awake", awake * 0.8]];
  const timeline = [];
  let t = start.getTime();
  for (const [stage, hours] of pattern) {
    const next = t + hours * 3600000;
    timeline.push({ stage, startAt: new Date(t).toISOString(), endAt: new Date(next).toISOString(), hours: round(hours, 3) });
    t = next;
  }
  return {
    date: day,
    durationHours: sleep,
    restorativeHours: round(deep + rem, 2),
    sleepStart: start.toISOString(),
    sleepEnd: end.toISOString(),
    stages: { deep, rem, core, awake },
    timeline,
  };
}

function bodyDaily(end, days) {
  const out = [];
  for (const day of dayRange(end, days)) {
    const { hrv, rhr, r } = dayStats(day);
    out.push({ type: "hrv_sdnn", date: day, min: round(hrv - 14), avg: hrv, max: round(hrv + 16), latest: round(hrv + (r() - 0.5) * 6), count: 6 });
    out.push({ type: "resting_heart_rate", date: day, min: round(rhr - 1), avg: rhr, max: round(rhr + 1.5), latest: rhr, count: 1 });
    out.push({ type: "heart_rate", date: day, min: round(48 + r() * 4), avg: round(70 + r() * 8), max: round(135 + r() * 40), latest: round(62 + r() * 20), count: 288 });
  }
  return out;
}

function todayPayload(date) {
  const days = dayRange(date, 30);
  const stats = days.map(dayStats);
  const t = stats[29];
  const prior = stats.slice(0, 29);
  const avg = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
  const hrvBase = round(avg(prior.map((s) => s.hrv)), 2);
  const rhrBase = round(avg(prior.map((s) => s.rhr)), 2);
  const sleepBase = round(avg(prior.map((s) => s.sleep)), 2);
  const strain = dayRange(date, 28).map((d) => workoutsFor(d, 1).reduce((a, w) => a + w.strain, 0));
  const load7 = round(strain.slice(-7).reduce((a, b) => a + b, 0) / 7, 2);
  const load28 = round(avg(strain), 2);
  const rolling = strain.map((_, i) => (i < 6 ? null : round(strain.slice(i - 6, i + 1).reduce((a, b) => a + b, 0) / 7, 2)));

  const pending = SCENARIO === "pending";
  const lowconf = SCENARIO === "lowconf";
  const calibrating = SCENARIO === "calibrating";

  const sleepScore = round(clamp(60 + (t.sleep - 7) * 22, 20, 98), 0);
  const recoveryScore = round(clamp(70 + (t.hrv - hrvBase) * 2.2 - (t.rhr - rhrBase) * 3, 15, 98), 0);
  const loadScore = round(clamp(74 - Math.max(0, load7 - load28) * 6, 20, 95), 0);
  const readiness = round(sleepScore * 0.35 + recoveryScore * 0.4 + loadScore * 0.25, 0);
  const decision = readiness >= 75 ? "push" : readiness >= 50 ? "maintain" : "recover";

  const advice = {
    push: ["You're recovered, so a hard session is on the table.", "Skip the hard effort and you leave progress unused."],
    maintain: ["Train, but keep intensity moderate today.", "Pushing to a maximal effort risks digging a recovery hole."],
    recover: ["Back off: rest or light movement only.", "Ignoring this stacks fatigue on a body already behind."],
  }[decision];

  return {
    date,
    readiness,
    decision,
    calibrating,
    pillars: {
      sleep: { score: sleepScore, drivers: [{ text: `${round(t.sleep, 1)} h of sleep`, detail: `Your 30-day average is ${round(sleepBase, 1)} h.` }] },
      recovery: { score: recoveryScore, drivers: [{ text: `HRV ${round(t.hrv, 0)} ms`, detail: `Baseline ${round(hrvBase, 0)} ms; resting HR ${round(t.rhr, 0)} bpm.` }] },
      load: { score: loadScore, drivers: [{ text: "Training load in range", detail: `7-day average strain ${load7} against ${load28} over 28 days.` }] },
    },
    overridesApplied: [],
    confidence: lowconf ? "low" : "high",
    missing: lowconf ? ["hrv_sdnn", "resting_heart_rate"] : [],
    sleepPending: pending,
    advisor: {
      decision,
      why: [`Sleep ${sleepScore}, recovery ${recoveryScore}, load ${loadScore}.`, "Scores come from your own 30-day baselines."],
      prescription: advice[0],
      ifIgnored: advice[1],
      source: "template",
    },
    baselines: {
      hrv: metric(round(t.hrv, 2), hrvBase, 0.05, stats.slice(-14).map((s) => round(s.hrv, 2)), "up"),
      restingHr: metric(round(t.rhr, 2), rhrBase, 0.03, stats.slice(-14).map((s) => round(s.rhr, 2)), "down"),
      sleepHours: metric(pending ? null : t.sleep, sleepBase, 0.1, stats.slice(-14).map((s) => s.sleep), "up"),
      load7d: metric(load7, load28, 0.3, rolling.slice(-14), "none"),
    },
  };
}

function historyPayload(date, days) {
  const first = dayRange(date, 30)[0];
  return {
    days,
    data: dayRange(date, days).map((day) => {
      const p = todayPayload(day);
      return {
        date: day,
        readiness: p.readiness,
        decision: p.decision,
        sleepScore: p.pillars.sleep.score,
        recoveryScore: p.pillars.recovery.score,
        loadScore: p.pillars.load.score,
        calibrating: SCENARIO === "calibrating" ? day >= first : false,
      };
    }),
  };
}

// --- server ----------------------------------------------------------------

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function send(req, res, status, body) {
  const json = JSON.stringify(body);
  const headers = { "Content-Type": "application/json; charset=utf-8" };
  if (req.url?.startsWith("/v1/") && req.method === "GET" && status === 200) {
    headers["Cache-Control"] = "private, no-store";
    headers.ETag = `W/"${createHash("sha1").update(json).digest("hex").slice(0, 16)}"`;
    if (req.headers["if-none-match"] === headers.ETag) {
      res.writeHead(304, headers);
      res.end();
      return;
    }
  }
  res.writeHead(status, headers);
  res.end(json);
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
  });
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://fixture");
  const path = url.pathname;
  const q = url.searchParams;
  const body = req.method === "POST" || req.method === "DELETE" ? await readBody(req) : "";
  if (LATENCY_MS > 0) await delay(LATENCY_MS);

  if (path === "/health") return send(req, res, 200, { ok: true });

  if (!path.startsWith("/v1/")) return send(req, res, 404, { error: "not_found" });
  if (!req.headers.authorization?.startsWith("Bearer ")) return send(req, res, 401, { error: "unauthorized" });
  if (SCENARIO === "error") return send(req, res, 500, { error: "fixture_error" });

  const date = /^\d{4}-\d{2}-\d{2}$/.test(q.get("date") ?? "") ? q.get("date") : localToday();
  const days = (fallback) => {
    const n = Number(q.get("days") ?? fallback);
    return Number.isInteger(n) && n >= 1 && n <= 90 ? n : fallback;
  };
  const empty = SCENARIO === "empty";

  if (req.method === "GET") {
    switch (path) {
      case "/v1/today":
        return empty ? send(req, res, 404, { error: "user_not_found" }) : send(req, res, 200, todayPayload(date));
      case "/v1/body": {
        const n = days(30);
        return send(req, res, 200, { days: n, daily: empty ? [] : bodyDaily(date, n) });
      }
      case "/v1/sleep": {
        const n = days(30);
        return send(req, res, 200, { days: n, data: empty ? [] : dayRange(date, n).map(sleepDay) });
      }
      case "/v1/train": {
        const n = days(28);
        return send(req, res, 200, { days: n, data: empty ? [] : workoutsFor(date, n) });
      }
      case "/v1/history": {
        const n = days(30);
        return empty ? send(req, res, 404, { error: "user_not_found" }) : send(req, res, 200, historyPayload(date, n));
      }
    }
  }
  if (req.method === "POST" && path === "/v1/coach/ask") {
    let decision = "maintain";
    try { decision = JSON.parse(body || "{}").question ? todayPayload(date).decision : decision; } catch { /* keep default */ }
    return send(req, res, 200, { decision, answer: "Fixture answer: follow today's locked decision and keep effort matched to it." });
  }
  if (req.method === "POST" && path === "/v1/sync") {
    let samples = 0;
    let workouts = 0;
    try { const p = JSON.parse(body || "{}"); samples = p.samples?.length ?? 0; workouts = p.workouts?.length ?? 0; } catch { /* ignore */ }
    return send(req, res, 200, { ok: true, samples, workouts });
  }
  if (req.method === "DELETE" && path === "/v1/user") return send(req, res, 200, { ok: true });
  return send(req, res, 404, { error: "not_found" });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`fixture API on http://127.0.0.1:${PORT} scenario=${SCENARIO} latency=${LATENCY_MS}ms`);
});
