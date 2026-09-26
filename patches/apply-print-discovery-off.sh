#!/usr/bin/env bash
# Iris — printing OFF and local-network device discovery OFF (jegly 2026-09-26, final release; verified 2026-09-26).
# Not gn: enable_printing / enable_mdns / enable_service_discovery trip gn asserts (memory/01_GOTCHAS.md).
# PRINTING: prefs::kPrintingEnabled default true -> false (chrome/browser/profiles/profile_impl.cc; ProfileImpl is
#   used on desktop and Android). Same effect as the PrintingEnabled=false enterprise policy: no Print menu,
#   window.print() does nothing, print preview (incl. "Save as PDF") unavailable. No settings-UI toggle exists.
# DISCOVERY (mDNS/DNS-SD): on Linux the only scanner that starts on its own is Cast sink discovery
#   (chrome/browser/media/router/discovery/mdns/cast_media_sink_service.cc -> DnsSdRegistry ->
#   local_discovery::ServiceDiscoverySharedClient), which runs only when Media Router is enabled. Media Router is
#   already default-OFF (apply-degoogle-group3.sh: kEnableMediaRouter false) -> nothing to change; GUARDED here so a
#   rebase or a reverted patch can't silently turn discovery back on. Other users need explicit action: the
#   chrome.mdns extension API (Chrome Apps only) and DevTools chrome://inspect Cast devices.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/profiles/profile_impl.cc"
s = open(p).read()
old = "registry->RegisterBooleanPref(prefs::kPrintingEnabled, true);"
new = "registry->RegisterBooleanPref(prefs::kPrintingEnabled, false);  // Iris: printing off"
if new in s: print("SKIP already applied: " + p + " (printing)")
elif s.count(old) == 1: open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : printing off")
else: die(f"{p}: kPrintingEnabled registration not found exactly once (drift?)")

s = open(p).read()
if not re.search(r"prefs::kEnableMediaRouter,\s*false", s):
    die("Media Router is no longer default-off (apply-degoogle-group3.sh) -> Cast mDNS discovery would run")
print("OK   guard: Media Router default-off -> no automatic mDNS/DNS-SD discovery")
PY
echo "=== printing + local discovery off complete ==="
