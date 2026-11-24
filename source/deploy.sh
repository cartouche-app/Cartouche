#!/usr/bin/env bash
# Deploys the Worker cartouche-source (README.md), which answers at
# https://source.cartouche.cloud/ with Cartouche's source for the player's
# own SideStore, to the Cloudflare account CLOUDFLARE_ACCOUNT_ID with the
# API token CLOUDFLARE_API_TOKEN, through Cloudflare's API, with curl and jq
# and nothing else:
#
# 1. the Worker, worker.js as it is, with no binding and no logs kept;
# 2. no workers.dev address: it answers at its domain alone;
# 3. what https://source.cartouche.cloud/ answers: the source, or a warning
#    with what attaches the domain to the Worker, once, in Cloudflare's
#    dashboard. The token the deploy has cannot do it: attaching a domain
#    takes Zone › Workers Routes › Edit, and its DNS record Cloudflare's own.
#
# Without the two variables it says so and does nothing: they are secrets of
# the repository's environment cloudflare, the telemetry's
# (telemetry/README.md), which .github/workflows/site.yml deploys from.
#
#     CLOUDFLARE_API_TOKEN=… CLOUDFLARE_ACCOUNT_ID=… source/deploy.sh
#
# The token needs Account › Workers Scripts › Edit.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=cartouche-source
HOST=source.cartouche.cloud
# The Workers runtime worker.js is written for.
COMPATIBILITY_DATE=2026-09-01
# What a player adds to SideStore; the tests give a stand-in's.
ADDRESS="${CARTOUCHE_SOURCE_ADDRESS:-https://$HOST/}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] || [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  echo "::notice::No CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID: the source's Worker is not deployed."
  exit 0
fi

# CLOUDFLARE_API stands in for Cloudflare's API in the tests (test/test_deploy.py).
API="${CLOUDFLARE_API:-https://api.cloudflare.com/client/v4}/accounts/$CLOUDFLARE_ACCOUNT_ID"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The token goes to curl in a file, never on a command line.
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN" >"$WORK/authorization"

# call METHOD PATH [CURL ARGUMENTS...]: Cloudflare's result, or its errors
# and the end of the deploy.
call() {
  local method="$1" path="$2"
  shift 2
  if ! curl -sS -o "$WORK/answer.json" -X "$method" -H @"$WORK/authorization" "$@" "$API$path" ||
    ! jq -e '.success == true' "$WORK/answer.json" >/dev/null 2>&1; then
    echo "Cloudflare refused $method $path:" >&2
    jq -r '.errors[]? | "  \(.code): \(.message)"' "$WORK/answer.json" >&2 2>/dev/null || cat "$WORK/answer.json" >&2
    exit 1
  fi
}

# 1. The Worker.
echo "Uploading the Worker $NAME"
jq -n --arg date "$COMPATIBILITY_DATE" '{
  main_module: "worker.js",
  compatibility_date: $date,
  bindings: [],
  observability: {enabled: false}
}' >"$WORK/metadata.json"
call PUT "/workers/scripts/$NAME" \
  -F "metadata=@$WORK/metadata.json;type=application/json" \
  -F "worker.js=@$HERE/worker.js;type=application/javascript+module"

# 2. No workers.dev address.
echo '{"enabled": false, "previews_enabled": false}' >"$WORK/subdomain.json"
call POST "/workers/scripts/$NAME/subdomain" -H "Content-Type: application/json" --data-binary "@$WORK/subdomain.json"

# 3. Its address: the source, by its identifier, which stays the same from
# one version to the next. The site may still be publishing the newest.
identifier="$(jq -r '.identifier' "$HERE/../app/sidestore-player-source.json")"
status="$(curl -sS -o "$WORK/source.json" --max-time 20 -w '%{http_code}' "$ADDRESS" 2>/dev/null || true)"
if [ "$status" = 200 ] && jq -e --arg id "$identifier" '.identifier == $id and (.apps | type) == "array"' "$WORK/source.json" >/dev/null 2>&1; then
  echo "$ADDRESS gives Cartouche's source for SideStore"
  echo "The source for the player's SideStore: $ADDRESS" >>"$SUMMARY"
else
  steps="Workers & Pages › $NAME › Settings › Domains & Routes › Add › Custom domain › $HOST"
  echo "::warning::$ADDRESS does not give the source yet (HTTP ${status:-none}). Attach the domain to the Worker once, in Cloudflare's dashboard: $steps (source/README.md)."
  echo "The source for the player's SideStore: $ADDRESS does not answer yet. Once, in Cloudflare's dashboard: $steps." >>"$SUMMARY"
fi
