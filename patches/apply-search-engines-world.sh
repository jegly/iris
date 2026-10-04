#!/usr/bin/env bash
# Iris — one worldwide list of 33 search engines in every country (jegly 2026-10-04: "30+ different search engines,
# from all around the world, truly multilingual"; verified against the 156.0.8073.0 and 156.0.8078.9 sources and
# search_engines_data effde84e / 5dc9f1af).
# Before: Settings -> Search engine offered Chromium's per-country list: the top 5 for most countries
# (kTopSearchEnginesThreshold) or a shuffled EEA list (regional_capabilities::GetPrepopulatedEngines in
# components/regional_capabilities/regional_capabilities_utils.cc), + DuckDuckGo via apply-search-list-ddg.sh.
# After: the same 33 engines everywhere, privacy-first, then global, then regional (names in their own scripts):
#   DuckDuckGo, Startpage, Brave, Mojeek, Qwant, Ecosia, Swisscows*, Marginalia*, Mwmbl*, Kagi, Yep, Lilo,
#   PrivacyWall, OceanHero, WWF Panda, Karma, Nona, Quendu, Freespoke, Info.com, Google, Microsoft Bing, Yahoo!,
#   Yahoo! JAPAN, Yandex, 百度 Baidu, 搜狗 Sogou, 360, 네이버 Naver, Daum, Seznam.cz, Cốc Cốc, Mail.ru.
#   (* = added here; search URLs checked 2026-10-04: swisscows.com/en/web?query=, marginalia-search.com/search?query=,
#   mwmbl.org/search?q=. Left out: Perplexity + You.com (AI search; Iris has no AI), MetaGer (landing page), Presearch
#   (account needed). Yahoo/Yandex country variants share one engine id, so one of each.)
#   The default stays DuckDuckGo (apply-default-search.sh). Desktop + Android (both read this function).
# How:
#  - prepopulated_engines.json (third_party/search_engines_data/resources/definitions): 3 new engines, ids 210-212
#    (Iris range, clear of upstream's 1..117), kMaxPrepopulatedEngineID raised to 212, kCurrentDataVersion + 1 so
#    existing profiles merge the new list on first start (TemplateURLService merges when the data version rises).
#  - regional_capabilities_utils.cc: after Chromium builds its regional list (kept, so its helpers stay used: no
#    -Wunused-function), GetPrepopulatedEngines() returns kIrisWorldEngines instead.
# Needs apply-search-list-ddg.sh / apply-default-search.sh? No (independent files/anchors); runs after them.
# STATUS 2026-10-04: copy-tested only, NOT compile-proven (json_to_struct generation, regional_capabilities_utils.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import json, re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)

# --- 1. engine definitions ---------------------------------------------------------------------------------------
p = "third_party/search_engines_data/resources/definitions/prepopulated_engines.json"
s = open(p).read()
MARK = "// Iris: extra engines (apply-search-engines-world.sh)"
if MARK in s:
    print("SKIP already applied: %s" % p)
else:
    data = json.loads(re.sub(r"^\s*//.*$", "", s, flags=re.M))
    used = {v["id"] for v in data["elements"].values()}
    for i in (210, 211, 212):
        if i in used: die("%s: engine id %d is now used upstream - pick new Iris ids" % (p, i))
    for k in ("swisscows", "marginalia", "mwmbl"):
        if k in data["elements"]: die("%s: upstream now defines '%s' - drop it from this patch" % (p, k))
    anchor = '    "mojeek": {\n'
    if s.count(anchor) != 1: die("%s: mojeek entry (insert anchor) not found exactly once (drift?)" % p)
    NEW = (MARK + "\n"
           '    "swisscows": {\n'
           '      "name": "Swisscows",\n'
           '      "keyword": "swisscows.com",\n'
           '      "favicon_url": "https://swisscows.com/favicon.ico",\n'
           '      "search_url": "https://swisscows.com/en/web?query={searchTerms}",\n'
           '      "type": "SEARCH_ENGINE_OTHER",\n'
           '      "id": 210\n'
           '    },\n\n'
           '    "marginalia": {\n'
           '      "name": "Marginalia",\n'
           '      "keyword": "marginalia-search.com",\n'
           '      "favicon_url": "https://marginalia-search.com/favicon.ico",\n'
           '      "search_url": "https://marginalia-search.com/search?query={searchTerms}",\n'
           '      "type": "SEARCH_ENGINE_OTHER",\n'
           '      "id": 211\n'
           '    },\n\n'
           '    "mwmbl": {\n'
           '      "name": "Mwmbl",\n'
           '      "keyword": "mwmbl.org",\n'
           '      "favicon_url": "https://mwmbl.org/favicon.ico",\n'
           '      "search_url": "https://mwmbl.org/search?q={searchTerms}",\n'
           '      "type": "SEARCH_ENGINE_OTHER",\n'
           '      "id": 212\n'
           '    },\n\n')
    s = s.replace(anchor, NEW + anchor, 1)
    m = re.search(r'"kMaxPrepopulatedEngineID": (\d+)', s)
    if not m: die("%s: kMaxPrepopulatedEngineID not found (drift?)" % p)
    if int(m.group(1)) < 212:
        s = s[:m.start()] + '"kMaxPrepopulatedEngineID": 212' + s[m.end():]
    m = re.search(r'"kCurrentDataVersion": (\d+)', s)
    if not m: die("%s: kCurrentDataVersion not found (drift?)" % p)
    s = s[:m.start()] + '"kCurrentDataVersion": %d' % (int(m.group(1)) + 1) + s[m.end():]
    json.loads(re.sub(r"^\s*//.*$", "", s, flags=re.M))  # still valid JSON (comments stripped)
    open(p, "w").write(s)
    print("OK   %s : +Swisscows/Marginalia/Mwmbl (ids 210-212), data version %s -> %d"
          % (p, m.group(1), int(m.group(1)) + 1))

# --- 2. one worldwide list -----------------------------------------------------------------------------------------
p = "components/regional_capabilities/regional_capabilities_utils.cc"
s = open(p).read()
MARK2 = "kIrisWorldEngines"
if MARK2 in s:
    print("SKIP already applied: %s" % p)
else:
    a1 = "using ::TemplateURLPrepopulateData::RegionalSettings;\n"
    a2 = ('  CHECK(!engines.empty()) << "Unexpected PrepopulatedEngines to be empty. "\n'
          '                             "SearchEngineListType might be invalid: "\n'
          '                          << static_cast<int>(search_engine_list_type);\n'
          '\n'
          '  return engines;\n'
          '}\n')
    for a, what in ((a1, "RegionalSettings using-declaration"), (a2, "end of GetPrepopulatedEngines()")):
        if s.count(a) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
    names = ["duckduckgo", "startpage", "brave", "mojeek", "qwant", "ecosia", "swisscows", "marginalia", "mwmbl",
             "kagi", "yep", "lilo", "privacywall", "oceanhero", "panda", "karma", "nona", "quendu", "freespoke",
             "info_com", "google", "bing", "yahoo", "yahoo_jp_next", "yandex_com", "baidu", "sogou", "so_360",
             "naver", "daum", "seznam", "coccoc", "mail_ru"]
    assert len(names) == len(set(names)) == 33
    decl = ("\n// Iris: the search engines offered in every country (apply-search-engines-world.sh): privacy-first,\n"
            "// then global, then regional. 33 engines, distinct prepopulated ids.\n"
            "const PrepopulatedEngine* const kIrisWorldEngines[] = {\n" +
            "".join("    &::TemplateURLPrepopulateData::%s,\n" % n for n in names) + "};\n")
    s = s.replace(a1, a1 + decl, 1)
    s = s.replace(a2, a2.replace("  return engines;\n",
        "  // Iris: same worldwide list everywhere (Chromium's regional list above is not used).\n"
        "  engines = base::ToVector<raw_ptr<const PrepopulatedEngine>>(\n"
        "      base::span(kIrisWorldEngines));\n"
        "  return engines;\n"), 1)
    open(p, "w").write(s)
    print("OK   %s : one worldwide list of %d engines" % (p, len(names)))
PY
echo "=== worldwide search engines complete ==="
