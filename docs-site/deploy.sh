#!/usr/bin/env bash
# Deploys the documentation (README.md): the Worker cartouche-docs, which
# serves dist/ as Cloudflare's static assets at https://docs.cartouche.cloud/,
# in the Cloudflare account that has the zone cartouche.cloud, as
# source/deploy.sh deploys the source's Worker:
#
# 1. the zone's account, read with CLOUDFLARE_DOMAIN_TOKEN, the token the
#    Domain workflow keeps the zone's records with (domain/README.md#the-token):
#    a Worker's domain is in the account of its zone, and nowhere else;
# 2. the Worker and its files, with wrangler (wrangler.jsonc): no code of its
#    own, no logs kept, no workers.dev or preview address, and its domain,
#    docs.cartouche.cloud, for which Cloudflare makes the DNS record and the
#    certificate itself;
# 3. what https://docs.cartouche.cloud/ answers: the documentation, or a
#    warning.
#
# The token needs what source/deploy.sh needs: besides the Domain workflow's
# Zone › DNS › Edit and Zone › Zone › Read, Account › Workers Scripts › Edit
# and Zone › Workers Routes › Edit. While it has not, the deploy warns with
# what to add, and does not fail. Without it, it says so and does nothing.
# The secret is the repository's environment cloudflare's, which
# .github/workflows/docs.yml deploys from. Build first: npm ci && npm run build.
#
#     CLOUDFLARE_DOMAIN_TOKEN=… docs-site/deploy.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZONE=cartouche.cloud
HOST="docs.$ZONE"
ADDRESS="${CARTOUCHE_DOCS_ADDRESS:-https://$HOST/}"
TRIES="${CARTOUCHE_DOCS_TRIES:-8}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
PERMISSIONS="Manage account › Account API Tokens › Cartouche domain › Edit: add Account › Workers Scripts › Edit and Zone › Workers Routes › Edit"

if [ -z "${CLOUDFLARE_DOMAIN_TOKEN:-}" ]; then
  echo "::notice::No CLOUDFLARE_DOMAIN_TOKEN: the documentation is not deployed."
  exit 0
fi
if [ ! -f "$HERE/dist/index.html" ]; then
  echo "dist/ is missing: run npm run build first." >&2
  exit 1
fi

API="${CLOUDFLARE_API:-https://api.cloudflare.com/client/v4}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The token goes to curl in a file, never on a command line.
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_DOMAIN_TOKEN" >"$WORK/authorization"

# 1. The zone's account.
if ! curl -sS -o "$WORK/zones.json" -H @"$WORK/authorization" "$API/zones?name=$ZONE" ||
  ! jq -e '.success == true' "$WORK/zones.json" >/dev/null 2>&1; then
  echo "Cloudflare did not give the zone $ZONE:" >&2
  jq -r '.errors[]? | "  \(.code): \(.message)"' "$WORK/zones.json" >&2 2>/dev/null || true
  exit 1
fi
account="$(jq -r '.result[0].account.id // empty' "$WORK/zones.json")"
if [ -z "$account" ]; then
  echo "The token does not see the zone $ZONE." >&2
  exit 1
fi
echo "The zone $ZONE is in the account $account"

# 2. The Worker, its files and its domain. Wrangler takes the token from its
# environment, and sends Cloudflare no usage measures of its own.
cd "$HERE"
if ! CLOUDFLARE_API_TOKEN="$CLOUDFLARE_DOMAIN_TOKEN" CLOUDFLARE_ACCOUNT_ID="$account" WRANGLER_SEND_METRICS=false \
  npx --no-install wrangler deploy 2>&1 | tee "$WORK/wrangler.log"; then
  if grep -Eq 'code: (10000|9109|10001)\]|Authentication error' "$WORK/wrangler.log"; then
    echo "::warning::The token Cartouche domain may not deploy the documentation yet. Once, in Cloudflare's dashboard: $PERMISSIONS (docs-site/README.md)."
    echo "The documentation is not deployed: the token Cartouche domain may not do it yet. $PERMISSIONS." >>"$SUMMARY"
    exit 0
  fi
  echo "Wrangler could not deploy the documentation." >&2
  exit 1
fi

# 3. Its address: the home page, in English. A new domain's certificate can
# take a minute.
status=none
for try in $(seq 1 "$TRIES"); do
  status="$(curl -sS -o "$WORK/home.html" --max-time 20 -w '%{http_code}' "$ADDRESS" 2>/dev/null || true)"
  if [ "$status" = 200 ] && grep -q '<html lang="en"' "$WORK/home.html" && grep -q 'Cartouche' "$WORK/home.html"; then
    echo "$ADDRESS gives the documentation"
    echo "The documentation: $ADDRESS" >>"$SUMMARY"
    exit 0
  fi
  if [ "$try" -lt "$TRIES" ]; then sleep 15; fi
done
echo "::warning::$ADDRESS does not give the documentation yet (HTTP ${status:-none}): a new domain's certificate can take a few minutes. Run the Documentation workflow again to check."
echo "The documentation: $ADDRESS does not answer yet (HTTP ${status:-none})." >>"$SUMMARY"
