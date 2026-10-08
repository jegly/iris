#!/usr/bin/env bash
# Iris — drop Mail.ru from the worldwide search engine list: 33 -> 32 (jegly 2026-10-08: "go.mail.ru doesn't work,
# ERR_SSL_VERSION_OR_CIPHER_MISMATCH"; Iris is TLS 1.3 only and go.mail.ru only offers TLS 1.2). Yandex stays (its own entry).
# Removes `&::TemplateURLPrepopulateData::mail_ru,` from kIrisWorldEngines (regional_capabilities_utils.cc) and bumps
# kCurrentDataVersion so profiles that already had the 33-engine list merge the new one on first start.
# Needs apply-search-engines-world.sh first.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (regional_capabilities_utils.o, json_to_struct generation).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "components/regional_capabilities/regional_capabilities_utils.cc"
s = open(p).read()
line = "    &::TemplateURLPrepopulateData::mail_ru,\n"
if line not in s:
    print("SKIP already applied: %s" % p); sys.exit(0)
if s.count(line) != 1: die("%s: mail_ru entry not found exactly once (drift?)" % p)
s = s.replace(line, "", 1).replace("33 engines, distinct", "32 engines, distinct", 1)
j = "third_party/search_engines_data/resources/definitions/prepopulated_engines.json"
t = open(j).read()
m = re.search(r'"kCurrentDataVersion": (\d+)', t)
if not m: die("%s: kCurrentDataVersion not found (drift?)" % j)
t = t[:m.start()] + '"kCurrentDataVersion": %d' % (int(m.group(1)) + 1) + t[m.end():]
open(p, "w").write(s); open(j, "w").write(t)
print("OK   %s : mail_ru removed; data version %s -> %d" % (p, m.group(1), int(m.group(1)) + 1))
PY
echo "=== no Mail.ru complete ==="
