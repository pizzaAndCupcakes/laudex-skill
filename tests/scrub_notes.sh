#!/usr/bin/env bash
# Checks laudex.sh's note scrubber offline: every case runs `report --dry-run`,
# which prints the request body and sends nothing. Needs jq or python3.
#
#   bash tests/scrub_notes.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../skills/laudex/scripts/laudex.sh"
export LAUDEX_API_KEY="lx_00000000000000000000000000000000" LAUDEX_REPORTING=on
fails=0 passes=0

body() { bash "$SCRIPT" report some-id success "$1" --dry-run 2>/dev/null; }
notes_of() {
  if command -v jq >/dev/null 2>&1; then jq -r '.notes // "<absent>"'
  else python3 -c 'import json,sys; print(json.load(sys.stdin).get("notes","<absent>"))'; fi
}

# gone <secret> [context]: the secret must not survive inside a note.
gone() {
  local secret="$1" note="${2:-before $1 after}" out
  out=$(body "$note" | notes_of)
  if [[ "$out" == *"$secret"* ]]; then
    echo "FAIL kept:    $secret"; echo "     note:    $out"; fails=$((fails + 1))
  else passes=$((passes + 1)); fi
}

# kept <fact> [context]: a fact about a tool must survive unchanged.
kept() {
  local fact="$1" note="${2:-before $1 after}" out
  out=$(body "$note" | notes_of)
  if [[ "$out" != *"$fact"* ]]; then
    echo "FAIL mangled: $fact"; echo "     note:    $out"; fails=$((fails + 1))
  else passes=$((passes + 1)); fi
}

# Secrets by prefix
gone "sk-ant-api03-AbCdEfGhIjKlMnOpQrStUv"
gone "sk_live_51HAbCdEfGhIjKlMn"                         # Stripe secret key
gone "rk_live_51HAbCdEfGhIjKlMn"                         # Stripe restricted key
gone "whsec_AbCdEfGhIjKlMnOpQrSt"                        # Stripe webhook secret
gone "ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
gone "AIzaSyD-AbCdEfGhIjKlMnOpQrStUvWxYz01234"           # Google API key
gone "glpat-AbCdEfGhIjKlMnOpQrSt"                        # GitLab
gone "npm_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
gone "hf_AbCdEfGhIjKlMnOpQrStUvWxYz01234567"             # Hugging Face
gone "lx_0123456789abcdef0123456789abcdef"
gone "AKIAABCDEFGHIJKLMNOP"
gone "xoxb-1234567890-abcdefghij"

# Assignments: the value goes, the variable name stays
gone "3f9a8b7c6d5e4f30" "set API_KEY=3f9a8b7c6d5e4f30 first"
kept "API_KEY=" "set API_KEY=3f9a8b7c6d5e4f30 first"
gone "hunter2" "login with password=hunter2 failed"
gone "abc123" "export GITHUB_TOKEN=abc123"
gone "s3cretpw" "connect postgres://admin:s3cretpw@db.example.com/app"

# Long tokens with both letters and digits, whatever their prefix
gone "q8Zr2LmN4pXw7Ty1Vb6Kc9Hd3Fg5Js0A"
kept "3c5a2bf3-d8c9-42f6-9981-1a3bd901dc4c"              # a uuid is not a secret
kept "browser_take_screenshot"

# The user's files
gone "/Users/jane/acme/out.md"
gone "acme" "wrote /workspace/acme/plan.md"
gone "acme" "installed into /opt/acme/app"
gone "Work/acme.txt" "saved /Volumes/Work/acme.txt"
gone "acme-q3-plan.docx" "converted ./acme-q3-plan.docx fine"
gone "acme-q3-plan.docx" "converted acme-q3-plan.docx fine"
gone "acme/notes.txt" "read ../acme/notes.txt"
gone "notes.txt" "read ~/notes.txt"
gone 'jane' 'opened C:\Users\jane\file.txt'
gone "acme-q4-plan.html" "read /tmp/acme-q4-plan.html"
gone "acme" "read /tmp/acme/report"

# Private networks and people
gone "10.0.0.12" "could not reach 10.0.0.12:5432 from the server"
gone "192.168.1.20" "bound to 192.168.1.20"
gone "172.20.3.4" "proxy at 172.20.3.4:8080"
gone "localhost:3000" "called http://localhost:3000/api"
gone "intranet.acme.corp" "fetched https://intranet.acme.corp/x"
gone "acme.corp" "cloned git@gitlab.acme.corp:team/app.git"
gone "jane@acme.com"

# Facts about a tool that must survive
kept "git@github.com:microsoft/playwright-mcp.git"
kept "ssh://git@github.com/microsoft/playwright-mcp"
kept "/tmp/playwright-mcp-output" "it wrote snapshots into /tmp/playwright-mcp-output."
kept "/tmp/playwright-mcp-output" "files land in /tmp/playwright-mcp-output (not the cwd)"
kept "BROWSERBASE_API_KEY" "needed BROWSERBASE_API_KEY, which the README only mentions in passing"
kept "https://api.exa.ai/search" "Error: ECONNREFUSED at https://api.exa.ai/search."
kept "https://example.com/home/docs"
kept "1.64.0-alpha" "ran @playwright/mcp@1.64.0-alpha via npx"
kept "package.json"

# A clean note passes through untouched
clean="Ran via npx (@browserbasehq/mcp). browser_navigate and browser_screenshot worked first try at 1280px."
[ "$(body "$clean" | notes_of)" = "$clean" ] && passes=$((passes + 1)) ||
  { echo "FAIL clean note changed"; fails=$((fails + 1)); }

# No note: the field is left out, not sent empty
out=$(bash "$SCRIPT" report some-id failure --dry-run 2>/dev/null | notes_of)
[ "$out" = "<absent>" ] && passes=$((passes + 1)) ||
  { echo "FAIL empty note sent as: $out"; fails=$((fails + 1)); }

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
