#!/usr/bin/env bash
# Deploys the telemetry server (README.md) in the Cloudflare account that has
# the zone cartouche.cloud, with CLOUDFLARE_DOMAIN_TOKEN, the token the
# Domain workflow keeps the zone's records with (domain/README.md#the-token),
# through Cloudflare's API, with curl and jq and nothing else (decision 158):
#
# 0. the zone, and the account it is in: the server's domain is in the
#    account of its zone, and the project's Workers are all there;
# 1. the D1 database cartouche-telemetry, created in the EU jurisdiction
#    when it does not exist yet: a database's jurisdiction is set when it
#    is created, and never changes;
# 2. schema.sql applied to it, each statement of which runs again without
#    harm;
# 3. the Worker cartouche-telemetry, worker.js as it is, with the database
#    as DB and no logs kept, and what it files the problems players send
#    with: the private repository CARTOUCHE_REPORTS_REPOSITORY, by the name
#    GitHub gives it now if it moved, and the token CARTOUCHE_REPORTS_TOKEN,
#    when they are set; without them, or with a public repository, the
#    Worker keeps the problems until a deploy with them. With IGDB_CLIENT_ID and IGDB_CLIENT_SECRET, a Twitch
#    application's, it finds on IGDB the covers of the games Cartouche does
#    not know; the dashboard never gets them;
# 4. its address, telemetry.cartouche.cloud, attached when it is not yet:
#    Cloudflare makes the name's DNS record and its certificate itself; the
#    server has no workers.dev address of its own. Its former address, in
#    the account it started in, is the relay's (move.sh, relay/worker.js);
# 5. its daily run, which deletes the reports older than 25 months;
# 6. the dashboard cartouche-dashboard, which shows the project what the
#    database holds (README.md#dashboard): dashboard/worker.js and its
#    page, with the catalog's names and covers of the games and chips of
#    the iPhones, bound to the database and to the problems' repository as
#    the server is, on its workers.dev address, on the account's workers.dev
#    subdomain, which is created when the account has none. It opens only behind
#    Cloudflare Access; with CLOUDFLARE_ACCESS_TEAM and
#    CLOUDFLARE_ACCESS_AUD, the team and the audience of a hostname's
#    Access application, it also reads that application's tokens.
#
# It ends with the server's address, which goes in app/config.env as
# CARTOUCHE_TELEMETRY_URL, and the dashboard's, with whether Access
# protects it. Without the token it says so and does nothing: it is a
# secret of the repository's environment cloudflare, which
# .github/workflows/telemetry.yml deploys from.
#
#     CLOUDFLARE_DOMAIN_TOKEN=… telemetry/deploy.sh
#
# The token needs, besides the Domain workflow's Zone › DNS › Edit and
# Zone › Zone › Read, Account › Workers Scripts › Edit, Zone › Workers
# Routes › Edit and Account › D1 › Edit. While it has not, the deploy warns
# with what to add, and does not fail: that is the owner's to do, in
# Cloudflare's dashboard.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="$HERE/../catalog"
NAME=cartouche-telemetry
DASHBOARD=cartouche-dashboard
ZONE=cartouche.cloud
HOST="telemetry.$ZONE"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
PERMISSIONS="Manage account › Account API Tokens › Cartouche domain › Edit: add Account › D1 › Edit, Account › Workers Scripts › Edit and Zone › Workers Routes › Edit"
# The Workers runtime worker.js is written for.
COMPATIBILITY_DATE=2026-09-01
# Every day at 03:17 UTC.
SCHEDULE="17 3 * * *"

if [ -z "${CLOUDFLARE_DOMAIN_TOKEN:-}" ]; then
  echo "::notice::No CLOUDFLARE_DOMAIN_TOKEN: the telemetry server is not deployed."
  exit 0
fi

# CLOUDFLARE_API stands in for Cloudflare's API in the tests (test/test_deploy.py).
ROOT="${CLOUDFLARE_API:-https://api.cloudflare.com/client/v4}"
API="$ROOT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The token goes to curl in a file, never on a command line.
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_DOMAIN_TOKEN" >"$WORK/authorization"
# The run's own output, for what call says while its result goes to a file.
exec 3>&1

# ask METHOD PATH [CURL ARGUMENTS...]: Cloudflare's whole answer, in
# $WORK/answer.json; fails when Cloudflare says the call did not succeed.
ask() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o "$WORK/answer.json" -X "$method" -H @"$WORK/authorization" "$@" "$API$path" || return 1
  jq -e '.success == true' "$WORK/answer.json" >/dev/null 2>&1
}

# call METHOD PATH [CURL ARGUMENTS...]: the call's result, or its errors and
# the end of the deploy; a token that may not do it yet ends it with the
# warning that says what to add.
call() {
  if ! ask "$@"; then
    if jq -e '[.errors[]?.code] | any(. == 10000 or . == 9109 or . == 10001)' "$WORK/answer.json" >/dev/null 2>&1; then
      echo "::warning::The token Cartouche domain may not deploy the telemetry yet ($1 $2). Once, in Cloudflare's dashboard: $PERMISSIONS (telemetry/README.md#deploy)." >&3
      echo "The telemetry is not deployed: the token Cartouche domain may not do it yet. $PERMISSIONS." >>"$SUMMARY"
      exit 0
    fi
    echo "Cloudflare refused $1 $2:" >&2
    jq -r '.errors[]? | "  \(.code): \(.message)"' "$WORK/answer.json" >&2 2>/dev/null || cat "$WORK/answer.json" >&2
    exit 1
  fi
  jq '.result' "$WORK/answer.json"
}

json() { printf '%s' "$1" >"$WORK/body.json"; echo "@$WORK/body.json"; }

# 0. The zone and its account.
call GET "/zones?name=$ZONE" >"$WORK/zones.json"
read -r zone account < <(jq -r '(.[0] // {}) | "\(.id // "") \(.account.id // "")"' "$WORK/zones.json")
if [ -z "$zone" ] || [ -z "$account" ]; then
  echo "The token does not see the zone $ZONE." >&2
  exit 1
fi
echo "The zone $ZONE is in the account $account"
API="$ROOT/accounts/$account"

# 1. The database.
call GET "/d1/database?name=$NAME" >"$WORK/databases.json"
found="$(jq -r --arg name "$NAME" 'map(select(.name == $name)) | first // empty | "\(.uuid) \(.jurisdiction // "")"' "$WORK/databases.json")"
if [ -z "$found" ]; then
  echo "Creating the D1 database $NAME in the EU jurisdiction"
  call POST /d1/database -H "Content-Type: application/json" \
    --data-binary "$(json "$(jq -n --arg name "$NAME" '{name: $name, jurisdiction: "eu"}')")" >"$WORK/database.json"
  database="$(jq -r '.uuid' "$WORK/database.json")"
else
  read -r database jurisdiction <<<"$found"
  if [ -n "$jurisdiction" ] && [ "$jurisdiction" != eu ]; then
    echo "The D1 database $NAME is in the jurisdiction $jurisdiction, not eu: delete it, and deploy again." >&2
    exit 1
  fi
  echo "The D1 database $NAME is there"
fi

# 2. Its tables. D1 runs the statements as one batch; the comments are left
# out.
echo "Applying schema.sql"
call POST "/d1/database/$database/query" -H "Content-Type: application/json" \
  --data-binary "$(json "$(sed -e '/^[[:space:]]*--/d' "$HERE/schema.sql" | jq -Rs '{sql: .}')")" >/dev/null

# 3. The Worker, and the repository it files problems in. Its token goes
# to curl and jq in files too.
echo '[]' >"$WORK/problems.json"
problems="the server keeps the problems players send: there is no CARTOUCHE_REPORTS_TOKEN"
if [ -n "${CARTOUCHE_REPORTS_TOKEN:-}" ] && [ -n "${CARTOUCHE_REPORTS_REPOSITORY:-}" ]; then
  repository="$CARTOUCHE_REPORTS_REPOSITORY"
  printf 'Authorization: Bearer %s\n' "$CARTOUCHE_REPORTS_TOKEN" >"$WORK/github-authorization"
  printf '%s' "$CARTOUCHE_REPORTS_TOKEN" >"$WORK/problems-token"
  # A repository moved to another owner answers at its old name with a
  # redirect, which curl follows on the same host with the token: the Worker
  # gets the name GitHub gives it now.
  curl -sSL --max-redirs 3 --max-time 20 -o "$WORK/repository.json" -H @"$WORK/github-authorization" \
    -H "Accept: application/vnd.github+json" "${GITHUB_API_URL:-https://api.github.com}/repos/$repository" 2>/dev/null || true
  visibility="$(jq -r 'if (type == "object" and has("private")) then (if .private then "private" else "public" end) else empty end' \
    "$WORK/repository.json" 2>/dev/null || true)"
  named="$(jq -r 'if (type == "object" and (.full_name | type) == "string") then .full_name else empty end' \
    "$WORK/repository.json" 2>/dev/null || true)"
  moved=""
  if [ -n "$visibility" ] && [[ "$named" =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]] && [ "${named,,}" != "${repository,,}" ]; then
    moved=" (GitHub moved it from $repository)"
    repository="$named"
  fi
  case "$visibility" in
    private) problems="players' problems go to $repository, a private repository$moved" ;;
    public) problems="$repository is public: the server files no problem there, and keeps them" ;;
    *) problems="the token cannot read $repository: the server keeps the problems until GitHub takes them" ;;
  esac
  if [ "$visibility" != public ]; then
    jq -n --arg repository "$repository" --rawfile token "$WORK/problems-token" '[
      {type: "plain_text", name: "PROBLEMS_REPOSITORY", text: $repository},
      {type: "secret_text", name: "PROBLEMS_TOKEN", text: $token}
    ]' >"$WORK/problems.json"
  fi
fi
case "$problems" in
  players*) echo "Problems: $problems" ;;
  *public*) echo "::error::Problems: $problems." ;;
  *) echo "::warning::Problems: $problems." ;;
esac

# The Twitch application the server asks IGDB with, for the games Cartouche
# does not know (worker.js, POST /v1/games): in files too, for the server
# alone.
echo '[]' >"$WORK/igdb.json"
if [ -n "${IGDB_CLIENT_ID:-}" ] && [ -n "${IGDB_CLIENT_SECRET:-}" ]; then
  printf '%s' "$IGDB_CLIENT_ID" >"$WORK/igdb-client"
  printf '%s' "$IGDB_CLIENT_SECRET" >"$WORK/igdb-secret"
  jq -n --rawfile client "$WORK/igdb-client" --rawfile secret "$WORK/igdb-secret" '[
    {type: "secret_text", name: "IGDB_CLIENT_ID", text: $client},
    {type: "secret_text", name: "IGDB_CLIENT_SECRET", text: $secret}
  ]' >"$WORK/igdb.json"
  igdb="the server finds on IGDB the covers of the games Cartouche does not know"
  echo "IGDB: $igdb"
else
  igdb="there is no IGDB_CLIENT_ID or IGDB_CLIENT_SECRET: the server cannot find the covers of the games Cartouche does not know"
  echo "::warning::IGDB: $igdb."
fi

echo "Uploading the Worker $NAME"
jq -n --arg date "$COMPATIBILITY_DATE" --arg database "$database" --slurpfile problems "$WORK/problems.json" \
  --slurpfile igdb "$WORK/igdb.json" '{
  main_module: "worker.js",
  compatibility_date: $date,
  bindings: ([{type: "d1", name: "DB", id: $database}] + $problems[0] + $igdb[0]),
  observability: {enabled: false}
}' >"$WORK/metadata.json"
call PUT "/workers/scripts/$NAME" \
  -F "metadata=@$WORK/metadata.json;type=application/json" \
  -F "worker.js=@$HERE/worker.js;type=application/javascript+module" >/dev/null

# 4. Its address: its domain alone.
call GET "/workers/domains?hostname=$HOST" >"$WORK/domains.json"
attached="$(jq -r --arg host "$HOST" '[.[]? | select(.hostname == $host)] | first | .service // empty' "$WORK/domains.json")"
if [ "$attached" = "$NAME" ]; then
  echo "$HOST is the server's domain"
elif [ -n "$attached" ]; then
  echo "$HOST is the domain of the Worker $attached, not $NAME: take it off that Worker, and deploy again." >&2
  exit 1
else
  echo "Attaching $HOST to the Worker $NAME"
  call PUT /workers/domains -H "Content-Type: application/json" \
    --data-binary "$(json "$(jq -n --arg host "$HOST" --arg name "$NAME" --arg zone "$zone" \
      '{hostname: $host, service: $name, zone_id: $zone}')")" >/dev/null
fi
call POST "/workers/scripts/$NAME/subdomain" -H "Content-Type: application/json" \
  --data-binary "$(json '{"enabled": false, "previews_enabled": false}')" >/dev/null

# The dashboard's address, on the account's workers.dev subdomain.
if ask GET /workers/subdomain && subdomain="$(jq -er '.result.subdomain // empty' "$WORK/answer.json")"; then
  echo "The account's workers.dev subdomain is $subdomain"
else
  subdomain="cartouche-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  echo "The account has no workers.dev subdomain: creating $subdomain"
  call PUT /workers/subdomain -H "Content-Type: application/json" \
    --data-binary "$(json "$(jq -n --arg subdomain "$subdomain" '{subdomain: $subdomain}')")" >/dev/null
fi

# 5. Its daily run.
call PUT "/workers/scripts/$NAME/schedules" -H "Content-Type: application/json" \
  --data-binary "$(json "$(jq -n --arg cron "$SCHEDULE" '[{cron: $cron}]')")" >/dev/null

# 6. The dashboard. Its page carries the catalog as JSON in a script
# element, its < > & written \u003c \u003e \u0026 so that nothing in it
# closes the element: for each title ID its name and IGDB cover, the other
# regions' title IDs, and for each model its chip and memory.
jq -nj --slurpfile games "$CATALOG/nxnative.json" --slurpfile covers "$CATALOG/covers.json" \
  --slurpfile devices "$CATALOG/devices.json" '
  ($covers[0].covers | map({key: .titleId, value: .cover}) | from_entries) as $cover
  | {
      games: (($covers[0].covers | map({key: .titleId, value: [.name, .cover]}) | from_entries)
        + ($games[0].games | map({key: .titleId, value: [.name, ($cover[.titleId] // null)]}) | from_entries)),
      aliases: ([$games[0].games[] | .titleId as $game | (.variants // [])[] | {key: .titleId, value: $game}] | from_entries),
      devices: ($devices[0].devices | map({key: .identifier, value: [.chip, .memoryGB]}) | from_entries)
    }
  | tojson | gsub("<"; "\\u003c") | gsub(">"; "\\u003e") | gsub("&"; "\\u0026")' >"$WORK/catalog.json"
PLACEHOLDER='<script type="application/json" id="catalog">{}</script>'
jq -Rsj --arg placeholder "$PLACEHOLDER" --rawfile catalog "$WORK/catalog.json" '
  split($placeholder)
  | if length == 2 then .[0] + "<script type=\"application/json\" id=\"catalog\">" + $catalog + "</script>" + .[1]
    else error("dashboard/index.html has no single place for the catalog") end' \
  "$HERE/dashboard/index.html" >"$WORK/index.html"

echo '[]' >"$WORK/access.json"
if [ -n "${CLOUDFLARE_ACCESS_TEAM:-}" ] && [ -n "${CLOUDFLARE_ACCESS_AUD:-}" ]; then
  jq -n --arg team "$CLOUDFLARE_ACCESS_TEAM" --arg aud "$CLOUDFLARE_ACCESS_AUD" '[
    {type: "plain_text", name: "ACCESS_TEAM_DOMAIN", text: $team},
    {type: "plain_text", name: "ACCESS_AUD", text: $aud}
  ]' >"$WORK/access.json"
fi
echo "Uploading the dashboard $DASHBOARD"
jq -n --arg date "$COMPATIBILITY_DATE" --arg database "$database" --slurpfile problems "$WORK/problems.json" \
  --slurpfile access "$WORK/access.json" '{
  main_module: "worker.js",
  compatibility_date: $date,
  bindings: ([{type: "d1", name: "DB", id: $database}] + $problems[0] + $access[0]),
  observability: {enabled: false}
}' >"$WORK/dashboard.json"
call PUT "/workers/scripts/$DASHBOARD" \
  -F "metadata=@$WORK/dashboard.json;type=application/json" \
  -F "worker.js=@$HERE/dashboard/worker.js;type=application/javascript+module" \
  -F "index.html=@$WORK/index.html;type=text/plain" >/dev/null
call POST "/workers/scripts/$DASHBOARD/subdomain" -H "Content-Type: application/json" \
  --data-binary "$(json '{"enabled": true, "previews_enabled": false}')" >/dev/null

URL="https://$HOST"
DASHBOARD_URL="https://$DASHBOARD.$subdomain.workers.dev"
# reach WORKER: where the checks below ask a Worker, its address, or the
# stand-in's in the tests (TELEMETRY_CHECK_BASE).
reach() {
  if [ -n "${TELEMETRY_CHECK_BASE:-}" ]; then
    echo "$TELEMETRY_CHECK_BASE$1/"
  elif [ "$1" = "$NAME" ]; then
    echo "$URL/"
  else
    echo "https://$1.$subdomain.workers.dev/"
  fi
}
# A new address can take a minute or two to answer, the time of its
# certificate. Behind
# Cloudflare Access, the server would send the iPhones to a sign-in page
# instead of taking their reports: only the dashboard goes behind Access.
answered=""
for ((try = 0; try < ${TELEMETRY_CHECK_TRIES:-12}; try++)); do
  if [ "$try" -gt 0 ]; then sleep 10; fi
  rm -f "$WORK/root"
  case "$(curl -sS -o "$WORK/root" --max-time 10 -w '%{http_code} %{redirect_url}' "$(reach "$NAME")" 2>/dev/null || true)" in
    30[0-9]\ *cloudflareaccess.com/* | 30[0-9]\ */cdn-cgi/access/*) answered=access && break ;;
  esac
  if [ -f "$WORK/root" ] && [ "$(cat "$WORK/root")" = "Cartouche telemetry" ]; then
    answered=yes
    break
  fi
done
case "$answered" in
  yes)
    echo "The telemetry server answers at $URL" ;;
  access)
    server="Cloudflare Access protects the telemetry server at $URL: the iPhones cannot send it their reports or their problems. Only $DASHBOARD goes behind Access: take $HOST out of it in Zero Trust › Access › Applications, or Workers & Pages › $NAME › Access › Manage access"
    echo "::error::$server." ;;
  *)
    echo "::warning::$URL does not answer yet: a new address can take a few minutes, the time of its certificate." ;;
esac

# Behind Access, the dashboard's address sends to the team's sign-in; without
# it, the Worker answers its closed page.
protection=""
for ((try = 0; try < ${TELEMETRY_CHECK_TRIES:-12}; try++)); do
  if [ "$try" -gt 0 ]; then sleep 10; fi
  case "$(curl -sS -o /dev/null --max-time 10 -w '%{http_code} %{redirect_url}' "$(reach "$DASHBOARD")" 2>/dev/null || true)" in
    30[0-9]\ *cloudflareaccess.com/* | 30[0-9]\ */cdn-cgi/access/*) protection=access && break ;;
    403\ *) protection=closed && break ;;
  esac
done
case "$protection" in
  access)
    dashboard="the dashboard is at $DASHBOARD_URL, behind Cloudflare Access"
    echo "Dashboard: $dashboard" ;;
  closed)
    dashboard="the dashboard is at $DASHBOARD_URL, closed until Cloudflare Access protects it: Workers & Pages › $DASHBOARD › Access (telemetry/README.md#dashboard)"
    echo "::warning::Dashboard: $dashboard." ;;
  *)
    dashboard="the dashboard is at $DASHBOARD_URL, and opens behind Cloudflare Access only (telemetry/README.md#dashboard)"
    echo "::notice::Dashboard: $dashboard." ;;
esac

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    if [ "$answered" = access ]; then echo "**$server.**"; fi
    echo "The telemetry server is at $URL: \`CARTOUCHE_TELEMETRY_URL=$URL\` in app/config.env."
    echo "Problems: $problems."
    echo "IGDB: $igdb."
    echo "Dashboard: $dashboard."
  } >>"$GITHUB_STEP_SUMMARY"
fi

# Both Workers are up, but behind Access the server takes nothing: the run
# fails, for the project to see it.
if [ "$answered" = access ]; then exit 1; fi
