#!/usr/bin/env bash
# SessionStart hook: hand the API key from the plugin's settings to laudex.sh.
#
# Claude Code keeps a `sensitive` userConfig value in the platform's secure
# store and passes it to hooks (as CLAUDE_PLUGIN_OPTION_<KEY>) and MCP servers,
# never to commands Claude runs through the Bash tool, which is how the skill
# calls laudex.sh. A SessionStart hook can export variables into those
# commands by appending to CLAUDE_ENV_FILE, so this is the bridge.
#
# The key is never printed. With no key configured this does nothing, and
# laudex.sh falls back to ~/.config/laudex/credentials (registering on first
# use if that file is missing too).
#
# CLAUDE_ENV_FILE is a plain file under ~/.claude/session-env/<session id>/.
# Claude Code makes the directory, this hook's append makes the file, and the
# file outlives the session, so the hook keeps it readable by the user alone.

key="${CLAUDE_PLUGIN_OPTION_API_KEY:-}"
[ -n "$key" ] && [ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0

# CLAUDE_ENV_FILE is sourced by a shell, so only the exact key format is
# written: anything else could inject commands into every Bash call.
if [[ "$key" =~ ^lx_[0-9a-f]{32}$ ]]; then
  umask 077 # a file the append creates is never readable by others
  printf 'export LAUDEX_API_KEY=%s\n' "$key" >> "$CLAUDE_ENV_FILE"
  # A file that was already there keeps its mode, so set it. A mode that cannot
  # be set must not stop the session: the key is exported either way, and the
  # user is told which file to look at.
  chmod 600 "$CLAUDE_ENV_FILE" 2>/dev/null ||
    echo "laudex: could not set mode 600 on $CLAUDE_ENV_FILE, which now holds the API key; check that only you can read it" >&2
else
  echo "laudex: the API key in the plugin's settings is not in the lx_<32 hex> format; ignoring it" >&2
fi
exit 0
