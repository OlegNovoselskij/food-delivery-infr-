#!/usr/bin/env bash
# Dump Postgres, keep 7 local copies, upload the dump to the private R2 bucket under backups/.
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
. ./.env.production
set +a

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FILE="atrium-$STAMP.sql.gz"
mkdir -p "$BACKUP_DIR"

docker compose --env-file .env.production -f docker-compose.prod.yml exec -T db \
  pg_dump -U atrium --no-owner atrium | gzip > "$BACKUP_DIR/$FILE"

if [ ! -s "$BACKUP_DIR/$FILE" ]; then
  echo "Backup file is empty" >&2
  rm -f "$BACKUP_DIR/$FILE"
  exit 1
fi

docker run --rm \
  -v "$BACKUP_DIR:/backups:ro" \
  -e AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
  -e AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
  -e AWS_DEFAULT_REGION=auto \
  -e AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
  -e AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
  amazon/aws-cli s3 cp "/backups/$FILE" "s3://$R2_PRIVATE_BUCKET/backups/$FILE" \
  --endpoint-url "https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"

find "$BACKUP_DIR" -name 'atrium-*.sql.gz' -mtime +7 -delete
echo "Backup done: $FILE"
