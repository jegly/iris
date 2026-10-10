#!/usr/bin/env bash
# Iris — 1 ms timer resolution by default (jegly 2026-10-09, API-surface audit: Chromium rounds performance.now(),
# event.timeStamp and requestAnimationFrame times to 0.1 ms, and to 5 microseconds on cross-origin-isolated pages;
# Firefox defaults to 1 ms). Iris now uses at least 1 ms everywhere, including cross-origin-isolated pages; the
# Settings switch "Coarser timers" (apply-privacy-toggles-2.sh) still raises it to 100 ms. Blink's random up/down
# rounding (TimeClamper::ThresholdFor) keeps working at the new step. Cost: sites can't measure below 1 ms
# (benchmarks, some profilers); animations are unaffected at 1 ms.
# Needs apply-privacy-toggles-2.sh (its iris_coarse_timers block is the anchor).
# STATUS 2026-10-09: copy-tested only, NOT compile-proven (time_clamper.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "third_party/blink/renderer/core/timing/time_clamper.cc"
s = open(p).read()
old = ("  // Iris: Settings -> \"Coarser timers\": 100 ms, Tor Browser's value\n"
       "  // (--iris-coarse-timers from the browser; apply-privacy-toggles-2.sh).\n"
       "  static const bool iris_coarse_timers =\n"
       "      base::CommandLine::ForCurrentProcess()->HasSwitch(\"iris-coarse-timers\");\n"
       "  if (iris_coarse_timers) {\n")
new = ("  // Iris: never finer than 1 ms, also for cross-origin-isolated pages\n"
       "  // (apply-timer-precision.sh).\n"
       "  resolution = std::max(resolution, 1000);\n" + old)
if "apply-timer-precision.sh" in s: print("SKIP already applied: " + p)
elif s.count(old) == 1:
    if "#include <algorithm>" not in s:
        inc = "#include <cmath>\n"
        if s.count(inc) != 1: sys.stderr.write("ERROR: %s: <cmath> include not found (drift?)\n" % p); sys.exit(1)
        s = s.replace(inc, "#include <algorithm>  // Iris: std::max\n" + inc)
    open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : 1 ms minimum resolution")
else:
    sys.stderr.write("ERROR: %s: Iris coarse-timers block not found (run apply-privacy-toggles-2.sh first, or drift)\n" % p)
    sys.exit(1)
PY
echo "=== timer precision complete ==="
