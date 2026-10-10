#!/usr/bin/env bash
# Checks `laudex.sh report --rating` offline: every case runs with --dry-run, which
# prints the request body and sends nothing. Needs jq or python3.
#
#   bash tests/report_rating.sh
#
# The rule being mirrored is the server's (laudex.dev, LAU-152): an optional whole
# number from 1 to 5; 3 to 5 go with success, 1 and 2 with failure. The script
# refuses a bad rating before sending, so the agent sees why and no report is lost
# to a 400 it cannot read.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../skills/laudex/scripts/laudex.sh"
export LAUDEX_API_KEY="lx_$(printf '0%.0s' {1..32})" LAUDEX_REPORTING=on
fails=0 passes=0

# field <name>: the value of one key in the body on stdin, or <absent>.
field() {
  if command -v jq >/dev/null 2>&1; then jq -c --arg k "$1" 'if has($k) then .[$k] else "<absent>" end'
  else python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[sys.argv[1]]) if sys.argv[1] in d else "\"<absent>\"")' "$1"; fi
}
check() { # check <got> <want> <label>
  if [ "$1" = "$2" ]; then passes=$((passes + 1)); else echo "FAIL $3: got '$1', want '$2'"; fails=$((fails + 1)); fi
}
# run <args...>: stdout of `report some-id <args> --dry-run`; sets $status.
run() { out=$(bash "$SCRIPT" report some-id "$@" --dry-run 2>/tmp/laudex-rating-err.$$); status=$?; err=$(cat /tmp/laudex-rating-err.$$); rm -f /tmp/laudex-rating-err.$$; }

# A rating is sent as a JSON number, beside success and the note
run success "worked first try" --rating 5
check "$status" 0 "success with 5 exits 0"
check "$(printf '%s' "$out" | field rating)" 5 "rating 5 is a number in the body"
check "$(printf '%s' "$out" | field success)" true "success stays true"
check "$(printf '%s' "$out" | field notes)" '"worked first try"' "notes unchanged beside a rating"

# Each rating that goes with its outcome is accepted
for r in 3 4 5; do
  run success "n" --rating "$r"; check "$status:$(printf '%s' "$out" | field rating)" "0:$r" "success with $r"
done
for r in 1 2; do
  run failure "n" --rating "$r"; check "$status:$(printf '%s' "$out" | field rating)" "0:$r" "failure with $r"
done

# The flag can sit anywhere among the arguments
run success --rating 4 "note first"
check "$(printf '%s' "$out" | field rating):$(printf '%s' "$out" | field notes)" '4:"note first"' "flag before the note"
run success --rating 4
check "$(printf '%s' "$out" | field rating):$(printf '%s' "$out" | field notes)" '4:"<absent>"' "rating with no note sends no notes field"

# No rating: the field is left out, as before
run success "just a note"
check "$(printf '%s' "$out" | field rating)" '"<absent>"' "no flag, no rating field"
run failure
check "$(printf '%s' "$out" | field rating)" '"<absent>"' "no note and no flag"

# Refused before sending: nothing on stdout, a non-zero exit, a message naming rating
refuse() { # refuse <label> <args...>
  local label="$1"; shift
  run "$@"
  if [ "$status" -ne 0 ] && [ -z "$out" ] && printf '%s' "$err" | grep -qi 'rating'; then passes=$((passes + 1))
  else echo "FAIL $label: status=$status stdout='$out' stderr='$err'"; fails=$((fails + 1)); fi
}
refuse "rating 0" success "n" --rating 0
refuse "rating 6" success "n" --rating 6
refuse "rating 4.5" success "n" --rating 4.5
refuse "rating word" success "n" --rating great
refuse "rating empty" success "n" --rating ""
refuse "rating negative" success "n" --rating -1
refuse "rating with no value" success "n" --rating
refuse "success with 2" success "n" --rating 2
refuse "success with 1" success "n" --rating 1
refuse "failure with 3" failure "n" --rating 3
refuse "failure with 5" failure "n" --rating 5

# A contradiction says which ratings go with which outcome
run success "n" --rating 2
case "$err" in *"3 to 5"*"1 to 2"*|*"3 to 5"*"1 and 2"*) passes=$((passes + 1)) ;;
  *) echo "FAIL contradiction message does not give the pairing: $err"; fails=$((fails + 1)) ;; esac

# A rating alone never sends anything when reporting is off
out=$(LAUDEX_REPORTING=off bash "$SCRIPT" report some-id success "n" --rating 4 --dry-run 2>/dev/null); status=$?
check "$status:$out" "0:" "reporting off sends nothing, rating or not"

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
