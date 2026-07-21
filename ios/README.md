# Readiness Coach — iOS app

SwiftUI iOS 17 app that reads HealthKit data, syncs it to the Readiness Coach
API, and shows the locked readiness decision plus the strict advisor note. This
covers implementation-plan Tasks 10–12.

## Requirements

- **macOS with Xcode 16 or newer** (the project uses file-system-synchronized
  groups, `objectVersion = 77`). If you have an older Xcode, regenerate the
  project with XcodeGen — see below.
- A physical iPhone signed into an Apple ID with HealthKit data (HealthKit is
  not available on the Simulator).
- The backend running and reachable from the device, with a private
  `API_TOKEN`.

## Open & run

```bash
open ios/ReadinessCoach.xcodeproj
```

1. Select the `ReadinessCoach` target → Signing & Capabilities → set your
   **Team** (the project ships with an empty team and automatic signing).
2. Copy `ios/Secrets.example.swift` to `ReadinessCoach/Secrets.swift` and optionally
   paste your API token to pre-fill onboarding (`Secrets.swift` is gitignored).
3. Open `Secrets.swift` only on your machine — never commit a real token.
   HealthKit is already declared in `ReadinessCoach.entitlements`.
2. Choose your connected iPhone as the run destination and Run (⌘R).
3. On first launch (Onboarding):
   - Enter **API URL** (e.g. `http://<your-mac-lan-ip>:4000`), **API token**
     (matches backend `API_TOKEN`), and a **User ID** (a UUID is prefilled).
   - Tap **Allow Health access** and grant read permissions.
   - Tap **Start & sync** to run the first sync and load Today.

> For a device to reach a locally-running backend, use your Mac's LAN IP (not
> `localhost`) and make sure both are on the same network. Plain HTTP to a LAN
> IP works in development; for anything outside your LAN, front the API with
> HTTPS.
>
> For daily use **without** leaving your Mac running the API, follow
> [`docs/personal-free-deploy.md`](../docs/personal-free-deploy.md) (free Neon +
> Render). Put that `https://…` URL into Onboarding instead of a LAN IP.

## Regenerate the project (optional / older Xcode)

```bash
brew install xcodegen
cd ios && xcodegen generate && open ReadinessCoach.xcodeproj
```

`project.yml` is the source of truth for that path.

## Structure

```
ReadinessCoach/
  ReadinessCoachApp.swift      App entry; injects AppSettings + SyncService
  Models/DTOs.swift            Codable types matching the API contract
  Networking/APIClient.swift   Async bearer-auth client for /v1/*
  Settings/AppSettings.swift   Persisted URL/token/userId + lastSyncAt
  Services/HealthKitService.swift  Read HK samples → sync payload (read-only)
  Services/SyncService.swift   Sync + Today refresh, observable state
  Views/                       Onboarding, Today, Sleep, Train, Body, Ask, Settings
```

## API contract used

| Call | Endpoint |
|------|----------|
| Today | `GET /v1/today?userId=&date=` |
| Sync | `POST /v1/sync` |
| Sleep | `GET /v1/sleep?userId=&days=` |
| Train | `GET /v1/train?userId=&days=` |
| Body | `GET /v1/body?userId=&days=` |
| Ask Coach | `POST /v1/coach/ask` |
| Delete account data | `DELETE /v1/user?userId=` |

All `/v1` calls send `Authorization: Bearer <token>`.

## Design invariants honored

- The score owns the decision. The app never computes or upgrades it; it renders
  `today.decision` and shows a locked **DecisionChip** in Ask Coach so the user
  always sees the constraint the coach must respect.
- Read-only HealthKit: authorization requests an empty share set.
- Missing signals surface a low-confidence banner; calibrating state is shown.
- No Watch app, no local LLM (kept out of scope per the plan).

## Device acceptance checklist (Task 11–12)

1. Grant HealthKit → first sync uploads real samples (verify counts in the sync
   summary or `prisma studio`).
2. Today shows the same decision + pillars as the web dashboard.
3. Ask Coach never contradicts a `recover` lock.
4. Missing data stays low-confidence and conservative.
