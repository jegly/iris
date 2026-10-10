#!/usr/bin/env bash
# Iris — Android: a switch to hide the shield button (jegly 2026-10-11: "i want a switch to hide the shield on phones";
# the toolbar looked cramped). Settings > Appearance > "Shield button", default on, like the desktop's toolbar-button
# switches in Settings > Appearance. Verified against 156.0.8078.11.
#  - The switch writes the app preference "iris_shield_button" (IrisShieldController.SHOW_BUTTON_PREF).
#  - IrisShieldController (patches/src, copied by apply-android-shield.sh) hides or shows the button at once when the
#    preference changes. Hiding only removes the button: blocking and the per-site settings keep working, and the
#    per-site settings stay in Site settings > Iris.
# English-only label (no new grit string), like the other Iris switches on Android.
# Needs apply-android-shield.sh and apply-android-themes.sh (anchor: the "Colours" picker).
# STATUS 2026-10-11: copy-tested only, NOT compile-proven (chrome/android:chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/android/java/src/org/chromium/chrome/browser/appearance/settings/AppearanceSettingsFragment.java"
s = open(p).read()
MARK = '"Shield button"'
if MARK in s:
    print("SKIP already applied: %s (Shield button switch)" % p); sys.exit(0)
OLD = "        getPreferenceScreen().addPreference(irisPalette);\n"
NEW = OLD + (
    '        // Iris: "Shield button" (apply-android-shield-toggle.sh): show or hide the\n'
    '        // shield in the toolbar. Blocking keeps working when it is hidden.\n'
    '        ChromeSwitchPreference irisShieldButton =\n'
    '                new ChromeSwitchPreference(getPreferenceManager().getContext());\n'
    '        irisShieldButton.setKey("iris_shield_button_switch");\n'
    '        irisShieldButton.setPersistent(false);\n'
    '        irisShieldButton.setTitle("Shield button");\n'
    '        irisShieldButton.setSummary(\n'
    '                "Show the shield in the toolbar. Blocking keeps working when it is hidden.");\n'
    '        irisShieldButton.setChecked(\n'
    '                ContextUtils.getAppSharedPreferences()\n'
    '                        .getBoolean(\n'
    '                                org.chromium.chrome.browser.iris.IrisShieldController\n'
    '                                        .SHOW_BUTTON_PREF,\n'
    '                                true));\n'
    '        irisShieldButton.setOnPreferenceChangeListener(\n'
    '                (preference, newValue) -> {\n'
    '                    ContextUtils.getAppSharedPreferences()\n'
    '                            .edit()\n'
    '                            .putBoolean(\n'
    '                                    org.chromium.chrome.browser.iris.IrisShieldController\n'
    '                                            .SHOW_BUTTON_PREF,\n'
    '                                    (Boolean) newValue)\n'
    '                            .apply();\n'
    '                    return true;\n'
    '                });\n'
    '        getPreferenceScreen().addPreference(irisShieldButton);\n')
if s.count(OLD) != 1:
    sys.stderr.write("ERROR: %s: Colours picker anchor found %d times (apply-android-themes.sh not applied, or drift)\n"
                     % (p, s.count(OLD))); sys.exit(1)
open(p, "w").write(s.replace(OLD, NEW))
print("OK   %s : Shield button switch" % p)
PY
echo "=== android shield toggle complete ==="
