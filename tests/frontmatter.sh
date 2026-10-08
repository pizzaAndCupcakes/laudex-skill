#!/usr/bin/env bash
# Checks skills/laudex/SKILL.md's frontmatter offline against the Agent Skills
# specification (https://agentskills.io/specification), so the one file is valid
# for Claude Code and for directories that validate against the spec, and against
# plugin.json, so the two versions cannot drift. Needs python3.
#
#   bash tests/frontmatter.sh
#
# The specification's own validator says the same: `skills-ref validate skills/laudex`.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$HERE/../skills/laudex"
fails=0 passes=0
check() { if [ "$1" = "$2" ]; then passes=$((passes + 1)); else echo "FAIL $3: got '$1', want '$2'"; fails=$((fails + 1)); fi; }

# One line per fact, "key<TAB>value": the top-level keys in order, the length of
# the description, and each entry under `metadata`.
facts=$(python3 - "$SKILL_DIR/SKILL.md" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
assert lines[0] == "---", "SKILL.md must start with frontmatter"
front = lines[1:lines.index("---", 1)]
top, section = [], None
for line in front:
    key = re.match(r"([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$", line)
    if key:
        section = key.group(1)
        top.append(section)
        if section in ("name", "license"):
            print(f"{section}\t{key.group(2)}")
        if section == "description":
            print(f"description_length\t{len(key.group(2))}")
    elif section == "metadata":
        entry = re.match(r"  ([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$", line)
        print(f"metadata.{entry.group(1)}\t{entry.group(2).strip(chr(34))}" if entry else f"metadata_not_a_string\t{line.strip()}")
print("top\t" + " ".join(top))
PY
)
fact() { printf '%s\n' "$facts" | awk -F'\t' -v k="$1" '$1 == k { print $2 }'; }

ALLOWED=" name description license compatibility metadata allowed-tools "
unexpected=""
for key in $(fact top); do
  [[ "$ALLOWED" == *" $key "* ]] || unexpected="$unexpected $key"
done
check "${unexpected# }" "" "only the fields the specification allows at the top level"
check "$(fact name)" "$(basename "$(cd "$SKILL_DIR" && pwd)")" "name matches its directory"
length=$(fact description_length)
check "$([ "${length:-0}" -ge 1 ] && [ "${length:-0}" -le 1024 ] && echo ok || echo "$length characters")" ok "description is 1 to 1024 characters"
check "$(fact metadata_not_a_string)" "" "metadata maps strings to strings"

plugin_version=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$HERE/../.claude-plugin/plugin.json")
check "$(fact metadata.version)" "$plugin_version" "the skill's version is plugin.json's"
check "$([ -n "$(fact metadata.author)" ] && echo kept || echo missing)" kept "author is kept, under metadata"
check "$([ -n "$(fact metadata.tags)" ] && echo kept || echo missing)" kept "tags are kept, under metadata"

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
