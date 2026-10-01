#!/usr/bin/env bash
# Iris — Gemini in Chrome ("Glic", "Ask Gemini") off on every platform (jegly 2026-10-01).
# features::kGlic is Glic's main kill switch (chrome/common/chrome_features.cc). Upstream enables it by default on
# Mac/Win/ChromeOS/Android and disables it elsewhere, so desktop Iris (Linux) never showed Gemini but the Android
# APK did ("Ask Gemini" in the app menu). With kGlic off, GlicGlobalEnabling::IsEnabledByGlobalCriteria() is false,
# ProfileEnablement::feature_enabled becomes false and GlicEnabling::IsEnabledForProfile() returns false for every
# entry point (app menu, text selection, context menu, toolbar/tab-strip button). Verified against this checkout.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/common/chrome_features.cc"
s = open(p).read()
old = ("BASE_FEATURE(kGlic,\n"
       "#if BUILDFLAG(IS_MAC) || BUILDFLAG(IS_WIN) || BUILDFLAG(IS_CHROMEOS) || \\\n"
       "    BUILDFLAG(IS_ANDROID)\n"
       "             base::FEATURE_ENABLED_BY_DEFAULT\n"
       "#else\n"
       "             base::FEATURE_DISABLED_BY_DEFAULT\n"
       "#endif\n"
       ");\n")
new = "BASE_FEATURE(kGlic, base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: Gemini off everywhere\n"
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write("ERROR: %s: kGlic definition not found exactly once (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   %s : kGlic (Gemini) off on all platforms" % p)
PY
