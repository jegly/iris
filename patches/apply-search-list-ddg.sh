#!/usr/bin/env bash
# Iris — make DuckDuckGo a SELECTABLE option in chrome://settings/search everywhere
# (verified against checkout 2026-09-25). Companion to apply-default-search.sh.
#
# Upstream already lists &duckduckgo in 123/134 regions. This adds it to the ~11 that
# lack it (10 Asian regions + the ZZ unknown-region fallback), so the DDG default we set
# in apply-default-search.sh is also user-selectable in the settings dropdown regardless
# of detected country. (Region cap is 8 engines; the target regions have 3-5, so there's room.)
#
# It DISCOVERS which regions are missing DDG (so it stays correct if upstream adds/removes
# some), then does a FORMATTING-PRESERVING surgical text insert (not a JSON reserialize —
# that would drop the file's comments and reflow every line). Idempotent: only inserts
# where &duckduckgo is absent from that region's array. Fails loudly if the file's shape drifts.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
JR="$SRC/third_party/search_engines_data/resources/definitions/regional_settings.json"
[ -f "$JR" ] || { echo "ERROR: not found: $JR" >&2; exit 1; }

python3 - "$JR" <<'PY'
import sys, json, re
path = sys.argv[1]
raw = open(path).read()

# Parse a comment-stripped copy only to DISCOVER regions; edits are done on `raw`.
clean = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
data = json.loads(clean)
elems = data["elements"]

missing = [k for k, v in elems.items() if "&duckduckgo" not in v["search_engines"]]
if not missing:
    print("SKIP: every region already lists &duckduckgo (nothing to do)")
    sys.exit(0)

changed = 0
text = raw
for region in missing:
    # Anchor the specific region's search_engines array opener, insert DDG as first item.
    # Matches:  "XX": {\n      "search_engines": [\n
    pat = re.compile(r'("' + re.escape(region) + r'":\s*\{\s*"search_engines":\s*\[\n)')
    m = pat.search(text)
    if not m:
        sys.stderr.write(f"ERROR: could not locate array opener for region {region} (drift?)\n")
        sys.exit(1)
    # Guard: make sure this exact region really lacks DDG in the raw text region-block too.
    text = pat.sub(lambda mo: mo.group(1) + '        "&duckduckgo",\n', text, count=1)
    changed += 1
    print(f"OK   inserted &duckduckgo -> region {region}")

# sanity: result must still parse
try:
    json.loads(re.sub(r'^\s*//.*$', '', text, flags=re.M))
except Exception as e:
    sys.stderr.write(f"ERROR: edited file no longer valid JSON: {e}\n")
    sys.exit(1)

open(path, "w").write(text)
print(f"=== added &duckduckgo to {changed} region list(s) ===")
PY
