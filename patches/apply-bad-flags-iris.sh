#!/usr/bin/env bash
# Iris — no "unsupported command-line flag: --disable-blink-features=..." bar (jegly 2026-09-27, first run WITH the
# real sandbox; verified against this checkout).
# Iris compiles its hardening list into --disable-blink-features (apply-default-switches.sh), which Chromium's
# bad-flags prompt (chrome/browser/ui/startup/bad_flags_prompt.cc kBadFlags) warns about on every start. Only the
# first bad flag is shown, so --no-sandbox hid it during dev runs.
# Removed from the list: --disable-blink-features only (turning web features OFF is Iris's own hardening; a user
# adding more only removes more). --enable-blink-features stays: turning features ON is the risky direction.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/browser/ui/startup/bad_flags_prompt.cc"
s = open(p).read()
old = "    switches::kDisableBlinkFeatures,\n    switches::kEnableBlinkFeatures,\n"
new = ("    // Iris: --disable-blink-features is Iris's compiled-in hardening list\n"
       "    // (turning features off), not a risk; enabling features still warns.\n"
       "    switches::kEnableBlinkFeatures,\n")
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write("ERROR: %s: Blink feature flags entry changed (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : no warning for Iris's --disable-blink-features")
PY
echo "=== bad-flags prompt complete ==="
