#!/usr/bin/env bash
# Iris — "Block screenshots" takes effect at once in every open Iris window (jegly 2026-10-11: "when screenshots are
# blocked is turned on and i turn it off and take a screenshot its still blocked i have to close the app and re open";
# verified against 156.0.8078.11).
# Cause: the switch (apply-android-screenshot-protection.sh) changed FLAG_SECURE only on the Settings window. The
# browser window got the flag in onCreate and kept it until it was created again (app restart).
# Fix: the switch now walks ApplicationStatus.getRunningActivities() and adds or clears FLAG_SECURE on each. When
# turning it off, a browser window that is showing Incognito keeps the flag (Chromium's IncognitoSnapshotController
# re-checks it when you leave Incognito).
# Needs apply-android-screenshot-protection.sh (anchor). STATUS 2026-10-11: copy-tested only, NOT compile-proven
# (chrome/android:chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
s = open(p).read()
MARK = "apply-android-screenshot-live.sh"
if MARK in s:
    print("SKIP already applied: %s (screenshot switch applies to every window)" % p); sys.exit(0)
OLD = ('                            .putBoolean("iris_screenshot_protection", on)\n'
       '                            .apply();\n'
       '                    android.app.Activity activity = getActivity();\n'
       '                    if (activity != null) {\n'
       '                        if (on) {\n'
       '                            activity.getWindow()\n'
       '                                    .addFlags(\n'
       '                                            android.view.WindowManager.LayoutParams.FLAG_SECURE);\n'
       '                        } else {\n'
       '                            activity.getWindow()\n'
       '                                    .clearFlags(\n'
       '                                            android.view.WindowManager.LayoutParams.FLAG_SECURE);\n'
       '                        }\n'
       '                    }\n'
       '                    return true;\n')
NEW = ('                            .putBoolean("iris_screenshot_protection", on)\n'
       '                            .apply();\n'
       '                    // Iris: every open Iris window at once, not only Settings\n'
       '                    // (apply-android-screenshot-live.sh). A window showing\n'
       '                    // Incognito keeps the flag.\n'
       '                    for (android.app.Activity activity :\n'
       '                            org.chromium.base.ApplicationStatus.getRunningActivities()) {\n'
       '                        if (on) {\n'
       '                            activity.getWindow()\n'
       '                                    .addFlags(\n'
       '                                            android.view.WindowManager.LayoutParams.FLAG_SECURE);\n'
       '                            continue;\n'
       '                        }\n'
       '                        if (activity\n'
       '                                        instanceof\n'
       '                                        org.chromium.chrome.browser.app.ChromeActivity\n'
       '                                                chromeActivity\n'
       '                                && chromeActivity.areTabModelsInitialized()\n'
       '                                && chromeActivity.getTabModelSelector().isIncognitoSelected()) {\n'
       '                            continue;\n'
       '                        }\n'
       '                        activity.getWindow()\n'
       '                                .clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE);\n'
       '                    }\n'
       '                    return true;\n')
if s.count(OLD) != 1:
    sys.stderr.write("ERROR: %s: Block screenshots listener found %d times (drift?)\n" % (p, s.count(OLD))); sys.exit(1)
open(p, "w").write(s.replace(OLD, NEW))
print("OK   %s : screenshot switch applies to every window" % p)
PY
echo "=== android screenshot live complete ==="
