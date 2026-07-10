# Readiness Coach Backend

## Prerequisites

- Node.js 20 or newer
- Docker Desktop or PostgreSQL 16

## Development setup

1. Copy `.env.example` to `.env`.
2. Set `DATABASE_URL` and a private `API_TOKEN`.
3. Set `CORS_ORIGIN` to the web dashboard's origin (e.g. `http://localhost:5173`). Leave unset to reject all cross-origin browser requests.
4. On Windows, use `127.0.0.1` instead of `localhost` if Prisma cannot reach PostgreSQL.
5. Run `npm install`.
6. From the repository root, run `docker compose up -d`.
7. In `backend`, run `npx prisma migrate deploy`.
8. Start the API with `npm run dev`.

## Security

- Helmet sets standard security response headers.
- CORS is deny-by-default; only the origin in `CORS_ORIGIN` may make cross-origin requests.
- `/v1/*` is rate-limited (300 requests / 15 min per IP by default) in addition to bearer-token auth.

## Tests

Unit tests do not require PostgreSQL:

```powershell
npm test
```

Create the dedicated integration database once:

```powershell
docker compose exec db createdb -U postgres readiness_coach_test
```

Set the safe test URL and run integration tests:

```powershell
$env:TEST_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/readiness_coach_test"
npm run test:integration
```

Run all tests and TypeScript:

```powershell
npm run test:all
npx tsc --noEmit
```

The integration harness refuses to run destructive cleanup unless the database
name ends with `_test`.
