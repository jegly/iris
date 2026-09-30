#!/usr/bin/env bash
# Iris — Cast / Media Router actually off (found by jegly 2026-09-27: "Cast…" still in the app menu; verified against
# this checkout).
# apply-degoogle-group3.sh set the kEnableMediaRouter PREF default to false, but media_router::MediaRouterEnabled()
# (chrome/browser/media/router/media_router_feature.cc) reads that pref ONLY when it is policy-managed and otherwise
# returns true -> the pref default was a silent no-op: Cast UI stayed, and the Cast sink service (mDNS/DNS-SD
# discovery on the local network) could run. The real switch is base::Feature kMediaRouter, checked first on desktop.
# Disabled = the same state as the upstream "EnableMediaRouter=false" enterprise policy (supported configuration):
# no Cast menu item / toolbar icon, no MediaRouter service, no local-network discovery. Tab mirroring gone too.
# Android: kMediaRouter is not compiled there (Cast needs Google Play Services, absent in Iris's target).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/media/router/media_router_feature.cc"
s = open(p).read()
old = "BASE_FEATURE(kMediaRouter, base::FEATURE_ENABLED_BY_DEFAULT);"
new = "BASE_FEATURE(kMediaRouter, base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no Cast / Media Router"
if new in s: print("SKIP already applied: " + p)
elif s.count(old) == 1: open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : Media Router (Cast) off")
else: die(f"{p}: kMediaRouter definition not found exactly once (drift?)")
s = open(p).read()
# guard: the feature is still the first gate in MediaRouterEnabled()
i = s.find("bool MediaRouterEnabled(content::BrowserContext* context) {")
if i < 0 or "if (!base::FeatureList::IsEnabled(kMediaRouter)) {" not in s[i:i + 400]:
    die("MediaRouterEnabled() no longer checks kMediaRouter first")
print("OK   guard: MediaRouterEnabled() gated on kMediaRouter")
PY
echo "=== Media Router (Cast) off complete ==="
