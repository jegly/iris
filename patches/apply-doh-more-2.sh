#!/usr/bin/env bash
# Iris — 24 more encrypted-DNS providers in the Secure DNS picker (jegly 2026-10-18: "at least 15 more", from
# DNSCrypt's public-resolvers list; existing ones kept). Same pattern as apply-doh-more.sh: picker-only entries (no
# auto-upgrade IP list / DoT name), POST templates (RFC 8484, no {?dns}), shown in every country, Iris* ids.
# Source: github.com/DNSCrypt/dnscrypt-resolvers v3/public-resolvers.md, DoH stamps flagged no-log, deduped; kept only
# resolvers run by an identifiable operator with a privacy/info page. Not added: ~120 single dnscry.pt city nodes,
# bare-IP duplicates of existing providers, DNS.SB (hidden, jegly 2026-10-08), Mullvad (stopped), Google.
# Each one verified live on 2026-10-18 before adding:
#   - a real lookup of example.com over DoH POST + HTTP/2 (what Chromium sends): HTTP 200, application/dns-message,
#     NOERROR with an A record;
#   - TLS 1.3 with TLS_AES_256_GCM_SHA384 (openssl s_client -tls1_3 -ciphersuites ...): Iris has TLS 1.2 off and
#     strict post-quantum mode allows AES-256 only;
#   - filtering matches the label: doubleclick.net blocked by the ad-blocking ones (DNS4EU noads, DNSforge ads,
#     LibreDNS noads, AdGuard family), resolved by the unfiltered ones; pornhub.com sent to a block page by
#     DNS4EU child + AdGuard family (unfiltered DNS4EU returns the real address);
#   - the privacy/info page loads (HTTP 200).
# Dropped after testing: CIRCL (no connection), Njalla (TLS 1.3 check failed), Quad101/TWNIC (unreachable).
# Needs apply-doh-more.sh first (anchor = its Wikimedia entry).
# STATUS 2026-10-18: copy-tested only, NOT compile-proven (net doh_provider_entry.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "net/dns/public/doh_provider_entry.cc"
s = open(p).read()
MARK = "// Iris: more providers 2 (apply-doh-more-2.sh)"
if MARK in s: print("SKIP already applied: " + p); sys.exit(0)
anchor = ('           "https://wikimedia-dns.org/dns-query",\n'
          '           /*ui_name=*/"Wikimedia DNS",\n'
          '           /*privacy_policy=*/"https://meta.wikimedia.org/wiki/Wikimedia_DNS",\n'
          '           /*display_globally=*/true,\n'
          '           /*display_countries=*/{},\n'
          '       },\n')
if s.count(anchor) != 1:
    sys.stderr.write("ERROR: %s: Wikimedia entry not found (drift? run apply-doh-more.sh first)\n" % p); sys.exit(1)
P = [
    # operators: organisations, non-profits, ISPs
    ("IrisSwitch", "https://dns.switch.ch/dns-query", "SWITCH (Switzerland, blocks malware)",
     "https://www.switch.ch/en/data-protection"),
    ("IrisDns4euUnfiltered", "https://unfiltered.joindns4.eu/dns-query", "DNS4EU (unfiltered)",
     "https://www.joindns4.eu/privacy-policy"),
    ("IrisDns4euNoAds", "https://noads.joindns4.eu/dns-query", "DNS4EU (blocks ads)",
     "https://www.joindns4.eu/privacy-policy"),
    ("IrisDns4euChild", "https://child.joindns4.eu/dns-query", "DNS4EU (child protection)",
     "https://www.joindns4.eu/privacy-policy"),
    ("IrisAdGuardFamily", "https://family.adguard-dns.com/dns-query", "AdGuard DNS (family protection)",
     "https://adguard-dns.io/en/privacy.html"),
    ("IrisControlDMalware", "https://freedns.controld.com/p1", "Control D (blocks malware)",
     "https://controld.com/privacy"),
    ("IrisCiraShield", "https://private.canadianshield.cira.ca/dns-query", "CIRA Canadian Shield (blocks malware)",
     "https://www.cira.ca/en/canadian-shield/privacy/"),
    ("IrisUncensoredDns", "https://anycast.uncensoreddns.org/dns-query", "UncensoredDNS (Denmark)",
     "https://blog.uncensoreddns.org/"),
    ("IrisRestena", "https://dnspub.restena.lu/dns-query", "RESTENA (Luxembourg)",
     "https://www.restena.lu/en/service/public-dns-resolver"),
    ("IrisFdn", "https://ns1.fdn.fr/dns-query", "FDN (France)", "https://www.fdn.fr/actions/dns/"),
    ("IrisAndrewsArnold", "https://dns.aa.net.uk/dns-query", "Andrews & Arnold (UK)", "https://www.aa.net.uk/dns/"),
    ("IrisArtikel10", "https://dns.artikel10.org/dns-query", "Artikel10 (Germany)",
     "https://artikel10.org/datenschutz/"),
    ("IrisFreifunkMunich", "https://doh.ffmuc.net/dns-query", "Freifunk München (Germany)",
     "https://ffmuc.net/wiki/doku.php?id=knb:dohdot"),
    ("IrisDns4All", "https://doh.dns4all.eu/dns-query", "DNS4All by SIDN Labs", "https://dns4all.eu/"),
    ("IrisDnsforge", "https://blank.dnsforge.de/dns-query", "DNSforge (unfiltered)", "https://dnsforge.de/"),
    ("IrisDnsforgeAds", "https://dnsforge.de/dns-query", "DNSforge (blocks ads)", "https://dnsforge.de/"),
    ("IrisRethinkDns", "https://sky.rethinkdns.com/dns-query", "RethinkDNS (unfiltered)",
     "https://rethinkdns.com/privacy"),
    ("IrisHurricaneElectric", "https://ordns.he.net/dns-query", "Hurricane Electric", "https://he.net/privacy.html"),
    ("IrisDnsHome", "https://dns.dnshome.de/dns-query", "dnsHome.de (Germany)",
     "https://www.dnshome.de/datenschutz.php"),
    # smaller / single-operator resolvers (pass every check)
    ("IrisLibreDns", "https://doh.libredns.gr/dns-query", "LibreDNS (unfiltered)", "https://libredns.gr/"),
    ("IrisLibreDnsAds", "https://doh.libredns.gr/noads", "LibreDNS (blocks ads)", "https://libredns.gr/"),
    ("IrisDnscryptCa", "https://dns1.dnscrypt.ca/dns-query", "dnscrypt.ca (Canada)", "https://dnscrypt.ca/"),
    ("IrisDremaxx", "https://open.dns.dremaxx.com/dns-query", "Dremaxx (unfiltered)",
     "https://dremaxx.de/en/dns-resolvers"),
    ("IrisBortzmeyer", "https://doh.bortzmeyer.fr/", "Stéphane Bortzmeyer (France)",
     "https://www.bortzmeyer.org/doh-bortzmeyer-fr-policy.html"),
]
seen_t = set()
for name, tmpl, ui, pol in P:
    if '"%s"' % name in s: sys.stderr.write("ERROR: provider id %s already exists\n" % name); sys.exit(1)
    if '"%s"' % tmpl in s: sys.stderr.write("ERROR: template %s already in the list\n" % tmpl); sys.exit(1)
    if tmpl in seen_t: sys.stderr.write("ERROR: duplicate template %s\n" % tmpl); sys.exit(1)
    seen_t.add(tmpl)
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
echo "=== more DoH providers (2) complete ==="
