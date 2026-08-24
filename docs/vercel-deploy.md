# Deploying the API to Vercel (free, no sleep)

Replaces the Render deploy. The database stays on Neon — only the API moves.

Why Vercel over Render free: Render's free web service sleeps after 15 minutes
idle, which is why this repo carries a keep-alive pinger and a GitHub Action.
Vercel runs the API as an on-demand function: nothing to keep warm, nothing to
spin up, and a personal-use workload stays inside the free Hobby plan.

## What changed in the repo

- `backend/api/index.ts` — serverless entrypoint. Exports the Express app as a
  handler instead of calling `app.listen`. `backend/src/index.ts` is untouched,
  so `npm run dev` and Docker still work exactly as before.
- `backend/vercel.json` — rewrites every path to that one function, so routing
  is still handled by Express.
- `backend/src/db.ts` — the Prisma client is cached on `globalThis` so warm
  invocations reuse one connection pool.
- `backend/prisma/schema.prisma` — added the `rhel-openssl-3.0.x` binary target
  (Vercel's runtime is Amazon Linux 2023; the local engine won't run there).
- `backend/package.json` — `postinstall: prisma generate` so the client is built
  during Vercel's install step.

## One-time setup

### 1. Use Neon's *pooled* connection string

This is the step that matters most. Each function invocation can open its own
Postgres connection, and Neon's direct endpoint will run out of them. In the
Neon dashboard copy the connection string with `-pooler` in the host, and append
a connection cap:

```
postgresql://USER:PASS@ep-xxxx-pooler.REGION.aws.neon.tech/DB?sslmode=require&connection_limit=1
```

Keep the **non-pooled** URL around separately — migrations need it.

### 2. Run migrations from your machine

Vercel's build step should not run migrations (builds can run concurrently and
the build environment isn't a good place to mutate your database). Run them
yourself against the direct, non-pooled URL:

```bash
cd backend
DATABASE_URL='postgresql://...ep-xxxx.REGION.aws.neon.tech/DB?sslmode=require' \
  npm run migrate:deploy
```

Re-run this any time you add a migration, before deploying.

### 3. Create the Vercel project

```bash
npm i -g vercel
cd ~/readiness-coach
vercel link          # create a new project when prompted
```

When it asks for the root directory, answer **`backend`**. If you created the
project through the dashboard instead, set Root Directory to `backend` under
Settings → General.

### 4. Set environment variables

Set each of these for the Production environment (Settings → Environment
Variables, or `vercel env add NAME production`):

| Variable | Value |
|---|---|
| `DATABASE_URL` | the **pooled** Neon URL from step 1 |
| `API_TOKEN` | your existing shared token |
| `API_TOKEN_USER_ID` | the user id that token is bound to |
| `SESSION_SECRET` | 32+ chars; reuse the Render value to keep sessions valid |
| `APPLE_BUNDLE_ID` | `com.readinesscoach.ReadinessCoach` |
| `LLM_API_KEY` | your OpenAI key |
| `LLM_BASE_URL` | `https://api.openai.com/v1` |
| `LLM_MODEL` | `gpt-4o-mini` |

`CORS_ORIGIN` is only needed if you serve the web app from a different origin.
`PORT` is not used on Vercel.

Pull the values off Render first if you don't have them saved — once you delete
the Render service the generated `SESSION_SECRET` is gone, and every existing
session token stops validating.

### 5. Deploy

```bash
vercel --prod
curl https://<your-project>.vercel.app/health
```

### 6. Point the phone at it

The iOS app reads its base URL from Settings (`AppSettings.apiBaseURL`), so you
can paste the new URL in the app without rebuilding. To change the shipped
default, edit `defaultBaseURL` in
`ios/ReadinessCoach/Settings/AppSettings.swift`.

## After it's working

Once you've confirmed the phone talks to Vercel, the Render scaffolding is dead
weight and can be deleted: `render.yaml`, the keep-alive GitHub Action, and
`backend/src/keepAlive.ts` (plus its call in `src/index.ts`). They're harmless
if left — `keepAlive` is inert unless `RENDER_EXTERNAL_URL` is set.

## Things to know about the free plan

- **Cold starts.** After idle, the first request takes roughly 0.5–1.5s while
  Prisma connects. Subsequent requests are fast. There is no 15-minute sleep
  penalty like Render.
- **`maxDuration` is 30s** (set in `vercel.json`). Long LLM coaching calls and
  big Health syncs need to finish inside that. If a full-history sync times out,
  the client's resumable sync will pick up where it left off.
- **Rate limiting is per-instance.** `express-rate-limit` uses in-memory state,
  so limits are enforced per warm function instance rather than globally. Fine
  for a single-user app; it is not a real defense if this ever goes public.
- **Hobby is non-commercial.** Personal use is what it's for.
