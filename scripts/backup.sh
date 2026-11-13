#!/usr/bin/env bash
# Nightly backup of this stack: Grafana's SQLite database (users, orgs,
# preferences, dashboards made in the UI, alerting) plus the stack's .env,
# packed as one tar.gz. Provisioned data sources and dashboards live in git.
# Prometheus and Loki data are not backed up (metrics/logs, short retention).
#
# The grafana image has no sqlite3, so the file is copied out with
# `docker cp` and the copy is checked with PRAGMA integrity_check; a copy
# taken mid-write fails the check and is retried.
#
# Restore (replaces the current Grafana database):
#   tar -xzf ~/backups/grafana/grafana-<timestamp>.tar.gz -C /tmp grafana.db
#   cd ~/grafana-stack && docker compose stop grafana
#   docker cp /tmp/grafana.db "$(docker compose ps -aq grafana)":/var/lib/grafana/grafana.db
#   docker compose start grafana && rm /tmp/grafana.db

set -euo pipefail

REPO_DIR="$HOME/grafana-stack"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/grafana}"
KEEP_DAYS="${KEEP_DAYS:-14}"

umask 077
mkdir -p "$BACKUP_DIR"
cd "$REPO_DIR"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

container="$(docker compose ps -q grafana)"
ok=""
for attempt in 1 2 3; do
  rm -f "$work/grafana.db"
  docker cp -q "$container:/var/lib/grafana/grafana.db" "$work/grafana.db"
  if python3 -I -c 'import sqlite3,sys; c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True); sys.exit(0 if c.execute("PRAGMA integrity_check").fetchone()[0]=="ok" else 1)' "$work/grafana.db"; then
    ok=1
    break
  fi
  echo "backup: grafana.db copy failed integrity_check (attempt $attempt), retrying" >&2
  sleep 5
done
[[ -n "$ok" ]] || { echo "backup: no consistent copy of grafana.db" >&2; exit 1; }
cp .env "$work/.env"

out="$BACKUP_DIR/grafana-$ts.tar.gz"
tar -czf "$out.part" -C "$work" grafana.db .env
mv "$out.part" "$out"
find "$BACKUP_DIR" -name 'grafana-*.tar.gz' -mtime +"$KEEP_DAYS" -delete
echo "backup: $out ($(du -h "$out" | cut -f1))"
