#!/usr/bin/env bash
# Laudex CLI helper — search the catalog, inspect a service, report an outcome.
#
#   laudex.sh search "<intent>" [--type mcp_server|api|tool|saas|other] [--limit N]
#   laudex.sh service <service_id>
#   laudex.sh report <service_id> success|failure "<notes>"
#   laudex.sh register [email]
#
# API key: $LAUDEX_API_KEY, else ~/.config/laudex/credentials. If neither exists,
# the first call registers a new agent and saves the key there.
# Base URL: $LAUDEX_URL (default https://laudex.dev).

set -euo pipefail

BASE="${LAUDEX_URL:-https://laudex.dev}"
CRED_FILE="${LAUDEX_CREDENTIALS:-$HOME/.config/laudex/credentials}"

die() { echo "laudex: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Build a JSON object from key/value pairs without hand-escaping strings.
# Values prefixed with "json:" are emitted raw (for booleans).
json_obj() {
  if have jq; then
    local args=() filter="{" first=1 k v
    while [ $# -gt 0 ]; do
      k="$1"; v="$2"; shift 2
      [ $first -eq 1 ] || filter+=","
      first=0
      if [[ "$v" == json:* ]]; then args+=(--argjson "$k" "${v#json:}"); else args+=(--arg "$k" "$v"); fi
      filter+="\"$k\":\$$k"
    done
    jq -cn "${args[@]}" "$filter}"
  elif have python3; then
    python3 - "$@" <<'PY'
import json, sys
a = sys.argv[1:]
out = {}
for k, v in zip(a[::2], a[1::2]):
    out[k] = json.loads(v[5:]) if v.startswith("json:") else v
print(json.dumps(out))
PY
  else
    die "need jq or python3 to build request bodies"
  fi
}

register() {
  local email="${1:-}" body resp key
  if [ -n "$email" ]; then body=$(json_obj email "$email"); else body='{}'; fi
  resp=$(curl -sS -m 20 -X POST "$BASE/api/agents/register" -H 'Content-Type: application/json' -d "$body")
  key=$(printf '%s' "$resp" | grep -o '"api_key":"lx_[a-f0-9]*"' | cut -d'"' -f4 || true)
  [ -n "$key" ] || die "registration failed: $resp"
  mkdir -p "$(dirname "$CRED_FILE")"
  (umask 077; printf '%s\n' "$key" > "$CRED_FILE")
  echo "Registered with Laudex; key saved to $CRED_FILE" >&2
}

api_key() {
  if [ -n "${LAUDEX_API_KEY:-}" ]; then printf '%s' "$LAUDEX_API_KEY"; return; fi
  [ -s "$CRED_FILE" ] || register "${LAUDEX_EMAIL:-}"
  head -n1 "$CRED_FILE" | tr -d '[:space:]'
}

# GET/POST with auth. Prints the body; exits non-zero on HTTP >= 400.
call() {
  local method="$1" path="$2" data="${3:-}" out status
  out=$(mktemp)
  local args=(-sS -m 60 -o "$out" -w '%{http_code}' -X "$method" "$BASE$path" -H "Authorization: Bearer $(api_key)")
  [ -z "$data" ] || args+=(-H 'Content-Type: application/json' -d "$data")
  status=$(curl "${args[@]}") || { rm -f "$out"; die "request to $BASE$path failed"; }
  if [ "$status" -ge 400 ]; then
    echo "laudex: HTTP $status from $path: $(cat "$out")" >&2
    rm -f "$out"; exit 1
  fi
  cat "$out"; rm -f "$out"
}

urlencode() {
  if have jq; then printf '%s' "$1" | jq -sRr @uri
  else python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1"; fi
}

cmd="${1:-}"; shift || true
case "$cmd" in
  search)
    intent="${1:-}"; shift || true
    [ -n "$intent" ] || die 'usage: laudex.sh search "<intent>" [--type T] [--limit N]'
    qs="intent=$(urlencode "$intent")"
    while [ $# -gt 0 ]; do
      case "$1" in
        --type) qs+="&type=$2"; shift 2 ;;
        --limit) qs+="&limit=$2"; shift 2 ;;
        *) die "unknown flag: $1" ;;
      esac
    done
    resp=$(call GET "/api/search?$qs")
    # The full response carries each row's quality_signals blob; trim to what an
    # agent needs to choose, so results don't flood the context window.
    if have jq; then
      printf '%s' "$resp" | jq '{mode, routing: (.routing // null | if . then {category, candidates_considered} else null end),
        results: [.results[] | {id: .service.id, name: .service.name, type: .service.type, url: .service.url,
          description: ((.service.description // "") | .[0:240]),
          owner: .highlights.owner, repo: .highlights.repo, stars: .highlights.stars,
          weekly_downloads: .highlights.weekly_downloads, install: .highlights.install,
          fit: .score.fit, best_fit_share: .score.best_fit_share, quality: .score.quality,
          success_rate: .score.success_rate, signal_count: .score.signal_count}
          | with_entries(select(.value != null))]}'
    else
      printf '%s\n' "$resp"
    fi
    ;;
  service)
    [ -n "${1:-}" ] || die "usage: laudex.sh service <service_id>"
    call GET "/api/services/$1"
    ;;
  report)
    [ $# -ge 2 ] || die 'usage: laudex.sh report <service_id> success|failure "<notes>"'
    case "$2" in
      success|true) ok=true ;;
      failure|false) ok=false ;;
      *) die "outcome must be success or failure, got: $2" ;;
    esac
    call POST /api/signal "$(json_obj service_id "$1" success "json:$ok" notes "${3:-}")"
    echo
    ;;
  register)
    register "${1:-}"
    ;;
  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
