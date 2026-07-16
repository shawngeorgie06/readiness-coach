#!/bin/sh
set -eu

echo "Running Prisma migrations..."
npx prisma migrate deploy

echo "Starting API on :${PORT:-4000}"
exec node dist/index.js
