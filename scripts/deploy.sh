#!/usr/bin/env bash
# Manual deploy: pull code, rebuild images, run migrations, restart, wait until the API is ready.
set -euo pipefail

cd "$(dirname "$0")/.."
COMPOSE=(docker compose --env-file .env.production -f docker-compose.prod.yml)

if [ ! -f .env.production ]; then
  echo "Missing .env.production (copy .env.production.example and fill it in)" >&2
  exit 1
fi

if [ "${SKIP_PULL:-0}" != "1" ]; then
  for repo in ../backend ../frontend; do
    [ -d "$repo/.git" ] && git -C "$repo" pull --ff-only
  done
fi

"${COMPOSE[@]}" build
"${COMPOSE[@]}" up -d db valkey
"${COMPOSE[@]}" run --rm backend alembic upgrade head
"${COMPOSE[@]}" up -d --remove-orphans

echo "Waiting for /health/ready ..."
for _ in $(seq 1 30); do
  if "${COMPOSE[@]}" exec -T backend python -c \
    "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/ready', timeout=3)" 2>/dev/null; then
    echo "Backend is ready"
    "${COMPOSE[@]}" ps
    docker image prune -f >/dev/null
    exit 0
  fi
  sleep 2
done

echo "Backend did not become ready; last logs:" >&2
"${COMPOSE[@]}" logs --tail 60 backend >&2
exit 1
