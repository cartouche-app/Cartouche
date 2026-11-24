#!/usr/bin/env bash
# Deploys the Worker cartouche-source (README.md), which answers at
# https://source.cartouche.cloud/ with Cartouche's source for the player's
# own SideStore, in the Cloudflare account that has the zone cartouche.cloud,
# through Cloudflare's API, with curl and jq and nothing else:
#
# 1. the zone, and the account it is in, read with CLOUDFLARE_DOMAIN_TOKEN,
#    the token the Domain workflow keeps the zone's records with
#    (domain/README.md#the-token): a Worker's domain is in the account of
#    its zone, and nowhere else;
# 2. the Worker, worker.js as it is, with no binding and no logs kept, and
#    no workers.dev address: it answers at its domain alone;
# 3. its domain, source.cartouche.cloud, attached when it is not yet:
#    Cloudflare makes the name's DNS record and its certificate itself;
# 4. the copy the first deploy left in the telemetry's account, removed,
#    with the telemetry's CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID when
#    they are set and that account is another;
# 5. what https://source.cartouche.cloud/ answers: the source, or a warning.
#
# The token needs, besides the Domain workflow's Zone › DNS › Edit and
# Zone › Zone › Read, Account › Workers Scripts › Edit and Zone › Workers
# Routes › Edit. While it has not, the deploy warns with what to add, and
# does not fail: that is the owner's to do, in Cloudflare's dashboard.
# Without it, it says so and does nothing. The secrets are the repository's
# environment cloudflare's, which .github/workflows/site.yml deploys from.
#
#     CLOUDFLARE_DOMAIN_TOKEN=… source/deploy.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=cartouche-source
ZONE=cartouche.cloud
HOST="source.$ZONE"
# The Workers runtime worker.js is written for.
COMPATIBILITY_DATE=2026-09-01
# What a player adds to SideStore; the tests give a stand-in's, and fewer
# tries, as a new domain's certificate can take a minute.
ADDRESS="${CARTOUCHE_SOURCE_ADDRESS:-https://$HOST/}"
TRIES="${CARTOUCHE_SOURCE_TRIES:-8}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
PERMISSIONS="Manage account › Account API Tokens › Cartouche domain › Edit: add Account › Workers Scripts › Edit and Zone › Workers Routes › Edit"

if [ -z "${CLOUDFLARE_DOMAIN_TOKEN:-}" ]; then
  echo "::notice::No CLOUDFLARE_DOMAIN_TOKEN: the source's Worker is not deployed."
  exit 0
fi

# CLOUDFLARE_API stands in for Cloudflare's API in the tests (test/test_deploy.py).
API="${CLOUDFLARE_API:-https://api.cloudflare.com/client/v4}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The tokens go to curl in files, never on a command line.
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_DOMAIN_TOKEN" >"$WORK/authorization"
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN" >"$WORK/telemetry-authorization"
fi

# ask METHOD PATH [CURL ARGUMENTS...]: Cloudflare's whole answer, in
# $WORK/answer.json; fails when Cloudflare says the call did not succeed.
# ASKING_WITH names the header file of the token to ask with.
ASKING_WITH="$WORK/authorization"
ask() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o "$WORK/answer.json" -X "$method" -H @"$ASKING_WITH" "$@" "$API$path" || return 1
  jq -e '.success == true' "$WORK/answer.json" >/dev/null 2>&1
}

# Cloudflare's errors in the last answer, one a line.
errors() {
  jq -r '.errors[]? | "  \(.code): \(.message)"' "$WORK/answer.json" 2>/dev/null || cat "$WORK/answer.json"
}

# Whether the last answer refused the token: what it may not do yet.
refused_the_token() {
  jq -e '[.errors[]?.code] | any(. == 10000 or . == 9109 or . == 10001)' "$WORK/answer.json" >/dev/null 2>&1
}

# call METHOD PATH [CURL ARGUMENTS...]: the call, or Cloudflare's errors and
# the end of the deploy; a token that may not do it yet ends it with the
# warning that says what to add.
call() {
  if ask "$@"; then return 0; fi
  if refused_the_token; then
    echo "::warning::The token Cartouche domain may not deploy the source's Worker yet ($1 $2). Once, in Cloudflare's dashboard: $PERMISSIONS (source/README.md)."
    echo "The source for the player's SideStore is not deployed: the token Cartouche domain may not do it yet. $PERMISSIONS." >>"$SUMMARY"
    exit 0
  fi
  echo "Cloudflare refused $1 $2:" >&2
  errors >&2
  exit 1
}

# 1. The zone and its account.
call GET "/zones?name=$ZONE"
read -r zone account < <(jq -r '.result[0] | "\(.id) \(.account.id)"' "$WORK/answer.json")
if [ -z "$zone" ] || [ "$zone" = null ] || [ -z "$account" ] || [ "$account" = null ]; then
  echo "The token does not see the zone $ZONE." >&2
  exit 1
fi
echo "The zone $ZONE is in the account $account"

# 2. The Worker, without a workers.dev address.
echo "Uploading the Worker $NAME"
jq -n --arg date "$COMPATIBILITY_DATE" '{
  main_module: "worker.js",
  compatibility_date: $date,
  bindings: [],
  observability: {enabled: false}
}' >"$WORK/metadata.json"
call PUT "/accounts/$account/workers/scripts/$NAME" \
  -F "metadata=@$WORK/metadata.json;type=application/json" \
  -F "worker.js=@$HERE/worker.js;type=application/javascript+module"
echo '{"enabled": false, "previews_enabled": false}' >"$WORK/subdomain.json"
call POST "/accounts/$account/workers/scripts/$NAME/subdomain" -H "Content-Type: application/json" --data-binary "@$WORK/subdomain.json"

# 3. Its domain.
call GET "/accounts/$account/workers/domains?hostname=$HOST"
attached="$(jq -r --arg host "$HOST" '[.result[]? | select(.hostname == $host)] | first | .service // empty' "$WORK/answer.json")"
if [ "$attached" = "$NAME" ]; then
  echo "$HOST is the Worker's domain"
elif [ -n "$attached" ]; then
  echo "$HOST is the domain of the Worker $attached, not $NAME: take it off that Worker, and deploy again." >&2
  exit 1
else
  echo "Attaching $HOST to the Worker $NAME"
  jq -n --arg host "$HOST" --arg name "$NAME" --arg zone "$zone" \
    '{hostname: $host, service: $name, zone_id: $zone}' >"$WORK/domain.json"
  call PUT "/accounts/$account/workers/domains" -H "Content-Type: application/json" --data-binary "@$WORK/domain.json"
fi

# 4. The copy in the telemetry's account, which the first deploy uploaded
# there (2026-11-24): never reachable, since it had no domain and no
# workers.dev address.
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && [ "$CLOUDFLARE_ACCOUNT_ID" != "$account" ]; then
  ASKING_WITH="$WORK/telemetry-authorization"
  if ask DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$NAME"; then
    echo "Removed the copy of $NAME from the telemetry's account"
  elif jq -e '[.errors[]?.code] | any(. == 10007)' "$WORK/answer.json" >/dev/null 2>&1; then
    echo "The telemetry's account has no copy of $NAME"
  else
    echo "::warning::The copy of $NAME in the telemetry's account could not be removed:"
    errors
  fi
  ASKING_WITH="$WORK/authorization"
fi

# 5. Its address: the source, by its identifier, which stays the same from
# one version to the next. The site may still be publishing the newest.
identifier="$(jq -r '.identifier' "$HERE/../app/sidestore-player-source.json")"
status=none
for try in $(seq 1 "$TRIES"); do
  status="$(curl -sS -o "$WORK/source.json" --max-time 20 -w '%{http_code}' "$ADDRESS" 2>/dev/null || true)"
  if [ "$status" = 200 ] && jq -e --arg id "$identifier" '.identifier == $id and (.apps | type) == "array"' "$WORK/source.json" >/dev/null 2>&1; then
    echo "$ADDRESS gives Cartouche's source for SideStore"
    echo "The source for the player's SideStore: $ADDRESS" >>"$SUMMARY"
    exit 0
  fi
  if [ "$try" -lt "$TRIES" ]; then sleep 15; fi
done
echo "::warning::$ADDRESS does not give the source yet (HTTP ${status:-none}): a new domain's certificate can take a few minutes. Run the Showcase site workflow again to check."
echo "The source for the player's SideStore: $ADDRESS does not answer yet (HTTP ${status:-none})." >>"$SUMMARY"
