#!/usr/bin/env bash
# Iris — unpinned downloads button leaves the toolbar 10 s after a download finishes (upstream: 60 minutes)
# (jegly 2026-09-30: "Downloads" off in Customize toolbar only means "not pinned"; the button still stayed an hour).
# In-progress / needs-attention downloads (dangerous-file warnings) still show the button; pinned = always shown.
# chrome/browser/download/bubble/download_display_controller.cc kToolbarIconVisibilityTimeInterval (one object).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/browser/download/bubble/download_display_controller.cc"
s = open(p).read()
old = "constexpr base::TimeDelta kToolbarIconVisibilityTimeInterval =\n    base::Minutes(60);\n"
new = "constexpr base::TimeDelta kToolbarIconVisibilityTimeInterval =\n    base::Seconds(10);  // Iris: upstream 60 minutes\n"
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write("ERROR: %s: kToolbarIconVisibilityTimeInterval not found (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   %s : downloads icon hides 10 s after completion" % p)
PY
