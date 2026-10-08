#!/usr/bin/env bash
# Iris — Android home screen, round 2 (jegly 2026-10-08, from testing the signed -1 APK: spinner still there and the
# "Iris tips - Enhance your security" card still shown; verified against the 156.0.8078.11 sources).
# 1. Spinner: LogoContainerView shows a LoadingView while it waits for a search-engine logo; DuckDuckGo etc. have no
#    default logo drawable so it spins forever. LogoMediator.updateVisibility() now never shows a logo (no logo
#    fetch either). Needs nothing else.
# 2. Tips card: the "Iris tips" educational-tip / setup-list module (Enhanced Safe Browsing, default browser, sign
#    in...) is never built and never eligible, so it is hidden by default and cannot appear. (Upstream's own
#    "Hide Iris tips card" menu item stays for any leftover case.)
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (chrome_java).
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

edit("chrome/browser/ui/android/logo/java/src/org/chromium/chrome/browser/logo/LogoMediator.java",
     "        mShouldShowLogo = doesDefaultSearchEngineHaveLogo(mProfile);\n        mLogoModel.set(LogoProperties.VISIBILITY, mShouldShowLogo);\n",
     "        // Iris: no search-engine logo on the home screen (its loading spinner never ended).\n"
     "        mShouldShowLogo = false;\n        mLogoModel.set(LogoProperties.VISIBILITY, mShouldShowLogo);\n",
     "Iris: no search-engine logo", "no logo / no spinner")
d = "chrome/browser/educational_tip/java/src/org/chromium/chrome/browser/educational_tip/EducationalTipModuleBuilder.java"
edit(d,
     "            ModuleDelegate moduleDelegate, Callback<ModuleProvider> onModuleBuiltCallback) {\n        if (!SetupListModuleUtils",
     "            ModuleDelegate moduleDelegate, Callback<ModuleProvider> onModuleBuiltCallback) {\n"
     "        if (true) return false;  // Iris: no tips card\n        if (!SetupListModuleUtils",
     "Iris: no tips card", "tips module never built")
edit(d,
     "    public boolean isEligible() {\n        if (SetupListModuleUtils",
     "    public boolean isEligible() {\n        if (true) return false;  // Iris: no tips card\n        if (SetupListModuleUtils",
     "isEligible() {\n        if (true)", "tips module never eligible")
PY
echo "=== Android home screen round 2 complete ==="
