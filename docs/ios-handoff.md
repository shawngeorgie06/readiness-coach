# iOS implementation handoff

Tasks 1–9 are complete and verified in this Windows environment. Tasks 10–12
require macOS with Xcode, plus a physical iPhone with HealthKit access and
Apple Watch data; they were intentionally not scaffolded or claimed complete
here.

## Before starting

- Run the backend with Postgres available and set `API_TOKEN` to a private
  value.
- Run `npm run seed:demo` in `backend` if a demo Today payload is needed before
  HealthKit sync is working.
- Use the API contract exposed by `/v1/today`, `/v1/sync`, `/v1/sleep`,
  `/v1/train`, `/v1/body`, and `/v1/coach/ask`.

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
- Exercise account-data deletion through the planned `DELETE /v1/user` route
  before release.
