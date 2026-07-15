# iOS implementation handoff

Tasks 1–9 and the SwiftUI iOS app under `ios/` are implemented. **Run on a
physical iPhone** — HealthKit is unavailable in the Simulator.

## Run on hardware (required)

Full checklist: [`ios/README.md`](../ios/README.md). Short version:

1. Start the API on your Mac (`npm run dev` in `backend` — binds `0.0.0.0:4000`).
2. `open ios/ReadinessCoach.xcodeproj` → Signing & Capabilities → set **Team**.
3. Choose your **iPhone** as the run destination (not Simulator) → ⌘R.
4. Onboarding: API URL = `http://<Mac-LAN-IP>:4000` (not localhost), matching
   `API_TOKEN`, Allow Health + Local Network, then Start & sync.

Optional compile check (Simulator compile only — does not exercise HealthKit):

```bash
cd ios
xcodebuild -project ReadinessCoach.xcodeproj -scheme ReadinessCoach \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Before starting

- Run the backend with Postgres available and set `API_TOKEN` to a private
  value.
- Run `npm run seed:demo` in `backend` if a demo Today payload is needed before
  HealthKit sync is working.
- Use the API contract exposed by `/v1/today`, `/v1/sync`, `/v1/sleep`,
  `/v1/train`, `/v1/body`, `/v1/coach/ask`, and `DELETE /v1/user`.

## Required acceptance checks (on device)

- `GET /v1/today` shows the same decision and pillars after an iPhone sync as
  the web dashboard.
- Missing data remains low confidence and conservative.
- A Recover lock always remains Recover in advisor notes and Ask Coach output.
- Exercise account-data deletion through `DELETE /v1/user?userId=<id>` before
  release (implemented; deletes the user and all associated health samples,
  workouts, daily scores, and advisor notes; returns 404 for an unknown user).
