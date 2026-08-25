#!/bin/zsh
# Deploy the readiness-coach API to family-host.
#
# Reads API_TOKEN, API_TOKEN_USER_ID and LLM_API_KEY out of backend/.env so you
# only have to type the two values that live nowhere on this machine.
set -eu

cd "$(dirname "$0")"

# Pull the three known values from backend/.env without echoing them.
eval "$(grep -E '^(API_TOKEN|API_TOKEN_USER_ID|LLM_API_KEY)=' backend/.env | sed 's/^/export /')"

echo "Use the NON-POOLED Neon URL (no '-pooler' in the host)."
echo "The container runs 'prisma migrate deploy' at startup and PgBouncer"
echo "does not support the advisory lock that needs."
echo
read -rs "DATABASE_URL?Neon DATABASE_URL (non-pooled): "; echo
read -rs "SESSION_SECRET?SESSION_SECRET (the one from Render): "; echo

case "$DATABASE_URL" in
  *-pooler*) echo "STOP: that is the pooled URL. Migrations will fail."; exit 1 ;;
  postgres*) ;;
  *) echo "STOP: that does not look like a postgres:// URL."; exit 1 ;;
esac
[ -n "$SESSION_SECRET" ] || { echo "STOP: SESSION_SECRET is empty."; exit 1; }

family-host deploy shawngeorgie06/readiness-coach \
  --name readiness-coach-api \
  --branch main \
  --build-pack dockerfile \
  --base-directory /backend \
  --port 4000 \
  --visibility public \
  --auto-deploy \
  --env "PORT=4000" \
  --env "DATABASE_URL=$DATABASE_URL" \
  --env "API_TOKEN=$API_TOKEN" \
  --env "API_TOKEN_USER_ID=$API_TOKEN_USER_ID" \
  --env "SESSION_SECRET=$SESSION_SECRET" \
  --env "APPLE_BUNDLE_ID=com.readinesscoach.ReadinessCoach" \
  --env "LLM_API_KEY=$LLM_API_KEY" \
  --env "LLM_BASE_URL=https://api.openai.com/v1" \
  --env "LLM_MODEL=gpt-4o-mini"
