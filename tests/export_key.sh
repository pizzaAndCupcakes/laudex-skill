#!/usr/bin/env bash
# Checks hooks/export-key.sh offline: a valid key from the plugin's settings is
# exported for laudex.sh, anything else is never written to CLAUDE_ENV_FILE.
#
#   bash tests/export_key.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/export-key.sh"
ENVF="$(mktemp)"
trap 'rm -f "$ENVF"' EXIT
fails=0 passes=0
check() { if [ "$1" = "$2" ]; then passes=$((passes + 1)); else echo "FAIL $3: got '$1', want '$2'"; fails=$((fails + 1)); fi; }

KEY=lx_0123456789abcdef0123456789abcdef

CLAUDE_ENV_FILE="$ENVF" CLAUDE_PLUGIN_OPTION_API_KEY="$KEY" bash "$HOOK"
check "$?" 0 "valid key exit"
check "$(. "$ENVF"; printf '%s' "${LAUDEX_API_KEY:-}")" "$KEY" "valid key exported"

: > "$ENVF"
out=$(CLAUDE_ENV_FILE="$ENVF" CLAUDE_PLUGIN_OPTION_API_KEY='lx_1; touch /tmp/pwned' bash "$HOOK" 2>&1)
check "$?" 0 "malformed key exit"
check "$(cat "$ENVF")" "" "malformed key not written"
check "$([[ "$out" == *lx_1* ]] && echo leaked || echo hidden)" hidden "malformed key not echoed"

: > "$ENVF"
CLAUDE_ENV_FILE="$ENVF" bash "$HOOK"
check "$?" 0 "no key exit"
check "$(cat "$ENVF")" "" "no key, nothing written"

CLAUDE_PLUGIN_OPTION_API_KEY="$KEY" CLAUDE_ENV_FILE= bash "$HOOK"
check "$?" 0 "no env file exit"

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
