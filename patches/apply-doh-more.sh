#!/usr/bin/env bash
# Iris — more encrypted-DNS providers in Settings -> Privacy and security -> Use secure DNS (jegly 2026-10-08).
# Each one verified live on 2026-10-08 before adding: a real lookup over DoH (curl --doh-url), TLS 1.3 on the resolver
# (openssl s_client -tls1_3), the privacy page exists, and for the filtering variants that a known ad domain
# (doubleclick.net) is blocked (filtered) / resolved (unfiltered):
#   AdGuard DNS (blocks ads and trackers)  https://dns.adguard-dns.com/dns-query        https://adguard-dns.io/en/privacy.html
#   AdGuard DNS (unfiltered)               https://unfiltered.adguard-dns.com/dns-query
#   Control D (unfiltered)                 https://freedns.controld.com/p0             https://controld.com/privacy
#   Control D (blocks ads and trackers)    https://freedns.controld.com/p2
#   Applied Privacy                        https://doh.applied-privacy.net/query       https://applied-privacy.net/services/dns/
#   Digitale Gesellschaft                  https://dns.digitale-gesellschaft.ch/dns-query  https://www.digitale-gesellschaft.ch/dns/
#   Wikimedia DNS                          https://wikimedia-dns.org/dns-query         https://meta.wikimedia.org/wiki/Wikimedia_DNS
# Picker-only entries like upstream's IIJ entry: no auto-upgrade IP list / DoT name (nothing unverified added), POST
# templates (RFC 8484), shown in every country (DohProviderEntry DCHECKs: ui name + privacy policy set, no countries).
# DNS.SB is hidden in apply-doh-secure.sh (jegly 2026-10-08). Needs apply-doh-secure.sh first.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (net doh_provider_entry.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "net/dns/public/doh_provider_entry.cc"
s = open(p).read()
MARK = "// Iris: more providers (apply-doh-more.sh)"
if MARK in s: print("SKIP already applied: " + p); sys.exit(0)
anchor = ('           /*ui_name=*/"IIJ (Public DNS)",\n'
          '           /*privacy_policy=*/"https://policy.public.dns.iij.jp/",\n'
          '           /*display_globally=*/true,\n'
          '           /*display_countries=*/{},\n'
          '       },\n')
if s.count(anchor) != 1:
    sys.stderr.write("ERROR: %s: IIJ entry not found (drift? run apply-doh-secure.sh first)\n" % p); sys.exit(1)
P = [("IrisAdGuard", "https://dns.adguard-dns.com/dns-query", "AdGuard DNS (blocks ads and trackers)",
      "https://adguard-dns.io/en/privacy.html"),
     ("IrisAdGuardUnfiltered", "https://unfiltered.adguard-dns.com/dns-query", "AdGuard DNS (unfiltered)",
      "https://adguard-dns.io/en/privacy.html"),
     ("IrisControlD", "https://freedns.controld.com/p0", "Control D (unfiltered)", "https://controld.com/privacy"),
     ("IrisControlDAds", "https://freedns.controld.com/p2", "Control D (blocks ads and trackers)",
      "https://controld.com/privacy"),
     ("IrisAppliedPrivacy", "https://doh.applied-privacy.net/query", "Applied Privacy",
      "https://applied-privacy.net/services/dns/"),
     ("IrisDigitaleGesellschaft", "https://dns.digitale-gesellschaft.ch/dns-query", "Digitale Gesellschaft",
      "https://www.digitale-gesellschaft.ch/dns/"),
     ("IrisWikimedia", "https://wikimedia-dns.org/dns-query", "Wikimedia DNS",
      "https://meta.wikimedia.org/wiki/Wikimedia_DNS")]
for name, *_ in P:
    if '"%s"' % name in s: sys.stderr.write("ERROR: provider id %s already exists\n" % name); sys.exit(1)
add = "       " + MARK + "\n"
for name, tmpl, ui, pol in P:
    add += ('       {\n'
            '           "%s",\n'
            '           MAKE_STATIC_STORAGE_BASE_FEATURE(kDohProvider%s,\n'
            '                                            base::FEATURE_ENABLED_BY_DEFAULT),\n'
            '           /*dns_over_53_server_ip_strs=*/{},\n'
            '           /*dns_over_tls_hostnames=*/{},\n'
            '           "%s",\n'
            '           /*ui_name=*/"%s",\n'
            '           /*privacy_policy=*/"%s",\n'
            '           /*display_globally=*/true,\n'
            '           /*display_countries=*/{},\n'
            '       },\n') % (name, name, tmpl, ui, pol)
open(p, "w").write(s.replace(anchor, anchor + add, 1))
print("OK   %s : %d providers added" % (p, len(P)))
PY
echo "=== more DoH providers complete ==="
