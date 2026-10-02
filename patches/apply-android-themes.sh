#!/usr/bin/env bash
# Iris — Android themes (jegly 2026-10-02 "get that all done now"): the desktop Iris palettes on Android, dark by
# default with Catppuccin Mocha, like desktop (apply-catppuccin-default.sh / apply-palettes-picker.sh).
# Verified against this checkout.
#  - Generated from the same palette header as desktop (branding/gen_palettes_android.py ->
#    patches/src/chrome/android/java/res/values/iris_palettes.xml + .../browser/iris/IrisPalettes.java): one Material 3
#    ThemeOverlay per palette; both files are copied here and added to chrome_java_{sources,resources}.gni.
#  - ChromeBaseAppCompatActivity.applyThemeOverlays(): applies the chosen palette's overlay (after dynamic colours)
#    when its light/dark kind matches the current mode.
#  - NightModeUtils.getThemeSetting(): default DARK instead of "system default" (users can still pick in Settings).
#  - Settings -> Appearance: "Colours" list (English-only labels). Picking a palette also sets light/dark to match it
#    (UI_THEME_SETTING), then redraws.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
PSRC="$(cd "$(dirname "$0")" && pwd)/src"
cd "$SRC"
for f in chrome/android/java/res/values/iris_palettes.xml \
         chrome/android/java/src/org/chromium/chrome/browser/iris/IrisPalettes.java; do
  [ -f "$PSRC/$f" ] || { echo "ERROR: missing $PSRC/$f (run branding/gen_palettes_android.py)" >&2; exit 1; }
  mkdir -p "$(dirname "$f")"
  if cmp -s "$PSRC/$f" "$f"; then echo "SKIP already applied: $f"; else cp "$PSRC/$f" "$f"; echo "OK   $f : copied"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

edit("chrome/android/chrome_java_sources.gni",
     '  "java/src/org/chromium/chrome/browser/ChromeBaseAppCompatActivity.java",\n',
     '  "java/src/org/chromium/chrome/browser/ChromeBaseAppCompatActivity.java",\n'
     '  "java/src/org/chromium/chrome/browser/iris/IrisPalettes.java",  # Iris\n',
     '"java/src/org/chromium/chrome/browser/iris/IrisPalettes.java",  # Iris', "java source")
edit("chrome/android/chrome_java_resources.gni",
     '  "java/res/values/styles.xml",\n',
     '  "java/res/values/iris_palettes.xml",  # Iris\n  "java/res/values/styles.xml",\n',
     '"java/res/values/iris_palettes.xml",  # Iris', "resource")

p = "chrome/android/java/src/org/chromium/chrome/browser/ChromeBaseAppCompatActivity.java"
old = ("        if (shouldApplyDynamicColors()) {\n"
       "            if (!maybeApplyCustomizedColors()) {\n"
       "                DynamicColors.applyToActivityIfAvailable(this);\n"
       "            }\n"
       "        }\n")
new = old + ("\n        // Iris: colour palette (Settings > Appearance; default Catppuccin Mocha, dark).\n"
             "        int irisPalette =\n"
             "                org.chromium.chrome.browser.iris.IrisPalettes.overlayFor(\n"
             "                        mNightModeStateProvider.isInNightMode());\n"
             "        if (irisPalette != 0) applySingleThemeOverlay(irisPalette);\n")
edit(p, old, new, "// Iris: colour palette (Settings > Appearance", "apply palette overlay")

p = "chrome/browser/ui/android/night_mode/java/src/org/chromium/chrome/browser/night_mode/NightModeUtils.java"
edit(p, "        if (userSetting == -1) {\n            return ThemeType.SYSTEM_DEFAULT;\n",
     "        if (userSetting == -1) {\n            return ThemeType.DARK; // Iris: dark by default (as on desktop)\n",
     "return ThemeType.DARK; // Iris", "dark by default")

p = "chrome/android/java/src/org/chromium/chrome/browser/appearance/settings/AppearanceSettingsFragment.java"
M = ('        // Iris: "Colours" (Iris palettes; picking one also sets light/dark to match).\n'
     '        androidx.preference.ListPreference irisPalette =\n'
     '                new androidx.preference.ListPreference(getPreferenceManager().getContext());\n'
     '        irisPalette.setKey("iris_palette_picker");\n'
     '        irisPalette.setPersistent(false);\n'
     '        irisPalette.setTitle("Colours");\n'
     '        irisPalette.setDialogTitle("Colours");\n'
     '        String[] irisValues =\n'
     '                new String[org.chromium.chrome.browser.iris.IrisPalettes.NAMES.length];\n'
     '        for (int i = 0; i < irisValues.length; i++) irisValues[i] = String.valueOf(i);\n'
     '        irisPalette.setEntries(org.chromium.chrome.browser.iris.IrisPalettes.NAMES);\n'
     '        irisPalette.setEntryValues(irisValues);\n'
     '        irisPalette.setValueIndex(org.chromium.chrome.browser.iris.IrisPalettes.getSelected());\n'
     '        irisPalette.setSummaryProvider(\n'
     '                androidx.preference.ListPreference.SimpleSummaryProvider.getInstance());\n'
     '        irisPalette.setOnPreferenceChangeListener(\n'
     '                (preference, newValue) -> {\n'
     '                    int index = Integer.parseInt((String) newValue);\n'
     '                    org.chromium.chrome.browser.iris.IrisPalettes.setSelected(index);\n'
     '                    org.chromium.chrome.browser.preferences.ChromeSharedPreferences.getInstance()\n'
     '                            .writeInt(\n'
     '                                    org.chromium.chrome.browser.preferences.ChromePreferenceKeys\n'
     '                                            .UI_THEME_SETTING,\n'
     '                                    org.chromium.chrome.browser.iris.IrisPalettes.DARK[index]\n'
     '                                            ? org.chromium.chrome.browser.night_mode.ThemeType.DARK\n'
     '                                            : org.chromium.chrome.browser.night_mode.ThemeType\n'
     '                                                    .LIGHT);\n'
     '                    android.app.Activity activity = getActivity();\n'
     '                    if (activity != null) activity.recreate();\n'
     '                    return true;\n'
     '                });\n'
     '        getPreferenceScreen().addPreference(irisPalette);\n')
edit(p, "        SettingsUtils.addPreferencesFromResource(this, R.xml.appearance_preferences);\n",
     "        SettingsUtils.addPreferencesFromResource(this, R.xml.appearance_preferences);\n" + M,
     '// Iris: "Colours"', "Colours picker")
PY
