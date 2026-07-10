# Readiness Coach — Design Spec

**Date:** 2026-07-10  
**Status:** Approved for implementation planning  
**Working title:** Readiness Coach (name TBD)

## Problem

Apple Health shows raw Watch metrics (HR, HRV, sleep, workouts) but does not turn them into a clear daily training decision. Generic AI coaches give vague advice untethered from personal baselines. Whoop-like products are closed and subscription-heavy.

## Product

A **native iPhone app** that syncs Apple Watch data via HealthKit to **your backend**, computes a personal readiness score, and surfaces a **strict AI advisor** that tells you what to do today — grounded only in your metrics.

**One-liner:** Live readiness OS on Apple Watch data, with a strict advisor that decides Push / Maintain / Recover from *your* sleep, recovery, and training load.

### Goals (v1)

- Live-ish HealthKit sync on iPhone (HR, HRV, RHR, sleep stages, workouts)
- Personal baselines (14/30 day)
- Readiness score → **Push / Maintain / Recover**
- Hybrid coach: deterministic decision + cloud LLM explanation / Q&A
- Light web dashboard reading the same API
- Primary training goal: **recomp / general fitness**

### Non-goals (v1)

- Apple Watch app, complications, or live workout streaming UI
- Food logging, social features, coaching marketplace
- Local on-device LLM
- Medical diagnosis or clinical claims
- Reverse-engineering private Apple APIs (HealthKit only)

## Users

Primary user: you (personal product). Design for daily morning use on iPhone; laptop web view is secondary.

## Architecture

**Approach: native-first**

```
Apple Watch
    → HealthKit (iPhone)
    → SwiftUI app (permissions, local cache, sync client)
    → Backend API + DB (store samples, baselines, scores, notes)
         ├─ Scoring engine (deterministic)
         ├─ Cloud LLM (advisor note + Ask Coach)
         └─ REST API
              → iPhone UI
              → Light web dashboard
```

### Components

| Component | Responsibility |
|-----------|----------------|
| **iOS app (SwiftUI)** | HealthKit auth/read, background delivery hooks, sync, Today/Sleep/Train/Body/Settings UI, Ask Coach |
| **Sync API** | Accept batched HealthKit samples; idempotent upsert by sample UUID / source revision |
| **Scoring engine** | Baselines, pillar scores, readiness, decision bands, hard overrides |
| **Advisor service** | Build metric summary → LLM → structured note; Ask Coach with same grounding |
| **Web dashboard** | Read-only Today + trends (same auth/API) |
| **DB** | Users, samples, daily scores, advisor notes, settings |

### Coach runtime (hybrid, cloud-leaning)

1. Scoring engine produces **decision** (Push / Maintain / Recover). Non-negotiable.
2. Cloud LLM receives a **metric summary** + locked decision and writes the strict note / answers questions.
3. LLM **must not** upgrade a more conservative decision (e.g. Recover → Push).
4. API keys live on the backend only.

## Scoring model

### Pillars (each 0–100)

| Pillar | Signals |
|--------|---------|
| **Sleep** | Duration vs need, deep/REM share, consistency, sleep debt |
| **Recovery** | HRV vs 30-day baseline, RHR vs baseline, overnight HR |
| **Load** | Yesterday strain, 7-day training load, acute:chronic ratio |

### Composite (recomp weighting)

```
Readiness = 0.35×Sleep + 0.40×Recovery + 0.25×Load
```

Recovery is weighted highest so consistency is protected over grinding.

### Decision bands

| Score | Decision |
|------:|----------|
| ≥ 75 | **Push** — hard session OK |
| 50–74 | **Maintain** — train, cap intensity |
| < 50 | **Recover** — easy only / rest |

### Strain proxy (v1, tunable)

Approximate workout strain from duration × average HR relative to heart-rate reserve (or available workout stats from HealthKit). Exact formula locked in implementation plan; must be deterministic and unit-tested.

### Baselines

- Rolling **14-day** and **30-day** personal norms for HRV, RHR, sleep duration, weekly load.
- First ~14 days: **calibrating** mode — show banner; prescriptions lean conservative.
- Comparisons are vs personal baseline, not population averages.

### Hard overrides

Force **Recover** (or block Push) even if composite score is higher when:

- Sleep duration last night < 5 hours
- HRV ≤ −20% vs 30-day baseline **and** RHR elevated vs baseline
- Back-to-back high-strain days with no easy day in between

## Strict advisor

### Voice

Strict advisor: direct, evidence-backed, no cheerleading, no emoji. One primary prescription + one fallback when useful.

### Morning note structure

1. **Decision** — one line  
2. **Why** — 2–4 bullets citing user numbers  
3. **Today’s prescription** — concrete action  
4. **If you ignore this** — one consequence line  

### Ask Coach

User can ask planning / “can I PR?” / sleep questions. Answers must cite current readiness + recent load. Cannot override a Recover lock without new supporting data.

### Safety

- Not medical advice; no diagnosis language.
- Pain / illness reports → stop training prescriptions; suggest rest / clinician.
- Missing data → state what’s missing; default more conservative.
- LLM outage → show decision + deterministic template note; disable chat until restored.

## Screens (v1)

| Screen | Purpose |
|--------|---------|
| Onboarding | HealthKit permissions, goal = recomp, account |
| **Today** | Score, decision, three pillars, advisor note, Ask Coach entry |
| **Sleep** | Last night, debt, 7/30-day trends |
| **Train** | Workouts, weekly load, acute:chronic |
| **Body** | HRV, RHR, HR trends vs baseline |
| Settings | Sync status, units, data delete, account |
| Web (light) | Today + trends |

### Today hierarchy

1. Readiness number  
2. Decision label (Push / Maintain / Recover)  
3. Sleep / Recovery / Load pillar chips  
4. Advisor card  
5. Ask Coach  

## Data & API (sketch)

### HealthKit types (read)

- Heart rate, resting heart rate, heart rate variability (SDNN)
- Sleep analysis (including stages when available)
- Workouts (type, duration, calories, HR stats when present)

### Sync

- App batches new/changed samples and `POST /v1/sync`
- Idempotent by HealthKit sample UUID (or equivalent stable id)
- Server records `last_sync_at`; client shows sync health

### Core reads

- `GET /v1/today` — score, pillars, decision, advisor note, confidence
- `GET /v1/sleep`, `/v1/train`, `/v1/body` — detail + trends
- `POST /v1/coach/ask` — question + grounded answer

Exact schemas belong in the implementation plan.

## Error handling

| Case | Behavior |
|------|----------|
| HealthKit denied | Block main experience; clear grant-access path |
| Partial data | Score available pillars; low confidence; conservative advisor |
| Sync failure | Keep last good day; retry; no fabricated “fresh” advice |
| LLM down | Decision + template note; Ask Coach unavailable |
| Calibrating (< ~14 days) | Banner + cautious prescriptions |
| Stale samples | Warn when data older than expected window |

## Testing bar (v1)

- Unit tests: pillar scores, composite, bands, hard overrides (fixture metrics)
- Sync: idempotent upsert, validation of payloads
- Advisor contract test: LLM response cannot upgrade locked decision (enforce in service layer, not trust the model)
- Manual device: grant HealthKit → Today populates with real Watch data

## Privacy

- Health data is sensitive: encrypt in transit (TLS); encrypt at rest on server
- Minimize LLM payload to summaries / recent windows, not full lifetime raw dumps
- User can delete account data from Settings
- No selling data; personal product defaults to single-user deploy

## Open decisions (non-blocking for planning)

- Final product name
- Exact cloud LLM provider (OpenAI / Gemini / Claude) — pluggable behind Advisor service
- Hosting (e.g. Railway / Render / Fly) and auth (Sign in with Apple vs simple personal token)
- Precise strain formula constants

## Success criteria

v1 succeeds when, on a normal morning with Watch sleep + recent workouts synced:

1. Today shows a readiness score and Push / Maintain / Recover within seconds of open (after sync).
2. Advisor note cites real personal deltas (e.g. HRV vs baseline, sleep debt, yesterday load).
3. Ask Coach answers a planning question without contradicting the locked decision.
4. Web dashboard shows the same Today summary.
