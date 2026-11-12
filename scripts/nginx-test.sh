#!/usr/bin/env bash
# Runs `nginx -t` on nginx/*.conf in a container that matches the VPS
# (nginx 1.24). The configs reference Let's Encrypt files that only exist on
# the VPS, so throwaway self-signed certs are generated at the same paths.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

: > "$tmp/options-ssl-nginx.conf"
grep -ho '/etc/letsencrypt/live/[^/]*' nginx/*.conf | sort -u | while read -r dir; do
  name="${dir##*/}"
  mkdir -p "$tmp/live/$name"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 -subj "/CN=$name" \
    -keyout "$tmp/live/$name/privkey.pem" -out "$tmp/live/$name/fullchain.pem" 2>/dev/null
done

docker run --rm \
  -v "$PWD/nginx:/etc/nginx/conf.d:ro" \
  -v "$tmp:/etc/letsencrypt:ro" \
  nginx:1.24-alpine nginx -t
