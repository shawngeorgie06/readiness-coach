# Fixture API

A dependency-free local stand-in for the Readiness Coach API. It serves deterministic synthetic data (no real health data) so the simulator app can be exercised and timed without a database.

```
FIXTURE_SCENARIO=normal FIXTURE_LATENCY_MS=250 node ios/Fixtures/server.mjs
```

It listens on `127.0.0.1:8787` (override with `FIXTURE_PORT`).

- `FIXTURE_SCENARIO`: `normal` (default), `empty` (new user, no data), `error` (every `/v1` call returns 500), `lowconf` (low confidence, missing signals), `calibrating`, `pending` (tonight's sleep not happened yet).
- `FIXTURE_LATENCY_MS`: artificial delay on every request (default 0). Use 250 to approximate production.

Endpoints: `/health`, `/v1/today` (includes `baselines`), `/v1/body`, `/v1/sleep`, `/v1/train`, `/v1/history`, `/v1/coach/ask`, plus `/v1/sync` and `DELETE /v1/user` so sign-in and sync do not fail. Any bearer token is accepted. `/v1` reads send `Cache-Control: private, no-store` and a weak `ETag`, and answer `If-None-Match` with 304.

## Pointing the simulator app at it

In onboarding, open Advanced and set API URL `http://127.0.0.1:8787`, any API token, and user ID `fixture-user`. `NSAllowsLocalNetworking` is already set in `Info.plist`.

To skip onboarding taps, write the same values into the simulator's defaults (the token is a Keychain item, so it still needs to be typed once, or compiled in through the gitignored `Secrets.swift`):

```
xcrun simctl spawn booted defaults write com.readinesscoach.ReadinessCoach apiBaseURL http://127.0.0.1:8787
xcrun simctl spawn booted defaults write com.readinesscoach.ReadinessCoach userId fixture-user
xcrun simctl spawn booted defaults write com.readinesscoach.ReadinessCoach hasCompletedOnboarding -bool YES
```

## Reading the perf signposts

```
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.readinesscoach.ReadinessCoach"'
```

Lines look like `perf LaunchToToday 412.3ms` and `perf TabSwitch.sleep 180.5ms`.
