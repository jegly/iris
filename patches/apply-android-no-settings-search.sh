#!/usr/bin/env bash
# Iris — Android Settings: no search bar (jegly 2026-10-08: "weird glitch in settings when going in and out of
# sub-pages, it jumps"; the previous branch's build did not do it; verified against 156.0.8078.11).
# The Settings search bar is created in SettingsActivity only for the main page (single-column mode) and lives in the
# toolbar; on sub-pages it is gone, so the toolbar changes height during the slide animation and the content jumps
# ~35px. createSearchCoordinator() now returns at once: mSearchCoordinator stays null, and every other use in
# SettingsActivity is already null-checked (field is @Nullable). Cost: no search inside Settings.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/android/java/src/org/chromium/chrome/browser/settings/SettingsActivity.java"
s = open(p).read()
if "Iris: no Settings search bar" in s: print("SKIP already applied: " + p); sys.exit(0)
old = "    private void createSearchCoordinator(@Nullable Bundle savedState) {\n"
if s.count(old) != 1: sys.stderr.write("ERROR: anchor not found exactly once (drift?)\n"); sys.exit(1)
open(p, "w").write(s.replace(old, old + "        if (true) return;  // Iris: no Settings search bar (it made sub-page transitions jump)\n", 1))
print("OK   " + p)
PY
echo "=== Android Settings search removal complete ==="
