#!/usr/bin/env bash
# Deploys a commit of this repo on the VPS, with health check and automatic rollback.
#
# Usage: deploy.sh [commit-sha]     (default: origin/main)
# GitHub Actions calls it over SSH; the deploy key is restricted in
# ~/.ssh/authorized_keys to run only this script, and the requested SHA
# arrives in SSH_ORIGINAL_COMMAND.
#
# Everything is inside main() so bash has parsed the whole script before
# `git reset` rewrites this file on disk.

set -euo pipefail

REPO_DIR="$HOME/grafana-stack"
HEALTH_URL="http://127.0.0.1:3000/api/health"
HEALTH_TRIES=30   # x 2s = 60s

log() { echo "[deploy] $*"; }

healthy() {
  local i
  for ((i = 1; i <= HEALTH_TRIES; i++)); do
    if curl -fsS --max-time 3 "$HEALTH_URL" 2>/dev/null | grep -q '"database": *"ok"'; then
      log "health check passed (attempt $i)"
      return 0
    fi
    sleep 2
  done
  log "health check FAILED after $((HEALTH_TRIES * 2))s"
  return 1
}

start() {
  docker compose config -q &&
  docker compose pull -q &&
  docker compose up -d --remove-orphans
}

main() {
  local target="${1:-${SSH_ORIGINAL_COMMAND:-}}"
  cd "$REPO_DIR"

  git fetch -q origin
  if [[ -z "$target" ]]; then
    target="$(git rev-parse origin/main)"
  elif [[ ! "$target" =~ ^[0-9a-f]{7,40}$ ]]; then
    log "refusing: '$target' is not a commit SHA"
    exit 2
  fi

  local previous
  previous="$(git rev-parse HEAD)"
  target="$(git rev-parse "$target^{commit}")"
  log "current: $previous"
  log "target:  $target"

  if [[ "$previous" == "$target" ]]; then
    log "already at target, verifying health only"
    healthy
    exit $?
  fi

  git reset -q --hard "$target"

  if ! git diff --quiet "$previous" "$target" -- nginx/; then
    log "WARNING: nginx/ changed; run on the VPS: sudo nginx -t && sudo systemctl reload nginx"
  fi

  if start && healthy; then
    log "deployed $target"
    docker image prune -f >/dev/null
    exit 0
  fi

  log "ROLLING BACK to $previous"
  git reset -q --hard "$previous"
  if start && healthy; then
    log "rollback succeeded; $target was NOT deployed"
  else
    log "ROLLBACK ALSO FAILED; manual action needed"
  fi
  exit 1
}

main "$@"
