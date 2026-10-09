#!/usr/bin/env bash
# Iris — Android: remove the footer line at the bottom of Settings -> Privacy and security: "For more settings that use
# data to improve your Iris experience, go to Google Services" (jegly 2026-10-09). It is a preference row
# (PREF_SYNC_AND_SERVICES_LINK) whose text points to the Google services page, which Iris has removed. The row is hidden
# (setVisible(false)); the page behind it stays unreachable. Verified against 156.0.8078.11.
# STATUS 2026-10-09: copy-tested only, NOT compile-proven (chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
s = open(p).read()
old = ("        Preference syncAndServicesLink = findPreference(PREF_SYNC_AND_SERVICES_LINK);\n"
       "        syncAndServicesLink.setSummary(buildFooterString());\n")
new = ("        Preference syncAndServicesLink = findPreference(PREF_SYNC_AND_SERVICES_LINK);\n"
       "        syncAndServicesLink.setSummary(buildFooterString());\n"
       "        // Iris: no \"go to Google Services\" footer (apply-android-no-google-services-footer.sh).\n"
       "        syncAndServicesLink.setVisible(false);\n")
if "apply-android-no-google-services-footer.sh" in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write("ERROR: %s: footer lines not found exactly once (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new, 1)); print("OK   " + p)
PY
echo "=== Android Google services footer removed ==="
