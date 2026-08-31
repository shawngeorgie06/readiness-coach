# Family Host deployment and Neon migration

The Readiness Coach API is already live and healthy at:

- App: <https://readiness-coach-api-shawngeorgie06.georgenijo.com>
- Health: <https://readiness-coach-api-shawngeorgie06.georgenijo.com/health>

The deployed container is built from this repository's `backend/Dockerfile`.
Family Host can also provision PostgreSQL, inject `DATABASE_URL`, run the
declared Prisma migration, retain backups, and restore the database with the
application. Neon is the last external hosting dependency.

This is a short data migration, not a rebuild.

## See the complete deployment plan safely

Authenticate and run the helper without arguments. It uses an installed
Family Host CLI when available and otherwise runs the official package with
Node.js 18+:

```bash
npx -y https://family.georgenijo.com/cli.tgz login
./deploy-family-host.sh
```

If `family-host` is already installed, `family-host update` gets the current
release and `family-host whoami` confirms the signed-in account.

The helper defaults to `--dry-run`. It shows the detected Docker build, port,
health check, managed PostgreSQL dependency, environment variables, and Prisma
migration without creating or changing anything. The GitHub repository must be
available to the GitHub account connected to Family Host.

`./deploy-family-host.sh --deploy` is only for a brand-new installation. It
refuses to create another `readiness-coach-api` when one already exists, and it
never imports, replaces, or deletes production data.

## What Shawn needs to do

1. Approve a brief write freeze for the final cutover.
2. Securely provide temporary access to a **non-pooled** Neon export connection
   string. Do not paste it into GitHub, a pull request, or chat.
3. After the switch, use the iPhone app to verify sign-in/onboarding, HealthKit
   sync, the Today score, history, and Ask Coach (when an LLM key is configured).

That is the entire owner-facing migration. Shawn does not need to operate
Docker, SSH, Coolify, Cloudflare, `pg_restore`, or Family Host database admin
credentials.

## What George and Family Host handle

Before the final cutover:

1. Create a managed PostgreSQL database for the existing app.
2. Rehearse the Neon export/import against a detached database.
3. Compare schema, migration history, and important row counts.
4. Prove an off-guest backup can be restored.

During the approved cutover:

1. Pause writes to Neon.
2. Take a final export and import it into the rehearsed managed database.
3. Attach PostgreSQL to the existing Family Host app; Family Host supplies its
   internal `DATABASE_URL`.
4. Deploy the current commit, let `prisma migrate deploy` run, and verify
   `/health` plus the core API flows.
5. Keep Neon unchanged during a short observation period.

If verification fails before writes reopen, switch the app back to Neon. Once
new writes are accepted on Family Host, do not switch back without reconciling
the two databases.

## Application secrets

The managed database URL is not an owner-supplied secret. Family Host creates
and injects it. These application values still need to be present:

| Variable | Purpose |
|---|---|
| `API_TOKEN` | Shared API credential; at least 8 characters |
| `API_TOKEN_USER_ID` | Permanent iPhone app user ID |
| `SESSION_SECRET` | Session signing secret; at least 32 characters |
| `APPLE_BUNDLE_ID` | iOS bundle identifier |
| `LLM_API_KEY` | Optional; enables Ask Coach |
| `CORS_ORIGIN` | Optional browser origin |

`LLM_BASE_URL` and `LLM_MODEL` already have application defaults. Never commit
real secret values to this repository.

## Acceptance checklist

Do not retire Neon until all of these pass:

- The Family Host app reports healthy and `/health` returns `{ "ok": true }`.
- Prisma migration history and important table row counts match the final Neon
  export.
- The iPhone app can read existing history and create a new readiness record.
- HealthKit sync and Ask Coach behave as expected.
- A managed PostgreSQL backup has completed and a restore test has passed.

Keep `render.yaml`, `.github/workflows/render-keepalive.yml`, and the Neon
project intact through the observation period. Remove those legacy artifacts
in a later cleanup only after the managed backup/restore test succeeds.

## Shipping later releases

Once the migration is accepted, normal backend releases are stateless from the
owner's point of view: push a commit, let Family Host rebuild the app, watch the
deployment phases, and keep the attached PostgreSQL data in place. Prisma
applies any new committed migrations during startup.

The iPhone still needs Xcode signing and a physical device for HealthKit. Its
API URL remains the Family Host URL above, with the same `API_TOKEN` and
permanent user ID.
