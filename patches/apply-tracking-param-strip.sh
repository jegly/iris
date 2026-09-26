#!/usr/bin/env bash
# Iris — strip click/campaign tracking parameters from navigation URLs (Phase B3; verified against checkout 2026-09-26).
# New code lives in patches/src/ (GPL-2.0-or-later) and is copied into the tree:
#   chrome/browser/ssl/iris_tracking_param_interceptor.{h,cc}
# MECHANISM: a content::URLLoaderRequestInterceptor, registered in
#   ChromeContentBrowserClient::WillCreateURLLoaderRequestInterceptors ahead of HttpsUpgradesInterceptor. For GET
#   navigations to http(s) URLs carrying utm_* or a known click ID (fbclid, gclid, msclkid, ...), it answers with an
#   internal 307 to the cleaned URL (same technique as HttpsUpgradesInterceptor::RedirectHandler), so the parameters
#   never reach the network. Interceptors are consulted again on every redirect -> parameters added by a server
#   redirect are stripped too. The cleaned URL has no tracking parameters, so it cannot loop.
# Build: files are added to //chrome/browser/ssl (header in :ssl `public`, source in :impl), which already has the
#   deps the HTTPS-Upgrades interceptor uses.
# NOT yet: per-site exception, "Copy link" cleaning, a settings switch (Phase B follow-ups).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in iris_tracking_param_interceptor.h iris_tracking_param_interceptor.cc; do
  from="$DIR/src/chrome/browser/ssl/$f"; to="chrome/browser/ssl/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(path, old, new, marker):
    s = open(path).read()
    if marker in s: print("SKIP already applied: " + path + " (" + marker[:40] + ")"); return
    if s.count(old) != 1: die(f"{path}: expected 1 match, found {s.count(old)} (drift?): {old[:70]!r}")
    open(path, "w").write(s.replace(old, new, 1)); print("OK   " + path)

B = "chrome/browser/ssl/BUILD.gn"
edit(B, '    "https_upgrades_interceptor.h",\n',
        '    "https_upgrades_interceptor.h",\n    "iris_tracking_param_interceptor.h",\n',
        '"iris_tracking_param_interceptor.h"')
edit(B, '    "https_upgrades_interceptor.cc",\n',
        '    "https_upgrades_interceptor.cc",\n    "iris_tracking_param_interceptor.cc",\n',
        '"iris_tracking_param_interceptor.cc"')

C = "chrome/browser/chrome_content_browser_client.cc"
edit(C, '#include "chrome/browser/ssl/https_upgrades_interceptor.h"\n',
        '#include "chrome/browser/ssl/https_upgrades_interceptor.h"\n'
        '#include "chrome/browser/ssl/iris_tracking_param_interceptor.h"\n',
        '#include "chrome/browser/ssl/iris_tracking_param_interceptor.h"')
edit(C, "  interceptors.push_back(std::make_unique<SearchPrefetchURLLoaderInterceptor>(\n"
        "      frame_tree_node_id, navigation_id, navigation_response_task_runner));\n",
        "  interceptors.push_back(std::make_unique<SearchPrefetchURLLoaderInterceptor>(\n"
        "      frame_tree_node_id, navigation_id, navigation_response_task_runner));\n\n"
        "  // Iris: strip click/campaign tracking parameters before anything else\n"
        "  // (including the HTTPS upgrade) sees the URL.\n"
        "  interceptors.push_back(std::make_unique<IrisTrackingParamInterceptor>());\n",
        "std::make_unique<IrisTrackingParamInterceptor>()")
PY
echo "=== tracking-parameter stripping complete ==="
