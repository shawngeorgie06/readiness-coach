#!/bin/zsh
# Preview or create a fresh Readiness Coach API + PostgreSQL deployment on
# Family Host. Existing production data follows docs/personal-free-deploy.md;
# this helper never imports, replaces, or deletes a database.
set -eu

cd "$(dirname "$0")"

usage() {
  print "usage: ./deploy-family-host.sh [--dry-run|--deploy]"
  print
  print "The default is --dry-run and creates no resources."
}

mode="${1:---dry-run}"
case "$mode" in
  --dry-run|--deploy) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[[ "$#" -le 1 ]] || { usage >&2; exit 2; }

if command -v family-host >/dev/null; then
  cli=(family-host)
else
  command -v npx >/dev/null || {
    print -u2 "Node.js 18+ is required; see https://family.georgenijo.com/docs"
    exit 1
  }
  cli=(npx -y https://family.georgenijo.com/cli.tgz)
fi

"${cli[@]}" whoami >/dev/null

deploy=(
  "${cli[@]}" app deploy shawngeorgie06/readiness-coach
  --name readiness-coach-api
  --branch main
  --base-directory /backend
  --visibility public
  --database postgres
)

if [[ "$mode" == "--dry-run" ]]; then
  "${deploy[@]}" --dry-run
  print
  print "Nothing was deployed. Family Host supplies DATABASE_URL and runs the"
  print "declared Prisma migration. See docs/personal-free-deploy.md for the"
  print "already-live app's short Neon data migration."
  exit 0
fi

apps_json="$("${cli[@]}" --json apps)"
if python3 -c 'import json,sys; raise SystemExit(not any(app.get("name") == "readiness-coach-api" for app in json.load(sys.stdin)))' <<<"$apps_json"; then
  print -u2 "readiness-coach-api already exists; refusing a duplicate deployment."
  print -u2 "Use docs/personal-free-deploy.md to migrate its Neon data instead."
  exit 1
fi

: "${API_TOKEN:?export API_TOKEN before --deploy}"
: "${API_TOKEN_USER_ID:?export API_TOKEN_USER_ID before --deploy}"
: "${SESSION_SECRET:?export SESSION_SECRET before --deploy}"
: "${APPLE_BUNDLE_ID:?export APPLE_BUNDLE_ID before --deploy}"

[[ "${#API_TOKEN}" -ge 8 ]] || { print -u2 "API_TOKEN must be at least 8 characters"; exit 1; }
[[ "${#SESSION_SECRET}" -ge 32 ]] || { print -u2 "SESSION_SECRET must be at least 32 characters"; exit 1; }

deploy+=(
  --env "API_TOKEN=$API_TOKEN"
  --env "API_TOKEN_USER_ID=$API_TOKEN_USER_ID"
  --env "SESSION_SECRET=$SESSION_SECRET"
  --env "APPLE_BUNDLE_ID=$APPLE_BUNDLE_ID"
)
[[ -z "${LLM_API_KEY:-}" ]] || deploy+=(--env "LLM_API_KEY=$LLM_API_KEY")
[[ -z "${CORS_ORIGIN:-}" ]] || deploy+=(--env "CORS_ORIGIN=$CORS_ORIGIN")

"${deploy[@]}"
