#!/usr/bin/env bash
# Iris — field-trial audit wins (verified against checkout 2026-09-26).
# Iris runs with NO field trials (disable_fieldtrial_testing_config + no variations fetch), so anything Google only
# turns on remotely stays at its code default. Audit: testing/variations/fieldtrial_testing_config.json -> 154
# security/privacy-keyword features enabled on linux/android -> 107 are DISABLED in code -> hand-triaged:
# ENABLE here (pure hardening/privacy, low risk):
#  - IsolateSubframeErrorPages (content)                 process isolation for subframe error pages
#  - PermissionsGestureGatedPrompts (permissions)        no-gesture notification/geolocation requests -> quiet prompt
#  - HardenUrlProvisionFetcher (media)                   provisioning fetcher: HTTPS POST only + max response size
#  - SafetyCheckUnusedSitePermissions (content_settings) + SafetyHubUnusedPermissionRevocationForAllSurfaces
#    (permissions)                                        auto-revoke permissions of sites you no longer use
# ALREADY ON in Iris via embedder code (no patch): HTTP cache split (HttpCache::SplitCacheFeatureEnableByDefault)
#   and connection/socket/TLS-session partitioning (NetworkAnonymizationKey::PartitionByDefault), both called from
#   chrome/app/chrome_main_delegate.cc.
# NOT taken: AddTLSServerHandshakePadding (trial uses 0 bytes = no effect), ChildProcessSecurityPolicyRust
#   (experimental rewrite of a site-isolation-critical component — revisit when mature), Google AI / Glic /
#   surveys / Safe-Browsing-dependent / perf-only features. HTTPS-First vs HTTPS-Only = separate decision.
# Guarded; idempotent; fails loudly on drift. Works for single-line and multi-line BASE_FEATURE declarations.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: "+m+"\n"); sys.exit(1)
def enable(path, ident):
    s = open(path).read()
    on  = re.compile(r'BASE_FEATURE\(\s*' + ident + r'\s*,\s*(?:"[^"]*"\s*,\s*)?base::FEATURE_ENABLED_BY_DEFAULT')
    off = re.compile(r'(BASE_FEATURE\(\s*' + ident + r'\s*,\s*(?:"[^"]*"\s*,\s*)?)base::FEATURE_DISABLED_BY_DEFAULT')
    if on.search(s): print(f"SKIP already enabled: {ident}"); return
    if len(off.findall(s)) != 1: die(f"{path}: {ident} DISABLED declaration found {len(off.findall(s))}x (drift?)")
    open(path, "w").write(off.sub(r'\1base::FEATURE_ENABLED_BY_DEFAULT', s, count=1)); print(f"OK   {ident} -> ENABLED ({path})")
enable("content/public/common/content_features.cc", "kIsolateSubframeErrorPages")
enable("components/permissions/features.cc", "kPermissionsGestureGatedPrompts")
enable("components/permissions/features.cc", "kSafetyHubUnusedPermissionRevocationForAllSurfaces")
enable("media/base/media_switches.cc", "kHardenUrlProvisionFetcher")
# kSafetyCheckUnusedSitePermissions is platform-conditional: already ENABLED on desktop, DISABLED on Android ->
# flip only the Android branch.
p = "components/content_settings/core/common/features.cc"; s = open(p).read()
a_old = "BASE_FEATURE(kSafetyCheckUnusedSitePermissions,\n#if BUILDFLAG(IS_ANDROID)\n             base::FEATURE_DISABLED_BY_DEFAULT);"
a_new = "BASE_FEATURE(kSafetyCheckUnusedSitePermissions,\n#if BUILDFLAG(IS_ANDROID)\n             base::FEATURE_ENABLED_BY_DEFAULT);  // Iris"
if a_new in s: print("SKIP already enabled: kSafetyCheckUnusedSitePermissions (Android)")
elif s.count(a_old) == 1: open(p,"w").write(s.replace(a_old, a_new)); print("OK   kSafetyCheckUnusedSitePermissions (Android branch) -> ENABLED")
else: die("kSafetyCheckUnusedSitePermissions Android branch not found (drift?)")
PY
echo "=== field-trial wins complete ==="
