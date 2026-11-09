# Deploying the API to Vercel

The API runs on Vercel's free Hobby plan as the `readiness-coach-api` project,
backed by the Neon project **Readiness Coach Fresh** (`aws-us-east-1`).

- App: <https://readiness-coach-api.vercel.app>
- Health (checks the database too): <https://readiness-coach-api.vercel.app/health>

## How it fits together

- `backend/api/index.ts` exports the Express app as a Vercel function.
  `backend/src/index.ts` (the long-running server) is unchanged, so
  `npm run dev` and Docker still work locally.
- `backend/vercel.json` rewrites every path to that one function, so Express
  still does the routing. `maxDuration` is 30s.
- `backend/src/db.ts` caches the Prisma client on `globalThis`, and
  `prisma/schema.prisma` ships the `rhel-openssl-3.0.x` engine for Vercel's
  runtime.
- The Vercel project's root directory is `backend`.

## Environment variables (Production)

| Variable | Value |
|---|---|
| `DATABASE_URL` | Neon **pooled** URL (`-pooler` host) with `&connection_limit=1` |
| `API_TOKEN` | shared bearer token; the iOS app's `Secrets.defaultAPIToken` |
| `API_TOKEN_USER_ID` | user id that token is bound to |
| `SESSION_SECRET` | 32+ random chars |
| `APPLE_BUNDLE_ID` | `com.readinesscoach.ReadinessCoach` |
| `LLM_API_KEY`, `LLM_BASE_URL`, `LLM_MODEL` | coach model provider |

Set values over stdin so they stay out of shell history:

```bash
cd backend
printf '%s' "$VALUE" | vercel env add NAME production
```

To change an existing value, `vercel env rm NAME production --yes` first, then
add it again. Redeploy after any change.

## Migrations

Run migrations from your machine against Neon's **direct** (non-pooled) URL,
before deploying code that needs them:

```bash
cd backend
DATABASE_URL="$(neonctl connection-string --project-id <id>)" npm run migrate:deploy
```

## Deploying

```bash
cd backend
vercel deploy --prod
curl https://readiness-coach-api.vercel.app/health
```

Merges to `main` do not deploy automatically yet. To turn that on, install the
Vercel GitHub app for this repository (Vercel dashboard → project → Settings →
Git) and connect it; the project's root directory is already `backend`.

## Free plan notes

- The first request after idle takes about a second while Prisma connects.
- Requests must finish within 30s, including Ask Coach model calls.
- `express-rate-limit` state is per function instance.
- Hobby is for non-commercial use.
