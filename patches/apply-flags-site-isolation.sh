#!/usr/bin/env bash
# Iris — remove the misleading "Strict site isolation" row from chrome://flags on Android (jegly 2026-10-11: "flags
# should show what flags are actually on or off ... not show disabled if its enabled"; verified against 156.0.8078.11).
# The row (#enable-site-per-process, Android only) is a SINGLE_VALUE switch row: it only adds --site-per-process, so
# its two choices are Disabled / Enabled and it shows "Disabled" whenever that switch was not added by hand. Iris turns
# strict site isolation on in code (apply-flags-group5.sh: kSitePerProcess ENABLED on Android), so the row said
# "Disabled" while chrome://process-internals showed "Site Per Process" (seen on jegly's phone, 0.0.0.7).
# apply-flags-default-state.sh cannot fix this row: it labels feature rows only, and this row is a switch.
# Removed instead of turned into a feature row: a feature row would add a "Disabled" choice that switches strict site
# isolation off. A value saved by an earlier version ("Enabled") is ignored once the row is gone (flags_state drops
# unknown entries).
# Not changed: #site-isolation-trial-opt-out (desktop + Android) can still turn site isolation off for testing.
# flag-metadata.json keeps its entry (only about_flags_unittest reads it; Iris does not build tests).
# Needs nothing else. STATUS 2026-10-11: copy-tested only, NOT compile-proven (about_flags.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/browser/about_flags.cc"
s = open(p).read()
OLD = ('    {"enable-site-per-process", flag_descriptions::kStrictSiteIsolationName,\n'
       '     flag_descriptions::kStrictSiteIsolationDescription, kOsAndroid,\n'
       '     SINGLE_VALUE_TYPE(switches::kSitePerProcess)},\n')
NEW = ('    // Iris: no "enable-site-per-process" row (apply-flags-site-isolation.sh):\n'
       '    // strict site isolation is always on in Iris, and this switch row showed\n'
       '    // "Disabled" anyway.\n')
if NEW in s and OLD not in s:
    print("SKIP already applied: %s (enable-site-per-process row removed)" % p); sys.exit(0)
if s.count(OLD) != 1:
    sys.stderr.write("ERROR: %s: enable-site-per-process entry found %d times (drift?)\n" % (p, s.count(OLD))); sys.exit(1)
open(p, "w").write(s.replace(OLD, NEW))
print("OK   %s : enable-site-per-process row removed" % p)
PY
echo "=== flags site isolation row complete ==="
