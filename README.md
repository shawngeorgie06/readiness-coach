# Readiness Coach

Personal Apple Watch / HealthKit readiness app with a **strict hybrid AI advisor**.

Watch → HealthKit → iPhone app → your API → readiness score (Push / Maintain / Recover) → cloud LLM writes the coaching note (decision is locked).

## Docs

- [Design spec](docs/superpowers/specs/2026-07-10-readiness-coach-design.md)
- [Implementation plan](docs/superpowers/plans/2026-07-10-readiness-coach.md)

## Stack (planned)

| Layer | Tech |
|-------|------|
| iOS | SwiftUI + HealthKit |
| API | Node.js + TypeScript + Express |
| DB | PostgreSQL + Prisma |
| Advisor | Cloud LLM (hybrid; score is deterministic) |
| Web | Vite + React (light Today dashboard) |

## Status

Design and implementation plan are checked in. Implementation starts at Task 1 of the plan (backend scaffold + scoring TDD).

## Local setup (after implementation begins)

```bash
# Backend
cd backend
cp .env.example .env
docker compose up -d   # from repo root
npm install
npx prisma migrate dev
npm test
npm run dev

# Web
cd web
npm install
VITE_API_URL=http://localhost:4000 VITE_API_TOKEN=dev-token-change-me npm run dev
```

iOS requires macOS + Xcode + a physical iPhone (and Apple Watch data in Health).
