#!/usr/bin/env bash
# Checks hooks/export-key.sh offline: a valid key from the plugin's settings is
# exported for laudex.sh into a file only the user can read, anything else is
# never written to CLAUDE_ENV_FILE.
#
#   bash tests/export_key.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/export-key.sh"
ENVF="$(mktemp)"
DIR="$(mktemp -d)"
trap 'rm -rf "$ENVF" "$DIR"' EXIT
fails=0 passes=0
check() { if [ "$1" = "$2" ]; then passes=$((passes + 1)); else echo "FAIL $3: got '$1', want '$2'"; fails=$((fails + 1)); fi; }

KEY=lx_0123456789abcdef0123456789abcdef
# The file's permission bits in octal: GNU stat first, then BSD (macOS).
mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

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

# The file holds the key once the hook has run, so only the user may read it,
# whoever created the file and with whatever mode.
chmod 644 "$ENVF"
printf 'export EARLIER=1\n' > "$ENVF"
CLAUDE_ENV_FILE="$ENVF" CLAUDE_PLUGIN_OPTION_API_KEY="$KEY" bash "$HOOK"
check "$(mode "$ENVF")" 600 "a file that was 644 ends at 600"
check "$(cat "$ENVF")" "$(printf 'export EARLIER=1\nexport LAUDEX_API_KEY=%s' "$KEY")" "an earlier line is kept, the export follows it"

NEW="$DIR/created-by-the-hook"
CLAUDE_ENV_FILE="$NEW" CLAUDE_PLUGIN_OPTION_API_KEY="$KEY" bash "$HOOK"
check "$(mode "$NEW")" 600 "a file the hook creates ends at 600"

# A mode that cannot be set must not stop the session or undo the export; the
# hook says so, naming the file and never the key.
STUB="$DIR/bin"
mkdir "$STUB"
printf '#!/bin/sh\nexit 1\n' > "$STUB/chmod"
chmod +x "$STUB/chmod"
STUCK="$DIR/mode-cannot-be-set"
: > "$STUCK"
chmod 644 "$STUCK"
out=$(PATH="$STUB:$PATH" CLAUDE_ENV_FILE="$STUCK" CLAUDE_PLUGIN_OPTION_API_KEY="$KEY" bash "$HOOK" 2>"$DIR/stderr")
check "$?" 0 "chmod fails, exit"
err=$(cat "$DIR/stderr")
check "$(cat "$STUCK")" "export LAUDEX_API_KEY=$KEY" "chmod fails, the key is still exported"
check "$([[ "$err" == *"$STUCK"* ]] && echo named || echo silent)" named "chmod fails, stderr names the file"
check "$([[ "$out$err" == *"$KEY"* ]] && echo leaked || echo hidden)" hidden "chmod fails, key not echoed"

# With nothing to export the hook touches no file: none created, no mode changed.
chmod 644 "$ENVF"
before=$(cat "$ENVF")
CLAUDE_ENV_FILE="$ENVF" bash "$HOOK"
check "$(mode "$ENVF")$(cat "$ENVF")" "644$before" "no key, an existing file is left as it was"
CLAUDE_ENV_FILE="$DIR/never-created" bash "$HOOK"
check "$([ -e "$DIR/never-created" ] && echo created || echo absent)" absent "no key, no file created"

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
