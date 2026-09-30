#!/usr/bin/env bash
# Iris — extra hardening defaults (jegly 2026-09-30, verified against this checkout).
# 1) Fill on account select (password_manager::features::kFillOnAccountSelect, DISABLED upstream): a saved password is
#    NOT put into the page when it loads; it is filled only after you pick the account from the dropdown. Stops
#    invisible/login-tracking forms and injected scripts from harvesting saved credentials without a click.
# 2) Scheme-bound cookies (net::features::kEnableSchemeBoundCookies, DISABLED upstream): a cookie set over https is
#    only sent back over https (and http-set cookies stay on http). Low breakage with Iris's strict HTTPS-Only mode.
# 3) Port-bound cookies (net::features::kEnablePortBoundCookies, DISABLED upstream; jegly 2026-09-30): a cookie is only
#    sent back to the port that set it. Cost: sites sharing a login across ports (router pages, media servers on :32400,
#    local dev servers) need a separate login per port.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def feature_on(p, name):
    s = open(p).read()
    rx = re.compile(r'(BASE_FEATURE\(\s*' + name + r',(?:\s*"[^"]*",)?\s*)base::FEATURE_(ENABLED|DISABLED)_BY_DEFAULT\);')
    hits = rx.findall(s)
    if len(hits) != 1: die("%s: %s declaration found %d times (drift?)" % (p, name, len(hits)))
    m = rx.search(s)
    if m.group(2) == "ENABLED": print("SKIP already applied: %s (%s)" % (p, name)); return
    s = s[:m.start()] + m.group(1) + "base::FEATURE_ENABLED_BY_DEFAULT);  // Iris" + s[m.end():]
    open(p, "w").write(s); print("OK   %s : %s ON" % (p, name))
feature_on("components/password_manager/core/browser/features/password_features.cc", "kFillOnAccountSelect")
feature_on("net/base/features.cc", "kEnableSchemeBoundCookies")
feature_on("net/base/features.cc", "kEnablePortBoundCookies")
PY
echo "=== extra hardening complete ==="
