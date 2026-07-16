# iOS implementation handoff

Tasks 1–9 are complete and verified. Tasks 10–12 are implemented under `ios/`
(SwiftUI iOS 17 app, HealthKit read-only sync, all six tabs, and the
strict-advisor Ask Coach lock). The app **compiles cleanly against the iOS SDK**
— verified with `xcodebuild` for the iOS Simulator (Debug, `** BUILD
SUCCEEDED **`) using Xcode 26.6 / iOS 26.5 SDK.

**Remaining — requires code signing + a physical device:** the app has not yet
been code-signed and run on hardware, and the HealthKit sync has not been
exercised against real Watch data (HealthKit is unavailable in the Simulator).
Open the project in Xcode, set your signing Team, run on a physical iPhone, and
work the acceptance checklist below. See `ios/README.md` for step-by-step setup.

Reproduce the build check:

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

## Complete Tasks 10–12 in order

1. Create the `ReadinessCoach` SwiftUI iOS 17 app, enable HealthKit, and add
   the required Health sharing usage descriptions. Implement the API client and
   persisted API settings.
2. Request read permissions for heart rate, resting heart rate, HRV SDNN,
   sleep analysis, and workouts. Sync only samples newer than the stored
   `lastSyncAt` value to `POST /v1/sync`.
3. Implement the Today, Sleep, Train, Body, Ask Coach, and Settings views.
   Keep the locked decision visible in Ask Coach and do not add a Watch app.
4. On a physical device, verify HealthKit authorization, real sample sync,
   Today population, and that Ask Coach cannot contradict a Recover decision.

## Required acceptance checks

- `GET /v1/today` shows the same decision and pillars after an iPhone sync as
  the web dashboard.
- Missing data remains low confidence and conservative.
- A Recover lock always remains Recover in advisor notes and Ask Coach output.
- Exercise account-data deletion through `DELETE /v1/user?userId=<id>` before
  release (implemented; deletes the user and all associated health samples,
  workouts, daily scores, and advisor notes; returns 404 for an unknown user).
