#!/usr/bin/env bash
# Iris — stop trusting eMudhra's two emSign roots (jegly 2026-10-21: "remove the certs").
# Why: on 2026-10-17 eight eMudhra intermediates (EM DV/OV/EV TLS CA - G3B/G3C, EM OV CS CA - G3B/G3C) were found to
# have private keys computable from their public certificates (weak key-generation ceremony, April 2025). The six TLS
# ones chain to emSign ECC Root CA - G3. Mozilla removed that root from NSS on 2026-10-20; Chrome blocked the
# intermediates by CRLSet and removes the root in Chrome Root Store v43, and is "reviewing" emSign Root CA - G1.
# Iris drops both roots now:
#   1. root_store.textproto: the two trust_anchors entries are removed (compiled-in Chrome Root Store), and their PEMs
#      from root_store.certs (root_store_tool rejects unused certificates);
#   2. cert_verify_proc_blocklist.inc: both roots' public keys (SHA-256 of the SPKI) go into kSPKIBlockList. That list is
#      merged into every CRLSet, the built-in one and each downloaded one (net/cert/crl_set.cc), so the roots stay
#      blocked even if a later root store from the PKI metadata component still lists one of them (e.g. G1).
# Cost: sites with emSign certificates (mostly Indian government/bank sites) fail with a certificate error.
# SPKI hashes computed from net/data/ssl/chrome_root_store/root_store.certs at 156.0.8078.47:
#   emSign Root CA - G1      cert 40f6af0346a99aa1... SPKI 376a1a7082a593dccc20d561d119e9ab8d30f11cc321d0a37fa41f0df284e01c
#   emSign ECC Root CA - G3  cert 86a1ecba089c4a8d... SPKI 8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782
# STATUS 2026-10-21: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys

# 1. Chrome Root Store: remove the two emSign trust anchors.
p = "net/data/ssl/chrome_root_store/root_store.textproto"
s = open(p).read()
MARK = "# Iris: emSign roots removed (apply-emudhra-distrust.sh)"
if MARK in s:
    print("SKIP already applied: " + p)
else:
    G1 = ('# CN=emSign Root CA - G1, O=eMudhra Technologies Limited, OU=emSign PKI, C=IN\n'
          '# https://testevg1.emsign.com/\n'
          'trust_anchors {\n'
          '  sha256_hex: "40f6af0346a99aa1cd1d555a4e9cce62c7f9634603ee406615833dc8c8d00367"\n'
          '  crs_root_id: 27\n'
          '  ev_policy_oids: "2.23.140.1.1"\n'
          '}\n\n')
    G3 = ('# CN=emSign ECC Root CA - G3, O=eMudhra Technologies Limited, OU=emSign PKI, C=IN\n'
          'trust_anchors {\n'
          '  sha256_hex: "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b"\n'
          '  crs_root_id: 28\n'
          '}\n\n')
    # M158 (Chrome Root Store v43, 2026-11-20): Google removed emSign ECC Root CA - G3 itself (entry + PEM gone).
    # G1 is still trusted upstream -> still required here. G3 may be present (<= 157) or already gone (>= 158).
    g3_gone = "86a1ecba089c4a8d" not in s
    for name, block in (("emSign Root CA - G1", G1), ("emSign ECC Root CA - G3", G3)):
        if name.endswith("G3") and g3_gone: continue
        if s.count(block) != 1:
            sys.stderr.write("ERROR: %s: %s entry not found (drift? Google may have removed it already: check and "
                             "update this script)\n" % (p, name)); sys.exit(1)
    s = s.replace(G1, MARK + "\n\n", 1)
    if not g3_gone: s = s.replace(G3, "", 1)
    for h in ("40f6af0346a99aa1", "86a1ecba089c4a8d"):
        if h in s: sys.stderr.write("ERROR: %s: %s still present\n" % (p, h)); sys.exit(1)
    open(p, "w").write(s)
    print("OK   %s : emSign Root CA - G1%s removed" % (p, "" if g3_gone else " and emSign ECC Root CA - G3"))

# 1b. Their PEMs too: root_store_tool fails the build on a certificate the textproto no longer uses.
import re
p = "net/data/ssl/chrome_root_store/root_store.certs"
s = open(p).read()
gone = 0
present = [h for h in ("40f6af0346a99aa1cd1d555a4e9cce62c7f9634603ee406615833dc8c8d00367",
                       "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b") if h in s]
for h in present:
    pat = re.compile(r"# " + h + r"\n.*?-----END CERTIFICATE-----\n\n?", re.S)
    n = len(pat.findall(s))
    if n > 1: sys.stderr.write("ERROR: %s: %s found %d times\n" % (p, h, n)); sys.exit(1)
    s, k = pat.subn("", s); gone += k
if gone == 0:
    print("SKIP already applied: " + p)
else:
    # 158+: only G1's PEM is left upstream (G3 removed by Google, see above); <= 157: both.
    if gone != len(present): sys.stderr.write("ERROR: %s: emSign PEM header without a PEM block (drift)\n" % p); sys.exit(1)
    if "emSign" in s: sys.stderr.write("ERROR: %s: emSign still present\n" % p); sys.exit(1)
    open(p, "w").write(s)
    print("OK   %s : %d emSign PEM(s) removed" % (p, gone))

# 2. Built-in SPKI blocklist (merged into every CRLSet).
p = "net/cert/cert_verify_proc_blocklist.inc"
s = open(p).read()
# jegly 2026-11-20: "ALL emudra certs / ca's need to be removed". Chrome's root store only ever had G1 + G3; the
# eMudhra Inc (US) roots C1 + C3 are in Mozilla's/Ubuntu's bundle and could still be trusted through the user NSS DB
# (TrustStoreNSS) or a later root store. Blocking the SPKI wins over every trust source. SPKI hashes computed
# 2026-11-20 from /usr/share/ca-certificates/mozilla (ca-certificates 20260816ubuntu0.26.04.2):
#   emSign Root CA - C1      cert 125609aa301da0a2... SPKI b7408b4d2be0238ba37004dd34e276c6019bd2f24c9db7d4980f5f6c359a4bcc
#   emSign ECC Root CA - C3  cert bc4d809b15189d78... SPKI eabc185c4e82d942b1a5978ba3c0181487d6b3b9974e5c49f72f6d0bd9637150
# (G1's SPKI computed the same way matched the 2026-10-21 value above, which checks the method.) The compromised
# intermediates chain to these roots, so they are blocked with them; upstream also lists 7 of them in blocklist/.
MARK = "// Iris: eMudhra emSign roots (apply-emudhra-distrust.sh)"
MARK2 = "        // Iris v2: + eMudhra Inc roots C1 and C3 (all eMudhra roots blocked)\n"
def row(hexs):
    b = ["0x" + hexs[i:i + 2] for i in range(0, 64, 2)]
    return ("        {" + ", ".join(b[0:11]) + ",\n         " + ", ".join(b[11:22]) + ",\n         " +
            ", ".join(b[22:32]) + "},\n")
G3ROW = "        // emSign ECC Root CA - G3\n" + row("8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782")
V2 = (MARK2 +
      "        // emSign Root CA - C1\n" + row("b7408b4d2be0238ba37004dd34e276c6019bd2f24c9db7d4980f5f6c359a4bcc") +
      "        // emSign ECC Root CA - C3\n" + row("eabc185c4e82d942b1a5978ba3c0181487d6b3b9974e5c49f72f6d0bd9637150"))
if MARK2 in s:
    print("SKIP already applied: " + p)
elif MARK in s:
    # tree has the 2-root version: add C1 + C3 right after its G3 row
    if s.count(G3ROW) != 1: sys.stderr.write("ERROR: %s: Iris G3 row not found for the v2 upgrade\n" % p); sys.exit(1)
    open(p, "w").write(s.replace(G3ROW, G3ROW + V2, 1))
    print("OK   %s : upgraded, + emSign C1 + C3 root SPKIs blocked (4 total)" % p)
else:
    anchor = "    kSPKIBlockList[][crypto::hash::kSha256Size] = {\n"
    if s.count(anchor) != 1:
        sys.stderr.write("ERROR: %s: kSPKIBlockList start not found (drift)\n" % p); sys.exit(1)
    add = ("        " + MARK + "\n"
           "        // emSign Root CA - G1\n" +
           row("376a1a7082a593dccc20d561d119e9ab8d30f11cc321d0a37fa41f0df284e01c") +
           G3ROW + V2)
    open(p, "w").write(s.replace(anchor, anchor + add, 1))
    print("OK   %s : 4 eMudhra root SPKIs blocked (G1, G3, C1, C3)" % p)
PY
echo "=== eMudhra distrust complete ==="
