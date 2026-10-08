#!/usr/bin/env bash
# Iris — search list round 3 (jegly 2026-10-08): 28 -> 20 engines.
#  - Removed ("random" ones): OceanHero, Karma, WWF Panda, Lilo, Quendu, Info.com, PrivacyWall, Freespoke, Yep.
#  - Added: DuckDuckGo Lite (https://lite.duckduckgo.com/lite/?q=, works with JavaScript off - pairs with Iris's
#    JavaScript switch). Checked 2026-10-08: TLS 1.3, returns results. New Iris prepopulated id 213.
#    Asked for but NOT added (checked the same day): Stract (stract.com is now an unrelated PR company; the search
#    engine is gone) and Ghostery Private Search (redirects to a "closed beta" blog post).
# kCurrentDataVersion + 1 so existing profiles re-merge the list. Needs apply-search-engines-world.sh,
# apply-search-no-mailru.sh, apply-search-no-tls12-only.sh first.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (json_to_struct generation, regional_capabilities_utils.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import json, re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "components/regional_capabilities/regional_capabilities_utils.cc"
j = "third_party/search_engines_data/resources/definitions/prepopulated_engines.json"
s = open(p).read()
t = open(j).read()
MARK = "// Iris: DuckDuckGo Lite (apply-search-engines-trim.sh)"
if MARK in t and "TemplateURLPrepopulateData::duckduckgo_lite," in s:
    print("SKIP already applied: %s, %s" % (p, j)); sys.exit(0)
GONE = ["yep", "lilo", "privacywall", "oceanhero", "panda", "karma", "quendu", "freespoke", "info_com"]
for n in GONE:
    line = "    &::TemplateURLPrepopulateData::%s,\n" % n
    if s.count(line) != 1: die("%s: %s not in the Iris list exactly once (drift?)" % (p, n))
    s = s.replace(line, "", 1)
ddg = "    &::TemplateURLPrepopulateData::duckduckgo,\n"
if s.count(ddg) != 1: die("%s: duckduckgo entry not found (drift?)" % p)
s = s.replace(ddg, ddg + "    &::TemplateURLPrepopulateData::duckduckgo_lite,\n", 1)
if "28 engines, distinct" not in s: die("%s: engine-count comment not found (drift?)" % p)
s = s.replace("28 engines, distinct", "20 engines, distinct", 1)
# json: DuckDuckGo Lite (id 213)
data = json.loads(re.sub(r"^\s*//.*$", "", t, flags=re.M))
if 213 in {v["id"] for v in data["elements"].values()}: die("%s: engine id 213 is now used upstream" % j)
if "duckduckgo_lite" in data["elements"]: die("%s: upstream now defines duckduckgo_lite" % j)
wm = "// Iris: extra engines (apply-search-engines-world.sh)"
if t.count(wm) != 1: die("%s: world-engines marker not found (run apply-search-engines-world.sh first)" % j)
t = t.replace(wm, MARK + "\n"
              '    "duckduckgo_lite": {\n'
              '      "name": "DuckDuckGo Lite",\n'
              '      "keyword": "lite.duckduckgo.com",\n'
              '      "favicon_url": "https://duckduckgo.com/favicon.ico",\n'
              '      "search_url": "https://lite.duckduckgo.com/lite/?q={searchTerms}",\n'
              '      "type": "SEARCH_ENGINE_OTHER",\n'
              '      "id": 213\n'
              '    },\n\n' + wm, 1)
m = re.search(r'"kMaxPrepopulatedEngineID": (\d+)', t)
if not m: die("%s: kMaxPrepopulatedEngineID not found" % j)
if int(m.group(1)) < 213: t = t[:m.start()] + '"kMaxPrepopulatedEngineID": 213' + t[m.end():]
m = re.search(r'"kCurrentDataVersion": (\d+)', t)
if not m: die("%s: kCurrentDataVersion not found" % j)
t = t[:m.start()] + '"kCurrentDataVersion": %d' % (int(m.group(1)) + 1) + t[m.end():]
json.loads(re.sub(r"^\s*//.*$", "", t, flags=re.M))
open(p, "w").write(s); open(j, "w").write(t)
print("OK   %s : -9 engines, +DuckDuckGo Lite (20)\nOK   %s : duckduckgo_lite id 213, data version bumped" % (p, j))
PY
echo "=== search list round 3 complete ==="
