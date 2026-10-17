#!/usr/bin/env bash
# Iris — no Privacy Guide on Android (jegly 2026-10-16: "settings > privacy and security > privacy guide ... privacy
# guide is irrelevant for iris"; verified against 156.0.8078.11 sources fetched from gitiles).
# The guide walks through Google services, sync, Safe Browsing and cookie choices that Iris has removed or fixed.
# Desktop already hides it (apply-settings-cleanup.sh: showPrivacyGuide = false).
# Android: PrivacySettings.onCreatePreferences() always removes the "Privacy guide" row. Upstream already removes it the
# same way for child and managed profiles, so this is a tested path; the now-unused ManagedBrowserUtils import goes too.
# Settings search: upstream has no separate index entry for the row (and Iris turns settings search off,
# apply-android-no-settings-search.sh).
# STATUS 2026-10-16: copy-tested on upstream 156.0.8078.11 PrivacySettings.java, NOT compile-proven (chrome_java).
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
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
edit(J, "        if (getProfile().isChild()\n"
        "                || ManagedBrowserUtils.isBrowserManaged(getProfile())\n"
        "                || ManagedBrowserUtils.isProfileManaged(getProfile())) {\n"
        "            getPreferenceScreen().removePreference(privacyGuidePreference);\n"
        "        }\n",
     "        // Iris: no Privacy Guide (apply-android-no-privacy-guide.sh).\n"
     "        getPreferenceScreen().removePreference(privacyGuidePreference);\n",
     "no Privacy Guide (apply-android-no-privacy-guide.sh)", "Privacy guide row removed")
IMP = "import org.chromium.chrome.browser.enterprise.util.ManagedBrowserUtils;\n"
s = open(J).read()
if "ManagedBrowserUtils." in s or IMP not in s:
    print("SKIP ManagedBrowserUtils import (still used, or already removed)")
else:
    open(J, "w").write(s.replace(IMP, "", 1)); print("OK   %s : unused import removed" % J)
PY
echo "=== Android: no Privacy Guide complete ==="
