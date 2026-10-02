#!/usr/bin/env bash
# Iris — Android screenshot protection (jegly 2026-10-02 "get that all done now"; from jegly's WWW app, where
# "Screenshot Protection" defaults to ON). Verified against this checkout.
# When on, every Iris window gets WindowManager FLAG_SECURE: screenshots, screen recording and the Recents
# thumbnail show a blank screen. Stored as a plain app preference "iris_screenshot_protection" (default true).
#  1) ChromeBaseAppCompatActivity.onCreate (base of the browser, Settings, Custom Tabs ... activities): add the flag.
#  2) Chromium's two FLAG_SECURE controllers (IncognitoSnapshotController, ScreenshotProtectionController) set AND
#     CLEAR the flag (e.g. when leaving Incognito); with Iris protection on they must never clear it -> their
#     "expected secure state" is forced true.
#  3) Settings -> Privacy and security: a "Block screenshots" switch (English-only label, no new grit IDs); takes
#     effect on the current window at once, other windows when they are next created.
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
PREF = ('org.chromium.base.ContextUtils.getAppSharedPreferences()\n'
        '                        .getBoolean("iris_screenshot_protection", true)')

# 1) every Iris activity
p = "chrome/android/java/src/org/chromium/chrome/browser/ChromeBaseAppCompatActivity.java"
M = ("        // Iris: screenshot protection (Settings > Privacy and security), on by default.\n"
     "        if (" + PREF + ") {\n"
     "            getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE);\n"
     "        }\n")
edit(p, "        applyThemeOverlays();\n        super.onCreate(savedInstanceState);\n",
     "        applyThemeOverlays();\n        super.onCreate(savedInstanceState);\n" + M,
     "// Iris: screenshot protection (Settings > Privacy and security)", "FLAG_SECURE on create")

# 2a) Incognito controller must not clear it
p = "chrome/android/java/src/org/chromium/chrome/browser/incognito/IncognitoSnapshotController.java"
M = ("        if (" + PREF + ") {\n"
     "            expectedSecureState = true; // Iris: screenshot protection is on\n"
     "        }\n")
edit(p, "            expectedSecureState = false;\n        }\n        if (currentSecureState == expectedSecureState) return;\n",
     "            expectedSecureState = false;\n        }\n" + M +
     "        if (currentSecureState == expectedSecureState) return;\n",
     "expectedSecureState = true; // Iris: screenshot protection is on", "Incognito controller keeps it")

# 2b) enterprise/screenshot controller must not clear it
p = "chrome/browser/android/screenshot_protection/java/src/org/chromium/chrome/browser/screenshot_protection/ScreenshotProtectionController.java"
edit(p, "        boolean expectedSecureState = isScreenshotBlocked();\n",
     "        boolean expectedSecureState =\n"
     "                isScreenshotBlocked()\n"
     "                        || " + PREF.replace("\n                        ", "\n                                ") + "; // Iris\n",
     '"iris_screenshot_protection", true); // Iris', "screenshot controller keeps it")
p = "chrome/browser/android/screenshot_protection/BUILD.gn"
edit(p, '    sources = [ "java/src/org/chromium/chrome/browser/screenshot_protection/ScreenshotProtectionController.java" ]\n    deps = [\n',
     '    sources = [ "java/src/org/chromium/chrome/browser/screenshot_protection/ScreenshotProtectionController.java" ]\n    deps = [\n      "//base:base_java",  # Iris: ContextUtils\n',
     '"//base:base_java",  # Iris: ContextUtils', "base_java dep")

# 3) the switch in Privacy and security
p = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
M = ('        // Iris: "Block screenshots" (screenshot protection, on by default).\n'
     '        ChromeSwitchPreference irisScreenshots =\n'
     '                new ChromeSwitchPreference(getPreferenceManager().getContext());\n'
     '        irisScreenshots.setKey("iris_screenshot_protection");\n'
     '        irisScreenshots.setPersistent(false);\n'
     '        irisScreenshots.setTitle("Block screenshots");\n'
     '        irisScreenshots.setSummary(\n'
     '                "Screenshots, screen recording and the Recents preview of Iris show a blank screen");\n'
     '        irisScreenshots.setChecked(\n'
     '                ' + PREF.replace("\n                        ", "\n                                ") + ');\n'
     '        irisScreenshots.setOnPreferenceChangeListener(\n'
     '                (preference, newValue) -> {\n'
     '                    boolean on = (Boolean) newValue;\n'
     '                    org.chromium.base.ContextUtils.getAppSharedPreferences()\n'
     '                            .edit()\n'
     '                            .putBoolean("iris_screenshot_protection", on)\n'
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
     '                    return true;\n'
     '                });\n'
     '        getPreferenceScreen().addPreference(irisScreenshots);\n')
edit(p, "        SettingsUtils.addPreferencesFromResource(this, R.xml.privacy_preferences);\n",
     "        SettingsUtils.addPreferencesFromResource(this, R.xml.privacy_preferences);\n" + M,
     '// Iris: "Block screenshots"', "Block screenshots switch")
PY
