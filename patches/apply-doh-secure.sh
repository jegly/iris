#!/usr/bin/env bash
# Iris — encrypted DNS (DoH) in SECURE mode by default + 15 resolvers in the picker (verified 2026-09-26).
# Adopted from Cromite ("Enable DOH secure mode by default"); our own code.
#
# 1) chrome/browser/net/default_dns_over_https_config_source.cc
#    - default mode kAutomatic -> kSecure (ctor SetDefaultPrefValue), registered default "" -> "secure"
#    - default template "" -> Quad9 "https://dns.quad9.net/dns-query"  (secure mode needs a template)
#    CAVEAT: secure mode never falls back to plaintext DNS -> captive portals (hotel/airport wifi) can't be
#    resolved until the user switches DoH off/to automatic in settings temporarily.
# 2) net/dns/public/doh_provider_entry.cc — picker (settings -> Privacy and security -> Use secure DNS):
#    upstream shows only 5 providers globally, and Quad9's entry is OFF in code (Google enables it via field
#    trial "Enabled_20260203"; Iris has no field trials). Iris list (all display_globally):
#      Quad9 (default) · Quad9 unfiltered · Cloudflare · Cloudflare malware · Cloudflare family ·
#      CleanBrowsing security/family/adult · DNS4EU Protective · CZ.NIC ODVR · DNS.SB · NextDNS ·
#      OpenDNS · OpenDNS FamilyShield · IIJ   (= 15)  + the built-in "Custom" field.
#    Google DNS hidden (de-Googled). Quad9 ECS variant (Quad9Cdn) left hidden (sends client subnet).
#    Mullvad not offered (jegly: Mullvad has stopped its DNS service).
#    DohProviderEntry DCHECKs honoured: displayed entries need ui_name + privacy_policy; global entries must
#    have empty display_countries. Privacy URLs reused from each provider's existing entry (not invented).
# Guarded; idempotent (re-run = no change); fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: "+m+"\n"); sys.exit(1)

# ---------- 1) secure-mode default ----------
p = "chrome/browser/net/default_dns_over_https_config_source.cc"
s = o = open(p).read()
s = s.replace("base::Value(SecureDnsConfig::ModeToString(\n                                         net::SecureDnsMode::kAutomatic)));",
              "base::Value(SecureDnsConfig::ModeToString(\n                                         net::SecureDnsMode::kSecure)));  // Iris")
s = s.replace('registry->RegisterStringPref(prefs::kDnsOverHttpsMode, std::string());',
              'registry->RegisterStringPref(prefs::kDnsOverHttpsMode, "secure");  // Iris')
s = s.replace('registry->RegisterStringPref(prefs::kDnsOverHttpsTemplates, std::string());',
              'registry->RegisterStringPref(prefs::kDnsOverHttpsTemplates,\n                               "https://dns.quad9.net/dns-query");  // Iris: Quad9')
for need in ["net::SecureDnsMode::kSecure)));  // Iris", 'kDnsOverHttpsMode, "secure");  // Iris', '"https://dns.quad9.net/dns-query");  // Iris: Quad9']:
    if need not in s: die(f"{p}: expected change missing (drift?): {need}")
if s != o: open(p,"w").write(s); print("OK   "+p+" : secure mode + Quad9 default")
else: print("SKIP already applied: "+p)

# ---------- 2) provider picker ----------
p = "net/dns/public/doh_provider_entry.cc"
s = o = open(p).read()
CF = "https://developers.cloudflare.com/1.1.1.1/privacy/public-dns-resolver/"
QUAD9 = "https://www.quad9.net/home/privacy/"
CB = "https://cleanbrowsing.org/privacy"
ODNS = "https://www.cisco.com/c/en/us/about/legal/privacy-full.html"
# name: (enable_feature, ui_name_if_empty, policy_if_empty, display_globally)
plan = {
  "Quad9Secure":        (True,  None, None, True),
  "Quad9Insecure":      (False, "Quad9 (unfiltered, 9.9.9.10)", QUAD9, True),
  "CloudflareSecurity": (True,  "Cloudflare (malware blocking, 1.1.1.2)", CF, True),
  "CloudflareFamily":   (True,  "Cloudflare (family, 1.1.1.3)", CF, True),
  "CleanBrowsingSecure":(False, "CleanBrowsing (Security Filter)", CB, True),
  "CleanBrowsingAdult": (False, "CleanBrowsing (Adult Filter)", CB, True),
  "OpenDNSFamily":      (False, "OpenDNS (FamilyShield)", ODNS, True),
  "Dns4eu":             (False, None, None, True),
  "Cznic":              (False, None, None, True),
  "Iij":                (False, None, None, True),
  "Dnssb":              (False, None, None, True),
  "NextDns":            (False, None, None, True),
  "Google":             (False, None, None, False),   # hide
}
for name,(enable,ui,pol,glob) in plan.items():
    i = s.find(f"kDohProvider{name},")
    if i < 0: die(f"provider {name} not found (drift?)")
    j = s.find("/*display_countries=*/", i)
    k = s.find("}", j) + 1          # end of the countries brace
    blk = s[i:k]
    if enable:
        blk = blk.replace("base::FEATURE_DISABLED_BY_DEFAULT", "base::FEATURE_ENABLED_BY_DEFAULT", 1)
    if ui is not None:
        blk = blk.replace('/*ui_name=*/""', f'/*ui_name=*/"{ui}"', 1)
        blk = blk.replace('/*privacy_policy=*/""', f'/*privacy_policy=*/"{pol}"', 1)
    blk = re.sub(r"/\*display_globally=\*/(true|false)", f"/*display_globally=*/{'true' if glob else 'false'}", blk, count=1)
    if glob:
        blk = re.sub(r"/\*display_countries=\*/\{[^}]*\}", "/*display_countries=*/{}", blk, count=1)
    # validate the DCHECK contract for displayed entries
    if glob:
        if re.search(r'/\*ui_name=\*/""', blk) or re.search(r'/\*privacy_policy=\*/""', blk):
            die(f"{name}: displayed entry would have empty ui_name/privacy_policy (DCHECK)")
        if "/*display_countries=*/{}" not in blk: die(f"{name}: global entry still has countries (DCHECK)")
    s = s[:i] + blk + s[k:]
if s != o: open(p,"w").write(s); print("OK   "+p+" : 15-provider picker, Quad9 on, Google hidden")
else: print("SKIP already applied: "+p)
PY
echo "=== DoH secure mode complete ==="
