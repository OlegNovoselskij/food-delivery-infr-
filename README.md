# Atrium infrastructure

Production setup: `docker-compose.prod.yml`, `Caddyfile` and the scripts in `scripts/`. Copy `.env.production.example` to
`.env.production` on the server and fill it in. Backend and frontend are cloned next to this repo as `../backend` and
`../frontend`.

## Scripts

- `scripts/deploy.sh` pulls both repos, rebuilds, runs migrations and restarts.
- `scripts/backup.sh` dumps Postgres and uploads the dump to the private bucket.
- `scripts/cleanup-orphans.sh [--dry-run]` removes storage objects that no database row refers to.

## Cost guards

R2 and Resend are used on their free tiers, so the backend limits itself:

- `STORAGE_QUOTA_BYTES` (default 8 GiB) caps the total size of videos, materials and covers. Uploads above it are refused
  with HTTP 507.
- `EMAIL_DAILY_LIMIT` (default 90) caps emails per UTC day. The rest waits in the queue until the next day.
- `S3_SIGN_CONTENT_LENGTH` (default true) makes the storage reject a file whose size differs from the declared one.

## Orphaned files

A file that was uploaded but never confirmed stays in the bucket and takes quota space in R2 (not in the database count).
Delete them with `scripts/cleanup-orphans.sh`. Only objects under `courses/` that are unknown to the database and older
than 7 hours (`STORAGE_ORPHAN_GRACE_SECONDS`) are removed. Look first:

```
scripts/cleanup-orphans.sh --dry-run
```

Run it every hour with cron (`crontab -e` on the server):

```
0 * * * * cd /opt/atrium/infra && ./scripts/cleanup-orphans.sh >> "$HOME/cleanup-orphans.log" 2>&1
```

Replace `/opt/atrium/infra` with the folder this repo is cloned to.
