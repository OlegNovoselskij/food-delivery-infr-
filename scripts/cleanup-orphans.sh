#!/usr/bin/env bash
# Delete storage objects that no database row refers to (uploads that were never confirmed).
# Usage: scripts/cleanup-orphans.sh [--dry-run]
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--dry-run" ]; }; then
  echo "Usage: $0 [--dry-run]" >&2
  exit 1
fi

docker compose --env-file .env.production -f docker-compose.prod.yml exec -T backend \
  python -m app.scripts.cleanup_orphans "$@"
