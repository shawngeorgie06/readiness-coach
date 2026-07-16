# Personal free deploy (no laptop server)

Use this when you want the iPhone app to work day-to-day **without** leaving
your Mac running the API. You still re-sign the iOS app from Xcode about once a
week (free Apple ID limit) — that is separate from hosting.

## What you get

| Piece | Free setup |
|-------|------------|
| Phone app | Same Readiness Coach UI (Today, Sleep, Insights, …) |
| API + DB | Hosted in the cloud (not your laptop) |
| Cost | $0 on the free path below |
| Catch | Free Render **sleeps when idle** — first open after a while can take 30–60s |

After wake-up it works like a normal app: sync HealthKit, see readiness, Ask Coach
(if you set an LLM key).

> Truly always-on free hosting for Node + Postgres is basically gone in 2026.
> This path stays free; cold start is the tradeoff. A cheap always-on host
> (~a few dollars/month) removes the sleep delay if you ever want that later.

## 1. Free Postgres (Neon)

1. Create a free account at [https://neon.tech](https://neon.tech).
2. Create a project (any region near you).
3. Copy the connection string (`DATABASE_URL`). Prefer the **pooled** URL if Neon shows one.

## 2. Free API host (Render)

1. Push this repo to GitHub (you already have it).
2. Sign up at [https://render.com](https://render.com) with GitHub (no card required for free).
3. **New → Blueprint** → select `readiness-coach` → it should pick up `render.yaml`.
   - Or **New → Web Service** → connect the repo → Docker → root directory `backend`.
4. Set environment variables:

| Key | Value |
|-----|--------|
| `DATABASE_URL` | Neon connection string |
| `API_TOKEN` | Long random secret (you type the same into the iPhone app) |
| `PORT` | `4000` (Render may also inject `PORT` — the app reads it) |
| `LLM_API_KEY` | Optional OpenAI key for Ask Coach |
| `LLM_BASE_URL` | `https://api.openai.com/v1` |
| `LLM_MODEL` | `gpt-4o-mini` |

5. Deploy. When healthy, open:

```text
https://<your-service>.onrender.com/health
```

You want `{ "ok": true }`.

Migrations run automatically on container start (`prisma migrate deploy`).

## 3. Point the iPhone app at it

1. Xcode → Run on your iPhone (free personal team is fine).
2. Onboarding / Settings:
   - **API URL:** `https://<your-service>.onrender.com` (no trailing slash)
   - **API token:** same as `API_TOKEN`
   - **User ID:** keep the prefilled UUID forever (don’t change it later)
3. Allow HealthKit → **Start & sync**.

Use **HTTPS**. Do not use your Mac LAN IP anymore.

## 4. Daily use

- Open the app like any other app.
- If it was asleep, the first load may spin for up to about a minute — wait, then pull to refresh / sync again.
- About once a week (free signing), if the icon won’t open: Mac → Xcode → Run again.

## 5. Shipping fixes later

Still free and still your dedicated app:

```bash
git checkout main
git pull
# make the fix, commit, push
```

Render redeploys the API from GitHub. For the phone: Xcode → Run when you want the UI fix on-device (or after the weekly re-sign).

## Optional: Ask Coach

Without `LLM_API_KEY`, Today still works (template advisor note). Ask Coach stays
unavailable until you add a key.

## If `/health` fails

- Confirm `DATABASE_URL` is set and Neon project is active.
- Check Render logs for Prisma migrate errors.
- Confirm `API_TOKEN` is at least 8 characters (backend requirement).
