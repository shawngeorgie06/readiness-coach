# Personal free deploy (Render + Neon, no laptop server)

Use this when you want the iPhone app to work day-to-day **without** leaving
your Mac running the API. You still re-sign the iOS app from Xcode about once a
week (free Apple ID limit) — that is separate from hosting.

## What you get

| Piece | Free setup |
|-------|------------|
| Phone app | Same Readiness Coach UI (Today, Sleep, Insights, …) |
| API + DB | Render (API) + Neon (Postgres) |
| Cost | $0 |
| Stay awake | Keep-alive pings every ~10 min so free Render does **not** die after 15 min idle |

## Stay awake (the 15‑minute fix)

Free Render spins down after **15 minutes with no inbound HTTP**. Same idea as
a keep-alive “proxy” ping on other projects:

1. **In the API** — on Render, `RENDER_EXTERNAL_URL` is set automatically. The
   process pings its own `/health` every 10 minutes while it’s up.
2. **From GitHub Actions** — workflow `.github/workflows/render-keepalive.yml`
   pings `/health` every 10 minutes even if the service went cold (wakes it).

After deploy, add a GitHub Actions secret:

| Secret | Value |
|--------|--------|
| `RENDER_HEALTH_URL` | `https://<your-service>.onrender.com/health` |

Optional backup: [cron-job.org](https://cron-job.org) → GET that same URL every 10 minutes.

## 1. Free Postgres (Neon)

1. Create a free account at [https://neon.tech](https://neon.tech) (or reuse one).
2. Create a project (any region near you).
3. Copy the connection string (`DATABASE_URL`). Prefer the **pooled** URL if Neon shows one.

## 2. Free API host (Render — you already have an account)

1. Make sure this repo is on GitHub `main` (with the Dockerfile).
2. In Render: **New → Web Service** → connect `readiness-coach`.
3. Settings:
   - **Runtime:** Docker
   - **Root directory:** `backend`
   - **Dockerfile path:** `./Dockerfile`
   - **Instance:** Free
4. Environment variables:

| Key | Value |
|-----|--------|
| `DATABASE_URL` | Neon connection string |
| `API_TOKEN` | Long random secret (same value you type into the iPhone app) |
| `API_TOKEN_USER_ID` | **Same User ID** as in the iPhone app (Settings / onboarding). Required — the shared token only works for this user |
| `SESSION_SECRET` | Long random secret (≥32 chars); Render can generate |
| `APPLE_BUNDLE_ID` | Your app bundle id (e.g. `com.readinesscoach.app`) |
| `LLM_API_KEY` | Optional OpenAI key for Ask Coach |
| `LLM_BASE_URL` | `https://api.openai.com/v1` |
| `LLM_MODEL` | `gpt-4o-mini` |

Render injects `PORT` and `RENDER_EXTERNAL_URL` itself.

5. Deploy. When healthy, open:

```text
https://<your-service>.onrender.com/health
```

You want `{ "ok": true }`.

Migrations run automatically on container start (`prisma migrate deploy`).

6. Add the `RENDER_HEALTH_URL` GitHub secret (see above) so the keep-alive Action can run.

## 3. Point the iPhone app at it

1. Xcode → Run on your iPhone (free personal team is fine).
2. Onboarding / Settings:
   - **API URL:** `https://<your-service>.onrender.com` (no trailing slash)
   - **API token:** same as `API_TOKEN`
   - **User ID:** keep the prefilled UUID forever (don’t change it later)
3. Allow HealthKit → **Start & sync**.

Use **HTTPS**. Do not use your Mac LAN IP anymore.

## 4. Daily use

- Open the app like any other app — with keep-alive it should stay warm.
- About once a week (free signing), if the icon won’t open: Mac → Xcode → Run again.

## 5. Shipping fixes later

```bash
git checkout main
git pull
# make the fix, commit, push
```

Render redeploys the API from GitHub. For the phone: Xcode → Run when you want the UI fix on-device.

## Optional: Ask Coach

Without `LLM_API_KEY`, Today still works (template advisor note). Ask Coach stays
unavailable until you add a key.

## If `/health` fails

- Confirm `DATABASE_URL` is set and Neon project is active.
- Check Render logs for Prisma migrate errors.
- Confirm `API_TOKEN` is at least 8 characters (backend requirement).
- Confirm GitHub secret `RENDER_HEALTH_URL` if the Action is skipping.
