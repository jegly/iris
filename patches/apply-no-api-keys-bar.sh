#!/usr/bin/env bash
# Iris — no "Google API keys are missing. Some functionality of Iris will be disabled." bar (jegly 2026-09-27;
# verified against this checkout). Iris ships without Google API keys on purpose (they are what connect Chromium to
# Google services: sync, translate, speech, ...), so the startup bar is expected, not a problem.
# The block in chrome/browser/ui/startup/infobar_utils.cc that shows it is removed whole (an `if (false)` would trip
# -Wunreachable-code-aggressive). chrome://infobar-internals can still show it for testing.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/browser/ui/startup/infobar_utils.cc"
s = open(p).read()
marker = "// Iris: no missing-API-keys bar"
if marker in s: print("SKIP already applied: " + p); sys.exit(0)
start = "  if (!google_apis::HasAPIKeyConfigured()) {\n"
if s.count(start) != 1: sys.stderr.write("ERROR: %s: API-keys block not found (drift?)\n" % p); sys.exit(1)
i = s.index(start)
end_pat = "      GoogleApiKeysInfoBarDelegate::Create(infobar_manager);\n    }\n  }\n"
j = s.find(end_pat, i)
if j < 0 or j - i > 900: sys.stderr.write("ERROR: %s: API-keys block shape changed (drift?)\n" % p); sys.exit(1)
s = s[:i] + "  " + marker + " (Iris ships without Google API keys on purpose).\n" + s[j + len(end_pat):]
open(p, "w").write(s); print("OK   " + p + " : missing-API-keys bar removed")
PY
echo "=== no API-keys bar complete ==="
