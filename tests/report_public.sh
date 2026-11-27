#!/usr/bin/env bash
# Checks `laudex.sh report --public` offline: every case runs with --dry-run, which
# prints the request body and sends nothing. Needs jq or python3.
#
#   bash tests/report_public.sh
#
# The rule being mirrored is the server's (laudex.dev, LAU-394): `public: true` shows the
# report on its listing page as a review, and needs a note. Without the flag no `public`
# field is sent, so a report stays private.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../skills/laudex/scripts/laudex.sh"
export LAUDEX_API_KEY="lx_$(printf '0%.0s' {1..32})" LAUDEX_REPORTING=on
fails=0 passes=0
errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT

field() {
  if command -v jq >/dev/null 2>&1; then jq -c --arg k "$1" 'if has($k) then .[$k] else "<absent>" end'
  else python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[sys.argv[1]]) if sys.argv[1] in d else "\"<absent>\"")' "$1"; fi
}
check() { # check <got> <want> <label>
  if [ "$1" = "$2" ]; then passes=$((passes + 1)); else echo "FAIL $3: got '$1', want '$2'"; fails=$((fails + 1)); fi
}
run() { out=$(bash "$SCRIPT" report some-id "$@" --dry-run 2>"$errfile"); status=$?; err=$(cat "$errfile"); }

# With the flag: public is a JSON true beside the note and rating
run success "worked first try" --rating 5 --public
check "$status" 0 "public with a note exits 0"
check "$(printf '%s' "$out" | field public)" true "public is true in the body"
check "$(printf '%s' "$out" | field notes)" '"worked first try"' "note unchanged"
check "$(printf '%s' "$out" | field rating)" 5 "rating kept"

# The flag can sit anywhere after the outcome, and goes with failure too
run failure --public "timed out on a slow page" --rating 2
check "$status:$(printf '%s' "$out" | field public):$(printf '%s' "$out" | field success)" "0:true:false" "flag before the note, with failure"

# Without the flag: no public field at all
run success "a private note"
check "$(printf '%s' "$out" | field public)" '"<absent>"' "no flag, no public field"

# The note is scrubbed the same way when public
run success "worked; config in /Users/someone/project/x.json" --public
check "$(printf '%s' "$out" | field notes)" '"worked; config in <path>"' "a public note is scrubbed"

# Refused before sending without a note: nothing on stdout, non-zero exit, a message naming the note
refuse() { # refuse <label> <args...>
  local label="$1"; shift
  run "$@"
  if [ "$status" -ne 0 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q -- '--public needs a note'; then passes=$((passes + 1))
  else echo "FAIL $label: status=$status stdout='$out' stderr='$err'"; fails=$((fails + 1)); fi
}
refuse "public with no note" success --public
refuse "public with a blank note" success "   " --public
refuse "public with a rating and no note" success --rating 4 --public

# Reporting off sends nothing, public or not
out=$(LAUDEX_REPORTING=off bash "$SCRIPT" report some-id success "n" --public --dry-run 2>/dev/null); status=$?
check "$status:$out" "0:" "reporting off sends nothing"

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
