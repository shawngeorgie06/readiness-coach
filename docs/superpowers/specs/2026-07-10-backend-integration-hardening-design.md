# Backend Integration Hardening — Design Spec

**Date:** 2026-07-10  
**Status:** Approved for implementation planning

## Goal

Increase confidence in the production backend path by testing the real HTTP-to-PostgreSQL flow and adding essential process-health safeguards. This is a focused hardening pass; it does not expand product behavior or the database schema.

## Scope

### Included

- PostgreSQL-backed HTTP integration tests
- Authentication and request-validation coverage
- Idempotent health-data sync coverage
- End-to-end `POST /v1/sync` to `GET /v1/today` coverage
- Database-aware readiness health check
- Graceful HTTP and Prisma shutdown
- Explicit test-database setup and cleanup safeguards

### Deferred

- GitHub Actions CI
- Rate limiting
- Helmet or other security-header middleware
- Restricted CORS policy
- Structured application logging and request IDs
- LLM-backed coach integration tests
- Product, API-contract, or Prisma schema changes

## Architecture

Split application construction from process startup:

1. An app factory creates and configures the Express application from explicit dependencies and configuration.
2. A thin server entry point loads environment variables, starts the HTTP listener, and owns process-signal handling.
3. Integration tests create the application without opening a network listener and exercise it through Supertest.
4. Tests use the real Prisma client and a dedicated PostgreSQL test database. The critical `HTTP → route → service → Prisma → PostgreSQL` path is not mocked.

Existing pure unit tests remain fast and independent of PostgreSQL.

## Test Database

Integration tests use `TEST_DATABASE_URL`, separate from the development `DATABASE_URL`. The expected local database name is `readiness_coach_test`.

Before destructive cleanup, the test harness must parse the configured URL and refuse to continue unless the database name ends with `_test`. This prevents accidental truncation of development or production data.

Suite setup runs `prisma migrate deploy` against the test database. Before each test, the harness truncates application tables in a foreign-key-safe operation and resets test state. Prisma disconnects after the suite.

## Integration Coverage

The focused suite covers:

1. `GET /health` returns `200` while PostgreSQL is reachable.
2. Protected routes return `401` without a bearer token.
3. Protected routes return `401` with an invalid bearer token.
4. A valid token reaches the protected route.
5. `POST /v1/sync` rejects an invalid payload with `400`.
6. A valid sync creates the user and supplied health records.
7. Repeating a sync with the same HealthKit UUID updates or preserves one record rather than creating a duplicate.
8. `GET /v1/today` returns `404` for an unknown user.
9. After valid synced data, `GET /v1/today` returns the documented readiness shape and persists a daily score.

Tests assert both HTTP responses and selected database rows where persistence or idempotency is part of the contract.

## Operational Behavior

### Health

`GET /health` executes a minimal PostgreSQL probe such as `SELECT 1`.

- Reachable database: `200` with `{ "ok": true }`
- Unreachable database: `503` with `{ "ok": false }`

The response does not expose connection details or raw errors.

### Shutdown

The production server handles `SIGINT` and `SIGTERM` once:

1. Stop accepting new HTTP connections.
2. Allow the server close callback to run.
3. Disconnect Prisma.
4. Exit successfully, or exit nonzero if shutdown fails.

Application construction remains free of process-level signal handlers so test instances cannot register duplicate handlers.

## Commands

- `npm test` runs the existing fast unit suite.
- `npm run test:integration` runs PostgreSQL-backed integration tests.
- `npm run test:all` runs unit and integration suites.
- `npx tsc --noEmit` verifies TypeScript.

The integration command requires PostgreSQL and `TEST_DATABASE_URL`. Setup instructions will document creating the local test database and using `127.0.0.1` on this Windows machine.

## Error Handling

- Test setup fails early with a clear message when `TEST_DATABASE_URL` is missing, malformed, or unsafe.
- Migration failure aborts the integration suite.
- Database health failures return a stable `503` response and log the internal error server-side.
- Shutdown is idempotent so repeated signals do not race multiple close/disconnect operations.

## Acceptance Criteria

1. Existing unit tests still pass.
2. Integration tests exercise the real Express, Prisma, migration, and PostgreSQL path.
3. Duplicate HealthKit UUID sync is proven idempotent in PostgreSQL.
4. A synced user can receive and persist a Today response through HTTP.
5. `/health` distinguishes a ready database from an unavailable database without leaking internals.
6. Production startup shuts down HTTP and Prisma cleanly on termination signals.
7. The integration harness cannot truncate a database whose name does not end with `_test`.
8. `npx tsc --noEmit` passes.

