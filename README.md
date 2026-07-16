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

Backend + web (Tasks 1–9) are implemented and verified. The iOS app (Tasks
10–12) is implemented under [`ios/`](ios/README.md) — full SwiftUI source wired
to the API — and **compiles against the iOS SDK** (`xcodebuild` for the
Simulator, `** BUILD SUCCEEDED **`). It still needs to be code-signed and run on
a physical iPhone in Xcode to exercise HealthKit (device-only). See
[`ios/README.md`](ios/README.md) and [`docs/ios-handoff.md`](docs/ios-handoff.md).

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
