#!/usr/bin/env bash
# Iris — input protection on by default (desktop; jegly 2026-11-05: "yes add it", after seeing #enable-input-protection
# in stock Chromium 157's flags).
# Verified against 157.0.8103.38: views::features::kEnableInputProtection (ui/views/views_features.cc, DISABLED upstream,
# experimental). When on, every views::Widget gets an InputProtectionEventHandler: clicks and key presses on browser UI
# that is covered, or was just covered, by one of Chromium's own always-on-top windows (Picture-in-Picture video,
# Document PiP) are ignored - a website can't float a PiP window over a permission prompt / dialog to trick a click
# through it. Only Chromium's own windows are tracked (OccludedWidgetInputProtector), not other apps.
# The second half ("security-sensitive UI that activates unexpectedly", Widget::EnableInputEventActivationProtection)
# has no callers in 157, so it does nothing yet. Cost: while your own PiP video covers a prompt, clicks there are
# ignored until you move it. Desktop only (ui/views is not used on Android).
# STATUS 2026-11-05: copy-tested on a 157 copy; compile-proven after apply (views_features.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
edit("ui/views/views_features.cc",
     "BASE_FEATURE(kEnableInputProtection, base::FEATURE_DISABLED_BY_DEFAULT);\n",
     "// Iris (apply-input-protection.sh): on by default.\n"
     "BASE_FEATURE(kEnableInputProtection, base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "// Iris (apply-input-protection.sh)", "input protection on")
PY
echo "=== input protection complete ==="
