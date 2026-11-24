#!/usr/bin/env bash
# Prints the ID of the Cloudflare account that has the zone cartouche.cloud,
# where the telemetry's database is (decision 158), read with
# CLOUDFLARE_API_TOKEN, a token that sees the zone: the workflows that read
# the database give it the Domain workflow's CLOUDFLARE_DOMAIN_TOKEN, and
# hand this to export.py, sheets.py and nxnative.py as CLOUDFLARE_ACCOUNT_ID.
# Without the token it prints nothing, and those do nothing.
#
#     CLOUDFLARE_ACCOUNT_ID="$(telemetry/account.sh)"; export CLOUDFLARE_ACCOUNT_ID

set -euo pipefail

ZONE=cartouche.cloud
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then exit 0; fi

# CLOUDFLARE_API stands in for Cloudflare's API in the tests (test/test_account.py).
API="${CLOUDFLARE_API:-https://api.cloudflare.com/client/v4}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The token goes to curl in a file, never on a command line.
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN" >"$WORK/authorization"
curl -sS -o "$WORK/answer.json" -H @"$WORK/authorization" "$API/zones?name=$ZONE"
if ! account="$(jq -er 'select(.success == true) | .result[0].account.id | select(type == "string")' "$WORK/answer.json" 2>/dev/null)"; then
  echo "The token does not see the zone $ZONE:" >&2
  jq -r '.errors[]? | "  \(.code): \(.message)"' "$WORK/answer.json" >&2 2>/dev/null || true
  exit 1
fi
echo "$account"
