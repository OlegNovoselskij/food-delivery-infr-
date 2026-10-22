#!/usr/bin/env bash
# Deploy a prebuilt backend image: pull it, migrate, restart, check health, roll back on failure.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="${1:?usage: deploy-image.sh <image-ref>}"
if ! [[ "$IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+:[A-Za-z0-9._-]+$ ]]; then
  echo "Refusing to deploy an unexpected image reference: $IMAGE" >&2
  exit 1
fi

ENV_FILE=.env.production
COMPOSE=(docker compose --env-file "$ENV_FILE" -f docker-compose.prod.yml)

current_image() {
  grep -E '^BACKEND_IMAGE=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true
}

set_image() {
  if grep -qE '^BACKEND_IMAGE=' "$ENV_FILE"; then
    sed -i "s|^BACKEND_IMAGE=.*|BACKEND_IMAGE=$1|" "$ENV_FILE"
  else
    echo "BACKEND_IMAGE=$1" >> "$ENV_FILE"
  fi
}

wait_ready() {
  for _ in $(seq 1 40); do
    if "${COMPOSE[@]}" exec -T backend python -c \
      "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/ready', timeout=3)" 2>/dev/null; then
      return 0
    fi
    sleep 3
  done
  return 1
}

PREVIOUS="$(current_image)"
echo "Deploying $IMAGE (previous: ${PREVIOUS:-local build})"

set_image "$IMAGE"

if ! "${COMPOSE[@]}" pull backend; then
  set_image "$PREVIOUS"
  echo "Could not pull the image, nothing was changed" >&2
  exit 1
fi

if ! "${COMPOSE[@]}" run --rm backend alembic upgrade head; then
  set_image "$PREVIOUS"
  echo "Migration failed, the running version was not touched" >&2
  exit 1
fi

"${COMPOSE[@]}" up -d --no-build backend worker

if ! wait_ready; then
  echo "New version did not become ready, rolling back" >&2
  "${COMPOSE[@]}" logs --tail 60 backend >&2 || true
  set_image "$PREVIOUS"
  "${COMPOSE[@]}" up -d --no-build backend worker
  exit 1
fi

docker image prune -af --filter "until=168h" >/dev/null || true
"${COMPOSE[@]}" ps
echo "Deployed $IMAGE"