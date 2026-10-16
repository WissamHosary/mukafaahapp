#!/usr/bin/env bash
# Builds the Netlify site: the Manager at /admin, and /v1/* passed on to the API.
set -euo pipefail
OUT=web-dist
rm -rf "$OUT" && mkdir -p "$OUT/admin"
cp backend/admin/* "$OUT/admin/"

API="${API_URL:-}"
API="${API%/}"
{
  echo "/            /admin/                 302"
  if [ -n "$API" ]; then
    # Status 200 = Netlify fetches it from the API for the browser (same origin, no CORS).
    echo "/v1/*        $API/v1/:splat          200!"
    echo "/health      $API/health             200!"
  else
    echo "/v1/*        /admin/no-server.json   503!"
  fi
} > "$OUT/_redirects"

cat > "$OUT/_headers" <<'H'
/admin/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: same-origin
  Cache-Control: no-cache
  Content-Security-Policy: default-src 'self'; img-src 'self' data: blob: https://tile.openstreetmap.org; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self'; connect-src 'self'; frame-ancestors 'none'
H

if [ -z "$API" ]; then
  echo '{"code":"NO_SERVER","message":"The Mukafaah server address is not set. In Netlify, add the API_URL environment variable and redeploy."}' > "$OUT/admin/no-server.json"
  echo "WARNING: API_URL is not set, so sign-in will not work until it is."
fi
echo "Built $OUT (API: ${API:-not set})"
ls -la "$OUT" "$OUT/admin"
