#!/usr/bin/env bash
#
# Contract test: replays exactly what the mobile clients put on the wire.
#
# The pgTAP suite proves the schema and the policies are right. It cannot prove
# the clients agree with them, because it never sends an HTTP request. Every
# failure this catches is a mismatch between the two — a renamed column, an RPC
# argument spelled differently on one side, a missing GRANT — and every one of
# them looks fine in both codebases read separately.
#
# Needs a running local stack:  supabase start
#
# Run:  supabase/tests/contract_test.sh

set -euo pipefail

API="${SUPABASE_API_URL:-http://127.0.0.1:54321}"
ANON="${SUPABASE_ANON_KEY:-}"
SERVICE="${SUPABASE_SERVICE_ROLE_KEY:-}"

if [[ -z "$ANON" || -z "$SERVICE" ]]; then
  # `supabase status` pretty-prints, so this reads the JSON rather than
  # grepping it out of one line.
  keys="$(supabase status -o json 2>/dev/null | sed -n '/^{/,$p' || true)"
  read_key() { printf '%s' "$keys" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1" 2>/dev/null; }
  ANON="${ANON:-$(read_key ANON_KEY)}"
  SERVICE="${SERVICE:-$(read_key SERVICE_ROLE_KEY)}"
fi

if [[ -z "$ANON" || -z "$SERVICE" ]]; then
  echo "Could not find local keys. Is the stack running?  supabase start" >&2
  exit 1
fi

pass=0
fail=0

check() { # check <description> <condition-result>
  if [[ "$2" == "ok" ]]; then
    printf '  ok   %s\n' "$1"; pass=$((pass + 1))
  else
    printf '  FAIL %s\n' "$1"; fail=$((fail + 1))
  fi
}

json() { python3 -c 'import json,sys; print(json.load(sys.stdin))' 2>/dev/null; }

# Creates a confirmed user and returns an access token, the way a real sign-in
# would. Uses the admin API because there is no inbox to read here.
make_user() {
  local email="$1" password="pw-$RANDOM-$RANDOM"
  curl -sS -X POST "$API/auth/v1/admin/users" \
    -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$password\",\"email_confirm\":true}" > /dev/null
  curl -sS -X POST "$API/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON" -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

rpc() { # rpc <token> <name> <json-body>
  curl -sS -X POST "$API/rest/v1/rpc/$2" \
    -H "apikey: $ANON" -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" -d "$3"
}

upsert() { # upsert <token> <table> <on_conflict> <json-array>
  curl -sS -o /dev/null -w '%{http_code}' -X POST "$API/rest/v1/$2?on_conflict=$3" \
    -H "apikey: $ANON" -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=minimal" -d "$4"
}

stamp="$(date +%s)$RANDOM"
ana_token="$(make_user "ana-$stamp@example.com")"
ben_token="$(make_user "ben-$stamp@example.com")"

if [[ -z "$ana_token" || -z "$ben_token" ]]; then
  echo "Could not sign in test users." >&2
  exit 1
fi

group_id="$(uuidgen | tr 'A-Z' 'a-z')"
ana_member="$(uuidgen | tr 'A-Z' 'a-z')"
marco_member="$(uuidgen | tr 'A-Z' 'a-z')"
expense_id="$(uuidgen | tr 'A-Z' 'a-z')"
settlement_id="$(uuidgen | tr 'A-Z' 'a-z')"

echo "Client contract"

# --- Sharing a local group --------------------------------------------------
# Argument names here are the ones SyncEngine.shareGroup sends.
adopt="$(rpc "$ana_token" adopt_local_group "$(cat <<EOF
{"p_group_id":"$group_id","p_name":"Lisbon Trip","p_kind":"trip","p_color_index":2,
 "p_currency_code":"EUR","p_simplify_debts":true,
 "p_members":[{"member_id":"$ana_member","display_name":"Ana","color_index":0,"is_me":true},
              {"member_id":"$marco_member","display_name":"Marco","color_index":1,"is_me":false}]}
EOF
)")"
[[ "$adopt" == "\"$group_id\"" ]] && check "adopt_local_group uploads a group under the id the device already uses" ok \
  || check "adopt_local_group uploads a group under the id the device already uses ($adopt)" no

# --- Pushing a group row ----------------------------------------------------
code="$(upsert "$ana_token" groups id "$(cat <<EOF
[{"id":"$group_id","name":"Lisbon Trip","kind":"trip","color_index":2,
  "default_currency_code":"EUR","simplify_debts":true,"notes":"","is_archived":false}]
EOF
)")"
[[ "$code" == 2* ]] && check "a group row upserts with the columns the client sends" ok \
  || check "a group row upserts with the columns the client sends (HTTP $code)" no

code="$(upsert "$ana_token" group_members group_id,member_id "$(cat <<EOF
[{"group_id":"$group_id","member_id":"$ana_member","display_name":"Ana","color_index":0},
 {"group_id":"$group_id","member_id":"$marco_member","display_name":"Marco","color_index":1}]
EOF
)")"
[[ "$code" == 2* ]] && check "the roster upserts on the composite key" ok \
  || check "the roster upserts on the composite key (HTTP $code)" no

# --- Pushing an expense -----------------------------------------------------
# 8450 split three ways is the case that proves the client and the database
# agree about remainders: 2817 + 2817 + 2816.
code="$(upsert "$ana_token" expenses id "$(cat <<EOF
[{"id":"$expense_id","group_id":"$group_id","title":"Dinner","notes":"",
  "amount_minor_units":8450,"currency_code":"EUR","date":"2026-08-01T19:00:00.000Z",
  "category":"food","split_method":"equal","tax_minor_units":0,"tip_minor_units":0,
  "base_currency_code":"EUR","exchange_rate_to_base":1.0,
  "payers":[{"participantId":"$ana_member","amountMinorUnits":8450}],
  "shares":[{"participantId":"$ana_member","amountMinorUnits":2817,"weight":1},
            {"participantId":"$marco_member","amountMinorUnits":5633,"weight":2}],
  "items":[]}]
EOF
)")"
[[ "$code" == 2* ]] && check "an expense upserts with payers and shares as JSONB" ok \
  || check "an expense upserts with payers and shares as JSONB (HTTP $code)" no

# The same push with a cent missing must be refused by the database.
code="$(upsert "$ana_token" expenses id "$(cat <<EOF
[{"id":"$(uuidgen | tr 'A-Z' 'a-z')","group_id":"$group_id","title":"Bad","notes":"",
  "amount_minor_units":1000,"currency_code":"EUR","date":"2026-08-01T19:00:00.000Z",
  "category":"food","split_method":"equal","tax_minor_units":0,"tip_minor_units":0,
  "base_currency_code":"EUR","exchange_rate_to_base":1.0,
  "payers":[{"participantId":"$ana_member","amountMinorUnits":1000}],
  "shares":[{"participantId":"$ana_member","amountMinorUnits":999}],"items":[]}]
EOF
)")"
[[ "$code" == 4* ]] && check "a split that loses a cent is rejected over HTTP, not just in SQL" ok \
  || check "a split that loses a cent is rejected over HTTP, not just in SQL (HTTP $code)" no

code="$(upsert "$ana_token" settlements id "$(cat <<EOF
[{"id":"$settlement_id","group_id":"$group_id","from_member_id":"$marco_member",
  "to_member_id":"$ana_member","amount_minor_units":5633,"currency_code":"EUR",
  "date":"2026-08-05T10:00:00.000Z","method":"cash","notes":"",
  "base_currency_code":"EUR","exchange_rate_to_base":1.0}]
EOF
)")"
[[ "$code" == 2* ]] && check "a settlement upserts with the columns the client sends" ok \
  || check "a settlement upserts with the columns the client sends (HTTP $code)" no

# --- Pulling ----------------------------------------------------------------
pull="$(rpc "$ana_token" pull_changes '{"since":"-infinity"}')"
printf '%s' "$pull" | grep -q '"server_time"' \
  && check "pull_changes returns a server_time to use as the next cursor" ok \
  || check "pull_changes returns a server_time to use as the next cursor" no

printf '%s' "$pull" | grep -q "$expense_id" \
  && check "pull_changes returns the expense that was just pushed" ok \
  || check "pull_changes returns the expense that was just pushed" no

printf '%s' "$pull" | grep -q '"amountMinorUnits": *2817' \
  && check "shares survive the round trip with their exact minor units" ok \
  || check "shares survive the round trip with their exact minor units" no

# The client parses this string. If Postgres formats it in a way
# SyncEngine.date(from:) rejects, the cursor never advances and every sync
# re-fetches all of history.
server_time="$(printf '%s' "$pull" | sed -n 's/.*"server_time": *"\([^"]*\)".*/\1/p')"
python3 - "$server_time" <<'PY' && check "server_time is a timestamp the client can parse" ok || check "server_time is a timestamp the client can parse" no
import re, sys
value = sys.argv[1]
sys.exit(0 if re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}:\d{2}|Z)$', value) else 1)
PY

# A cursor in the future must return nothing, or a quiet sync would still
# download the world every time.
later="$(rpc "$ana_token" pull_changes "{\"since\":\"$server_time\"}")"
printf '%s' "$later" | grep -q "\"expenses\": *\[\]" \
  && check "a cursor from the last pull returns no expenses the second time" ok \
  || check "a cursor from the last pull returns no expenses the second time" no

# --- The outsider -----------------------------------------------------------
ben_pull="$(rpc "$ben_token" pull_changes '{"since":"-infinity"}')"
printf '%s' "$ben_pull" | grep -q "$expense_id" \
  && check "someone outside the group cannot pull its expenses" no \
  || check "someone outside the group cannot pull its expenses" ok

# --- Invites ----------------------------------------------------------------
token="$(rpc "$ana_token" create_invite "{\"p_group_id\":\"$group_id\",\"p_member_id\":\"$marco_member\"}" | tr -d '"')"
[[ ${#token} -eq 32 ]] && check "create_invite returns a 32-character token" ok \
  || check "create_invite returns a 32-character token (got '${token}')" no

preview="$(rpc "$ben_token" preview_invite "{\"p_token\":\"$token\"}")"
printf '%s' "$preview" | grep -q '"group_name": *"Lisbon Trip"' \
  && check "preview_invite names the group before anyone joins it" ok \
  || check "preview_invite names the group before anyone joins it" no
printf '%s' "$preview" | grep -q '"claims_member_name": *"Marco"' \
  && check "preview_invite says which slot is being handed over" ok \
  || check "preview_invite says which slot is being handed over" no

redeem="$(rpc "$ben_token" redeem_invite "{\"p_token\":\"$token\"}")"
printf '%s' "$redeem" | grep -q "\"member_id\": *\"$marco_member\"" \
  && check "redeeming keeps the reserved member id, so old expenses still point at it" ok \
  || check "redeeming keeps the reserved member id, so old expenses still point at it" no

ben_pull="$(rpc "$ben_token" pull_changes '{"since":"-infinity"}')"
printf '%s' "$ben_pull" | grep -q "$expense_id" \
  && check "after joining, the new member pulls the group's history" ok \
  || check "after joining, the new member pulls the group's history" no

# --- Tombstones -------------------------------------------------------------
code="$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH \
  "$API/rest/v1/expenses?id=eq.$expense_id" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ana_token" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"deleted_at":"2026-08-10T00:00:00.000Z"}')"
[[ "$code" == 2* ]] && check "a deletion is pushed as a deleted_at patch" ok \
  || check "a deletion is pushed as a deleted_at patch (HTTP $code)" no

ben_pull="$(rpc "$ben_token" pull_changes '{"since":"-infinity"}')"
printf '%s' "$ben_pull" | grep -q '"deleted_at": *"2026-08-10' \
  && check "the tombstone reaches the other member, so the expense disappears there too" ok \
  || check "the tombstone reaches the other member, so the expense disappears there too" no

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
