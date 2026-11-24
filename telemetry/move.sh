#!/usr/bin/env bash
# Moves the telemetry from the Cloudflare account it started in, Ad's own,
# to the account of the zone cartouche.cloud, where deploy.sh puts it now
# (decision 158), and keeps the server's former address answering, through
# Cloudflare's API, with curl and jq and nothing else:
#
#     telemetry/move.sh move    # once deploy.sh has made the new database
#     telemetry/move.sh relay   # the relay again, as relay/worker.js is now
#     telemetry/move.sh clean   # once the move is checked
#
# The former account is CLOUDFLARE_ACCOUNT_ID, reached with
# CLOUDFLARE_API_TOKEN, the token the telemetry was deployed with until
# then; the new one is the zone's, reached with CLOUDFLARE_DOMAIN_TOKEN, as
# deploy.sh does. They are secrets of the repository's environment
# cloudflare, which .github/workflows/telemetry-move.yml runs from.
#
# move:
# 1. the former Worker cartouche-telemetry becomes the relay
#    (relay/worker.js), by the same name and so at the same address, which
#    every Cartouche given out before the move sends to. First it holds:
#    every request but GET / gets 503 with a Retry-After, and the apps keep
#    their reports and send them again later, so that the former database
#    takes nothing more. Its daily run goes with the database;
# 2. the rows of the former database's four tables are exported, and
#    imported into the new database, each row once (INSERT OR IGNORE),
#    again until both hold the same rows, table by table: their number and
#    their bytes;
# 3. the relay opens: it passes each request on to the server's new
#    address, https://telemetry.cartouche.cloud, and its answer back.
# The new database must be empty, unless the former Worker is the relay
# already: a move run again after one that stopped, whose new database
# may hold more than the former, never less.
#
# relay: the relay, open, as relay/worker.js is now; the move must be done.
#
# clean: once the move is done, and the new database holds at least the
# rows of the former, table by table, the former database and the former
# dashboard are deleted. The relay stays, for the copies of Cartouche that
# still send to the former address.
#
# Each ends with what the former account still holds: its Workers and its
# D1 databases, by name, and says it in the job's summary.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=cartouche-telemetry
DASHBOARD=cartouche-dashboard
ZONE=cartouche.cloud
TARGET="https://telemetry.$ZONE"
# The Workers runtime relay/worker.js is written for.
COMPATIBILITY_DATE=2026-09-01
TABLES='["reports", "daily", "problems", "lookups"]'
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
# Seconds a new version of the Worker takes to reach every place Cloudflare
# runs it, and the polls of an export or an import: fewer in the tests.
SETTLE="${TELEMETRY_MOVE_SETTLE:-60}"
POLL="${TELEMETRY_MOVE_POLL:-5}"
POLLS="${TELEMETRY_MOVE_POLLS:-180}"
CHECKS="${TELEMETRY_CHECK_TRIES:-12}"

STEP="${1:-}"
case "$STEP" in
  move | relay | clean) ;;
  *)
    echo "usage: telemetry/move.sh move|relay|clean" >&2
    exit 2 ;;
esac
for secret in CLOUDFLARE_DOMAIN_TOKEN CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
  if [ -z "${!secret:-}" ]; then
    echo "No $secret: the move needs the new account's token, and the former account's token and ID." >&2
    exit 1
  fi
done

# CLOUDFLARE_API stands in for Cloudflare's API in the tests (test/test_move.py).
ROOT="${CLOUDFLARE_API:-https://api.cloudflare.com/client/v4}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The tokens go to curl in files, never on a command line.
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_DOMAIN_TOKEN" >"$WORK/new"
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN" >"$WORK/former"

# ask WHO METHOD PATH [CURL ARGUMENTS...]: Cloudflare's whole answer to the
# token of WHO, new or former, in $WORK/answer.json; fails when Cloudflare
# says the call did not succeed.
ask() {
  local who="$1" method="$2" path="$3"
  shift 3
  curl -sS -o "$WORK/answer.json" -X "$method" -H @"$WORK/$who" "$@" "$ROOT$path" || return 1
  jq -e '.success == true' "$WORK/answer.json" >/dev/null 2>&1
}

# call WHO METHOD PATH [CURL ARGUMENTS...]: the call's result in
# $WORK/result.json, or Cloudflare's errors and the end of the run.
call() {
  if ! ask "$@"; then
    echo "Cloudflare refused $2 $3:" >&2
    jq -r '.errors[]? | "  \(.code): \(.message)"' "$WORK/answer.json" >&2 2>/dev/null || cat "$WORK/answer.json" >&2
    exit 1
  fi
  jq '.result' "$WORK/answer.json" >"$WORK/result.json"
}

json() { printf '%s' "$1" >"$WORK/body.json"; echo "@$WORK/body.json"; }

say() {
  echo "$1"
  echo "$1" >>"$SUMMARY"
}

# The new account, the zone's.
call new GET "/zones?name=$ZONE"
account="$(jq -r '(.[0].account.id // empty)' "$WORK/result.json")"
if [ -z "$account" ]; then
  echo "The token CLOUDFLARE_DOMAIN_TOKEN does not see the zone $ZONE." >&2
  exit 1
fi
if [ "$account" = "$CLOUDFLARE_ACCOUNT_ID" ]; then
  say "The telemetry's account is the zone's already: there is nothing to move."
  exit 0
fi
NEW="/accounts/$account"
FORMER="/accounts/$CLOUDFLARE_ACCOUNT_ID"

# database WHO ACCOUNT: the ID of the account's database cartouche-telemetry,
# or nothing.
database() {
  call "$1" GET "$2/d1/database?name=$NAME"
  jq -r --arg name "$NAME" 'map(select(.name == $name)) | first | .uuid // empty' "$WORK/result.json"
}

# rows WHO ACCOUNT DATABASE: what the database holds, table by table: the
# number of rows and their bytes, as one JSON object.
rows() {
  call "$1" POST "$2/d1/database/$3/query" -H "Content-Type: application/json" \
    --data-binary "$(json "$(jq -n '{params: [], sql: ([
      "SELECT (SELECT COUNT(*) FROM reports) AS reports,",
      "(SELECT TOTAL(LENGTH(body)) FROM reports) AS reportBytes,",
      "(SELECT COUNT(*) FROM daily) AS daily,",
      "(SELECT TOTAL(count) FROM daily) AS dailyCounts,",
      "(SELECT COUNT(*) FROM problems) AS problems,",
      "(SELECT TOTAL(LENGTH(body)) FROM problems) AS problemBytes,",
      "(SELECT COUNT(*) FROM lookups) AS lookups,",
      "(SELECT TOTAL(LENGTH(answer)) FROM lookups) AS lookupBytes"
    ] | join(" "))}')")"
  jq -c '.[0].results[0] | with_entries(.value |= (. // 0))' "$WORK/result.json"
}

# Whether the former Worker is the relay: it is bound to its target, and
# to no database.
is_relay() {
  if ! ask former GET "$FORMER/workers/scripts/$NAME/settings"; then return 1; fi
  jq -e '[.result.bindings[]?.name] | index("TARGET") != null' "$WORK/answer.json" >/dev/null
}

# relay HOLD: the relay in the former account, holding (yes) or open (no),
# at the former Worker's workers.dev address, with no daily run.
relay() {
  jq -n --arg date "$COMPATIBILITY_DATE" --arg target "$TARGET" --arg hold "$1" '{
    main_module: "worker.js",
    compatibility_date: $date,
    bindings: ([{type: "plain_text", name: "TARGET", text: $target}]
      + (if $hold == "yes" then [{type: "plain_text", name: "HOLD", text: "yes"}] else [] end)),
    observability: {enabled: false}
  }' >"$WORK/relay.json"
  call former PUT "$FORMER/workers/scripts/$NAME" \
    -F "metadata=@$WORK/relay.json;type=application/json" \
    -F "worker.js=@$HERE/relay/worker.js;type=application/javascript+module"
  call former POST "$FORMER/workers/scripts/$NAME/subdomain" -H "Content-Type: application/json" \
    --data-binary "$(json '{"enabled": true, "previews_enabled": false}')"
  call former PUT "$FORMER/workers/scripts/$NAME/schedules" -H "Content-Type: application/json" \
    --data-binary "$(json '[]')"
}

# The former address: what the copies of Cartouche given out send to.
call former GET "$FORMER/workers/subdomain"
FORMER_URL="https://$NAME.$(jq -r '.subdomain' "$WORK/result.json").workers.dev"

# answers: whether the former address gives the server's name, from the new
# server through the relay.
answers() {
  local base="${TELEMETRY_CHECK_BASE:+$TELEMETRY_CHECK_BASE$NAME/}"
  for ((try = 0; try < CHECKS; try++)); do
    if [ "$try" -gt 0 ]; then sleep 10; fi
    if [ "$(curl -sS --max-time 10 "${base:-$FORMER_URL/}" 2>/dev/null || true)" = "Cartouche telemetry" ]; then return 0; fi
  done
  return 1
}

opened() {
  relay no
  if answers; then
    say "The former address $FORMER_URL relays to $TARGET, which answers."
  else
    echo "::warning::The former address $FORMER_URL does not answer through the relay yet: run the step relay again in a few minutes."
    echo "The former address $FORMER_URL does not answer through the relay yet." >>"$SUMMARY"
  fi
}

# export_former DATABASE: the rows of the former database's tables, as D1
# writes them, in $WORK/former.sql.
export_former() {
  local body bookmark="" status url=""
  for ((poll = 0; poll < POLLS; poll++)); do
    body="$(jq -n --argjson tables "$TABLES" --arg bookmark "$bookmark" '{
      output_format: "polling", dump_options: {no_schema: true, tables: $tables}
    } + (if $bookmark == "" then {} else {current_bookmark: $bookmark} end)')"
    call former POST "$FORMER/d1/database/$1/export" -H "Content-Type: application/json" --data-binary "$(json "$body")"
    status="$(jq -r '.status // empty' "$WORK/result.json")"
    if [ "$status" = complete ]; then
      url="$(jq -r '.result.signed_url // empty' "$WORK/result.json")"
      break
    fi
    if [ "$status" = error ]; then
      echo "D1 could not export the former database: $(jq -r '.error // "no reason given"' "$WORK/result.json")" >&2
      exit 1
    fi
    bookmark="$(jq -r '.at_bookmark // empty' "$WORK/result.json")"
    sleep "$POLL"
  done
  if [ -z "$url" ]; then
    echo "D1 did not finish exporting the former database in time." >&2
    exit 1
  fi
  # A signed address: no token goes with it.
  curl -sS --fail -o "$WORK/former.sql" "$url"
}

# import_new DATABASE: $WORK/former.sql into the new database, each row once.
import_new() {
  local etag upload filename sent bookmark status
  # A statement starts a line outside any string: a string's quotes come in
  # pairs (its own doubled), so the lines before it hold an even number. A
  # line of a player's text that starts with the same words stays as it is.
  awk -v q="'" '{
    if (!open) sub(/^INSERT INTO /, "INSERT OR IGNORE INTO ")
    if (gsub(q, q) % 2) open = !open
    print
  }' "$WORK/former.sql" >"$WORK/import.sql"
  etag="$(md5sum "$WORK/import.sql" | cut -d' ' -f1)"
  call new POST "$NEW/d1/database/$1/import" -H "Content-Type: application/json" \
    --data-binary "$(json "$(jq -n --arg etag "$etag" '{action: "init", etag: $etag}')")"
  upload="$(jq -r '.upload_url // empty' "$WORK/result.json")"
  filename="$(jq -r '.filename // empty' "$WORK/result.json")"
  # Without an address, D1 has this very file already.
  if [ -n "$upload" ]; then
    curl -sS --fail -T "$WORK/import.sql" -D "$WORK/upload.headers" -o /dev/null "$upload"
    sent="$(tr -d '\r"' <"$WORK/upload.headers" | awk 'tolower($1) == "etag:" { print $2 }')"
    if [ "$sent" != "$etag" ]; then
      echo "The export reached D1's storage changed (md5 ${sent:-none}, not $etag)." >&2
      exit 1
    fi
  fi
  call new POST "$NEW/d1/database/$1/import" -H "Content-Type: application/json" \
    --data-binary "$(json "$(jq -n --arg etag "$etag" --arg filename "$filename" '{action: "ingest", etag: $etag, filename: $filename}')")"
  # The ingest's answer says it started; the polls, when it is over.
  bookmark="$(jq -r '.at_bookmark // empty' "$WORK/result.json")"
  for ((poll = 0; poll <= POLLS; poll++)); do
    status="$(jq -r '.status // empty' "$WORK/result.json")"
    if [ "$status" = error ]; then
      echo "D1 could not import into the new database: $(jq -r '.error // "no reason given"' "$WORK/result.json")" >&2
      exit 1
    fi
    if [ "$status" = complete ] || { [ "$poll" -gt 0 ] && jq -e '.success == true or .error == "Not currently importing anything."' "$WORK/result.json" >/dev/null; }; then
      return 0
    fi
    sleep "$POLL"
    call new POST "$NEW/d1/database/$1/import" -H "Content-Type: application/json" \
      --data-binary "$(json "$(jq -n --arg bookmark "$bookmark" '{action: "poll", current_bookmark: $bookmark}')")"
    bookmark="$(jq -r '.at_bookmark // empty' "$WORK/result.json" | grep . || echo "$bookmark")"
  done
  echo "D1 did not finish importing into the new database in time." >&2
  exit 1
}

# holds_all OLD NEW: whether the new database holds at least what the former
# does, table by table.
holds_all() {
  jq -n -e --argjson old "$1" --argjson new "$2" '[$old | keys[] as $key | $new[$key] >= $old[$key]] | all' >/dev/null
}

# What the former account holds, at the end of each step.
inventory() {
  call former GET "$FORMER/workers/scripts"
  local workers databases
  workers="$(jq -r '[.[]?.id] | sort | join(", ")' "$WORK/result.json")"
  call former GET "$FORMER/d1/database"
  databases="$(jq -r '[.[]?.name] | sort | join(", ")' "$WORK/result.json")"
  say "The former account holds the Workers: ${workers:-none}; the D1 databases: ${databases:-none}."
}

new_database="$(database new "$NEW")"
if [ -z "$new_database" ]; then
  echo "The account of $ZONE has no database $NAME yet: deploy the telemetry first (the Telemetry workflow)." >&2
  exit 1
fi
former_database="$(database former "$FORMER")"

case "$STEP" in
  move)
    if [ -z "$former_database" ]; then
      say "The former account has no database $NAME: there is nothing to move."
      inventory
      exit 0
    fi
    moved_before=no
    if is_relay; then moved_before=yes; fi
    before="$(rows new "$NEW" "$new_database")"
    if [ "$moved_before" = no ] && ! jq -e 'add == 0' <<<"$before" >/dev/null; then
      echo "The new database holds rows already ($before), and the former Worker is the server still: nothing is moved." >&2
      exit 1
    fi
    relay yes
    say "The former address holds the reports, which the apps keep and send again later."
    sleep "$SETTLE"
    same=no
    for ((round = 1; round <= 3; round++)); do
      export_former "$former_database"
      import_new "$new_database"
      old="$(rows former "$FORMER" "$former_database")"
      new="$(rows new "$NEW" "$new_database")"
      echo "Round $round: the former database holds $old; the new one $new"
      if { [ "$moved_before" = no ] && [ "$old" = "$new" ]; } || { [ "$moved_before" = yes ] && holds_all "$old" "$new"; }; then
        same=yes
        break
      fi
    done
    if [ "$same" = no ]; then
      echo "The two databases still differ after three rounds: the former address keeps holding the reports, which the apps keep. Run the move again." >&2
      echo "**The databases differ: the former address holds the reports until the move is run again.** Former: $old; new: $new." >>"$SUMMARY"
      exit 1
    fi
    say "Moved: the new database holds every row of the former, table by table: $new."
    opened
    inventory ;;
  relay)
    if ! is_relay; then
      echo "The former Worker is the server still: run the step move first." >&2
      exit 1
    fi
    opened
    inventory ;;
  clean)
    if ! is_relay; then
      echo "The former Worker is the server still: run the step move first, and clean once it is checked." >&2
      exit 1
    fi
    opened
    if [ -n "$former_database" ]; then
      old="$(rows former "$FORMER" "$former_database")"
      new="$(rows new "$NEW" "$new_database")"
      if ! holds_all "$old" "$new"; then
        echo "The new database holds less than the former ($new, against $old): nothing is deleted." >&2
        exit 1
      fi
      call former DELETE "$FORMER/d1/database/$former_database"
      say "Deleted the former database, whose rows the new one holds ($old)."
    fi
    if ask former DELETE "$FORMER/workers/scripts/$DASHBOARD"; then
      say "Deleted the former dashboard."
    elif jq -e '[.errors[]?.code] | any(. == 10007)' "$WORK/answer.json" >/dev/null 2>&1; then
      echo "The former account has no dashboard."
    else
      echo "Cloudflare refused to delete the former dashboard:" >&2
      jq -r '.errors[]? | "  \(.code): \(.message)"' "$WORK/answer.json" >&2
      exit 1
    fi
    inventory ;;
esac
