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

key="${CLAUDE_PLUGIN_OPTION_API_KEY:-}"
[ -n "$key" ] && [ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0

# CLAUDE_ENV_FILE is sourced by a shell, so only the exact key format is
# written: anything else could inject commands into every Bash call.
if [[ "$key" =~ ^lx_[0-9a-f]{32}$ ]]; then
  printf 'export LAUDEX_API_KEY=%s\n' "$key" >> "$CLAUDE_ENV_FILE"
else
  echo "laudex: the API key in the plugin's settings is not in the lx_<32 hex> format; ignoring it" >&2
fi
exit 0
