# Readiness Coach — iOS app

SwiftUI iOS 17 app that reads HealthKit data, syncs it to the Readiness Coach
API, and shows the locked readiness decision plus the strict advisor note.

**HealthKit does not work in the Simulator.** Run on a **physical iPhone**.

## Run on your iPhone (not Simulator)

### 1. Mac prep

- macOS with **Xcode 16+**
- Your iPhone on the **same Wi‑Fi** as the Mac
- Backend running on the Mac (from repo root):

```bash
docker compose up -d
cd backend && cp -n .env.example .env && npm install && npx prisma migrate deploy && npm run seed:demo && npm run dev
```

When the API starts it listens on `0.0.0.0:4000`. Find your Mac’s LAN IP:

```bash
ipconfig getifaddr en0   # or System Settings → Network → Wi‑Fi → Details
```

Example API URL for the phone: `http://192.168.1.42:4000`  
(Use the real IP. **Do not use `localhost` / `127.0.0.1` on a physical phone.**)

### 2. Open & sign the app

```bash
git checkout cursor/ios-physical-device-2e3f   # or pull this PR branch
open ios/ReadinessCoach.xcodeproj
```

1. Select the **ReadinessCoach** target → **Signing & Capabilities**.
2. Check **Automatically manage signing** and pick your **Team** (personal Apple ID is fine for a development install).
3. If the bundle id `com.readinesscoach.ReadinessCoach` is already taken on your team, change it to something unique (e.g. `com.yourname.ReadinessCoach`).
4. HealthKit entitlement is already in `ReadinessCoach.entitlements`.

### 3. Destination = your iPhone

1. Unlock the phone, trust the computer if asked.
2. In Xcode’s run destination menu (top toolbar), pick **your iPhone** — not any Simulator.
3. Press **Run (⌘R)**.
4. On the phone: Settings → General → VPN & Device Management → trust your developer certificate if iOS prompts.

### 4. First launch (Onboarding)

1. **API URL** — `http://<Mac-LAN-IP>:4000` (placeholder shows the pattern; fill your real IP).
2. **API token** — same value as backend `API_TOKEN` in `backend/.env`.
3. Tap **Test connection** (should succeed before you continue).
4. Tap **Allow Health access** and grant reads.
5. Tap **Start & sync**.

When iOS asks for **Local Network** access, allow it — that is how the phone reaches your Mac API.

### Quick failure checklist

| Symptom | Fix |
|--------|-----|
| Destination only shows Simulators | Plug in / wireless-pair the iPhone; unlock it; enable Developer Mode (iOS 16+: Settings → Privacy & Security → Developer Mode) |
| Signing / Team errors | Select a Team under Signing & Capabilities |
| Test connection fails | Same Wi‑Fi; Mac firewall allows Node; URL uses LAN IP not localhost; backend is running |
| Health / empty Today | Physical device only; grant Health read access; Watch data synced to iPhone Health |
| Local Network denied | Settings → Readiness Coach → Local Network → On |

## Requirements

- **macOS with Xcode 16 or newer** (file-system-synchronized groups, `objectVersion = 77`). Older Xcode: regenerate with XcodeGen (below).
- Physical iPhone with HealthKit data (ideally paired Apple Watch).
- Backend reachable from the device with a private `API_TOKEN`.

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

## Device acceptance checklist

1. Run destination is your physical iPhone (not Simulator).
2. Grant HealthKit → first sync uploads real samples.
3. Today shows the same decision + pillars as the web dashboard.
4. Ask Coach never contradicts a `recover` lock.
5. Missing data stays low-confidence and conservative.
