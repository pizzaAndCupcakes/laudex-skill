#!/usr/bin/env bash
# Checks what `laudex.sh search` keeps of a response, for each mode the API can
# answer in. Nothing leaves the machine: a stub on 127.0.0.1 serves canned
# responses. Needs jq (the trim is jq's; without it the script prints the
# response whole) and python3 (the stub).
#
#   bash tests/search_trim.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../skills/laudex/scripts/laudex.sh"
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { echo "skipped: needs jq and python3"; exit 0; }

DIR="$(mktemp -d)"
trap 'kill "$STUB" 2>/dev/null; wait "$STUB" 2>/dev/null; rm -rf "$DIR"' EXIT
fails=0 passes=0
check() { if [ "$1" = "$2" ]; then passes=$((passes + 1)); else echo "FAIL $3: got '$1', want '$2'"; fails=$((fails + 1)); fi; }

service='{"id":"s1","name":"Playwright MCP","type":"mcp_server","url":"https://example.com","description":"Browser automation","metadata":{"quality_signals":{"big":"blob"}}}'
highlights='{"owner":"microsoft","repo":"microsoft/playwright-mcp","stars":31088,"weekly_downloads":null,"fork":false,"archived":false,"install":null}'

cat > "$DIR/semantic.json" <<JSON
{"mode":"semantic","query":"q","routing":{"category":"browser_automation","scope":"category","confidence":0.97,"candidates_considered":40,"rounds":1},
 "results":[{"service":$service,"attribution":null,"highlights":$highlights,
   "score":{"success_rate":0,"signal_count":0,"rating_average":4,"rating_count":2,"fit":0.96,"best_fit_share":0.7,"quality":0.9}}]}
JSON
cat > "$DIR/embedding.json" <<JSON
{"mode":"embedding","query":"q","note":"this key's 100 judged searches for today are used up, so results are not judged until 00:00 UTC",
 "results":[{"service":$service,"attribution":{"glama_url":"https://glama.ai/mcp/servers/x","credit":"Data from Glama"},"highlights":$highlights,
   "score":{"success_rate":0,"signal_count":0,"rating_average":null,"rating_count":0,"similarity":0.658,"quality":0.9}}]}
JSON
cat > "$DIR/keyword.json" <<JSON
{"mode":"keyword","query":"q","results":[{"service":$service,"attribution":null,"highlights":$highlights,"score":{"success_rate":0,"signal_count":0}}]}
JSON

# Serves <intent>.json for /api/search?intent=<intent>, on a port the system picks.
python3 - "$DIR" > "$DIR/port" <<'PY' &
import http.server, sys, urllib.parse
root = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("intent", [""])[0]
        body = open(f"{root}/{name}.json", "rb").read()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
PY
STUB=$!
for _ in $(seq 1 50); do [ -s "$DIR/port" ] && break; sleep 0.1; done
[ -s "$DIR/port" ] || { echo "FAIL: the stub did not start"; exit 1; }
export LAUDEX_URL="http://127.0.0.1:$(cat "$DIR/port")" LAUDEX_API_KEY="lx_00000000000000000000000000000000"
search() { bash "$SCRIPT" search "$1" 2>/dev/null; }

out=$(search semantic)
check "$(jq -r .mode <<<"$out")" semantic "semantic: mode"
check "$(jq -c '.results[0] | [.fit, .best_fit_share, .quality]' <<<"$out")" "[0.96,0.7,0.9]" "semantic: fit, share and quality kept"
check "$(jq -r '.results[0] | has("similarity")' <<<"$out")" false "semantic: no similarity key"
check "$(jq -c '.results[0] | [.rating_average, .rating_count]' <<<"$out")" "[4,2]" "semantic: rating average and count kept"
check "$(jq -r 'has("note")' <<<"$out")" false "semantic: no note key"
check "$(jq -r .routing.category <<<"$out")" browser_automation "semantic: routing kept"

out=$(search embedding)
check "$(jq -r .mode <<<"$out")" embedding "embedding: mode"
check "$(jq -r .note <<<"$out")" "this key's 100 judged searches for today are used up, so results are not judged until 00:00 UTC" "embedding: note kept"
check "$(jq -c '.results[0] | [.similarity, .quality]' <<<"$out")" "[0.658,0.9]" "embedding: similarity and quality kept"
check "$(jq -r '.results[0] | has("fit")' <<<"$out")" false "embedding: no fit key"
check "$(jq -c '.results[0] | [has("rating_average"), .rating_count]' <<<"$out")" "[false,0]" "embedding: a null average is dropped, the count kept"
check "$(jq -r 'has("routing")' <<<"$out")" false "embedding: no routing key"
check "$(jq -r '[.credit, .results[0].glama_url] | join(" | ")' <<<"$out")" "Data from Glama | https://glama.ai/mcp/servers/x" "embedding: Glama credit and link kept"

out=$(search keyword)
check "$(jq -r .mode <<<"$out")" keyword "keyword: mode"
check "$(jq -c '.results[0] | [has("fit"), has("similarity"), has("quality")]' <<<"$out")" "[false,false,false]" "keyword: no ranking scores"
# Whatever the mode, the trim keeps what an agent chooses by and drops the metadata blob.
check "$(jq -c '.results[0] | [.id, .name, .owner, .stars, has("metadata")]' <<<"$out")" '["s1","Playwright MCP","microsoft",31088,false]' "trim keeps identity, drops metadata"

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
