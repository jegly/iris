#!/usr/bin/env python3
# Iris — merge the extra block lists into ONE Adblock-Plus-syntax file for ruleset_converter.
#   usage: prepare-extra-lists.py OUT.txt LIST...      (LIST = stevenblack hosts, urlhaus hosts, hagezi/adguard ABP files)
# - hosts files ("127.0.0.1 host" / "0.0.0.0 host"): each valid host becomes "||host^"
# - ABP-syntax files: kept line by line; comments, cosmetic rules and DNS-only options are dropped here
# - domains are validated (lower-case LDH labels, at least one dot), localhost-type names skipped, duplicates removed
# Network rules only (the Chromium filter has no cosmetic rules). Output is deterministic (sorted).
import re, sys
LABEL = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")
SKIP_HOSTS = {"localhost", "localhost.localdomain", "local", "broadcasthost", "ip6-localhost", "ip6-loopback",
              "ip6-localnet", "ip6-mcastprefix", "ip6-allnodes", "ip6-allrouters", "ip6-allhosts", "0.0.0.0"}
def valid_domain(h):
    if h in SKIP_HOSTS or len(h) > 253 or "." not in h: return False
    parts = h.split(".")
    if not all(LABEL.match(x) for x in parts): return False
    if parts[-1].isdigit(): return False           # an IP address, not a name
    return True
DNS_ONLY = ("$dnstype", "$dnsrewrite", "$client", "$ctag", "$denyallow", "$badfilter")
rules, stats = set(), {}
for path in sys.argv[2:]:
    n = 0
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.strip()
        if not line or line[0] in "#![" : continue
        if "##" in line or "#@#" in line or "#?#" in line or "#$#" in line or "#%#" in line: continue
        if any(o in line for o in DNS_ONLY): continue
        m = re.match(r"^(?:0\.0\.0\.0|127\.0\.0\.1)\s+(\S+)\s*(?:#.*)?$", line)
        if m:                                       # hosts-file line
            h = m.group(1).lower()
            if valid_domain(h): rules.add("||%s^" % h); n += 1
            continue
        if re.match(r"^\d+\.\d+\.\d+\.\d+\s", line) or line.startswith("::"): continue
        if line.endswith("$important"): line = line[:-len("$important")]   # "beats exceptions"; Chromium has no such option: keep as a plain block
        if line.startswith("||") or line.startswith("@@||") or line.startswith("|"):   # ABP network rule
            rules.add(line); n += 1
    stats[path] = n
with open(sys.argv[1], "w") as f:
    f.write("[Adblock Plus 2.0]\n! Iris extra lists (merged by adblock/prepare-extra-lists.py)\n")
    for r in sorted(rules): f.write(r + "\n")
for p, n in stats.items(): sys.stderr.write("%8d rules from %s\n" % (n, p))
sys.stderr.write("%8d unique rules written to %s\n" % (len(rules), sys.argv[1]))
