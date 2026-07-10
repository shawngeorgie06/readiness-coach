# Agent prompt — implement Readiness Coach

Paste this into a new Cursor agent chat opened on this repository.

---

Implement the Readiness Coach project from the approved design + plan.

## Context
This is a personal Apple Watch / HealthKit readiness app with a strict hybrid AI advisor.

- Design spec: `docs/superpowers/specs/2026-07-10-readiness-coach-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-10-readiness-coach.md`

## Product (do not reinterpret)
- Native-first: SwiftUI iPhone app + TypeScript/Express backend + Postgres + light React web dashboard
- HealthKit sync: HR, HRV, RHR, sleep, workouts
- Deterministic readiness score with recomp weights:
  Readiness = 0.35×Sleep + 0.40×Recovery + 0.25×Load
- Decision bands: ≥75 Push, 50–74 Maintain, <50 Recover
- Hard overrides can force Recover (sleep <5h, HRV ≤−20% + elevated RHR, back-to-back high strain)
- Hybrid coach: scoring locks the decision; cloud LLM only writes the strict advisor note / Ask Coach answers and MUST NOT upgrade the decision
- Goal profile: recomp / general fitness
- Advisor voice: strict advisor (direct, evidence-backed, no cheerleading)

## How to execute
1. Read the design spec and implementation plan fully before coding.
2. Follow the plan task-by-task in order (Tasks 1 → 12).
3. Use TDD where the plan specifies tests (especially scoring + advisor decision lock).
4. Commit after each task with the commit messages suggested in the plan.
5. Prefer subagent-driven development if available: one fresh subagent per task, review between tasks.
6. Do not expand scope into Watch apps, food logging, social, or local LLMs.

## Environment constraints
- Backend + web can be built/tested in a normal Node environment.
- iOS tasks (10–12) require macOS + Xcode + a physical iPhone/Watch for HealthKit. If you’re not on a Mac, complete Tasks 1–9 fully, leave clear handoff notes for iOS, and stub/demo seed data so the API + web work without HealthKit.

## Definition of done for v1
- `npm test` passes for backend scoring + advisor lock tests
- Sync + Today + Ask Coach APIs work with bearer auth
- Web Today page shows score, decision, pillars, advisor note
- iOS (when on Mac): HealthKit permission → sync → Today populated; Ask Coach cannot contradict a Recover lock

Start at Task 1 of the implementation plan now.
