#!/usr/bin/env bash
# Iris — drop the search engines whose sites cannot do TLS 1.3: 32 -> 28 (jegly 2026-10-08: "ensure all the search
# engines can do TLS 1.3"; Iris is TLS 1.3 only, so these show ERR_SSL_VERSION_OR_CIPHER_MISMATCH). Checked 2026-10-08
# with `openssl s_client -tls1_3` on every engine's search host (all other 28 negotiated TLS 1.3):
#   Nona (www.nona.de) - alert protocol_version; Baidu (www.baidu.com, baidu.com, m.baidu.com) - alert protocol_version;
#   360 Search (www.so.com, so.com) - handshake_failure; Cốc Cốc (coccoc.com, www.) - alert protocol_version.
# (Mail.ru went earlier in apply-search-no-mailru.sh.) Removes the four entries from kIrisWorldEngines and bumps
# kCurrentDataVersion so existing profiles re-merge the list. Needs apply-search-no-mailru.sh first.
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
names = ["baidu", "so_360", "nona", "coccoc"]
lines = ["    &::TemplateURLPrepopulateData::%s,\n" % n for n in names]
if not any(l in s for l in lines):
    print("SKIP already applied: %s" % p); sys.exit(0)
for l in lines:
    if s.count(l) != 1: die("%s: %s not found exactly once (drift?)" % (p, l.strip()))
    s = s.replace(l, "", 1)
if "32 engines, distinct" not in s: die("%s: engine-count comment not found (drift?)" % p)
s = s.replace("32 engines, distinct", "28 engines, distinct", 1)
j = "third_party/search_engines_data/resources/definitions/prepopulated_engines.json"
t = open(j).read()
m = re.search(r'"kCurrentDataVersion": (\d+)', t)
if not m: die("%s: kCurrentDataVersion not found (drift?)" % j)
t = t[:m.start()] + '"kCurrentDataVersion": %d' % (int(m.group(1)) + 1) + t[m.end():]
open(p, "w").write(s); open(j, "w").write(t)
print("OK   %s : removed %s; data version %s -> %d" % (p, ", ".join(names), m.group(1), int(m.group(1)) + 1))
PY
echo "=== no TLS-1.2-only search engines complete ==="
