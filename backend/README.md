# Readiness Coach Backend

## Prerequisites

- Node.js 20 or newer
- Docker Desktop or PostgreSQL 16

## Development setup

1. Copy `.env.example` to `.env`.
2. Set `DATABASE_URL` and a private `API_TOKEN`.
3. On Windows, use `127.0.0.1` instead of `localhost` if Prisma cannot reach PostgreSQL.
4. Run `npm install`.
5. From the repository root, run `docker compose up -d`.
6. In `backend`, run `npx prisma migrate deploy`.
7. Start the API with `npm run dev`.

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
