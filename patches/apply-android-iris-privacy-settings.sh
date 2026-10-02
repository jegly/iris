#!/usr/bin/env bash
# Iris — Android: an "Iris" section in Settings -> Privacy and security with Iris's own switches (jegly 2026-10-02
# "get that all done now"). Verified against this checkout. The logic behind each switch already runs on Android
# (iris_shredder, iris_google_signin_throttle, the IRIS_WEBGL check in chrome_content_browser_client are in the Android
# build); until now Android just had no way to change them.
#   - Block screenshots           (apply-android-screenshot-protection.sh; moved under this heading)
#   - Delete browsing data automatically   profile pref iris.shredding.enabled (hourly: cookies + site data > 24 h,
#                                           cache > 12 h, downloads list > 7 days; also clears copied text after 30 s)
#   - Allow WebGL                  default of ContentSettingsType.IRIS_WEBGL (BLOCK by default)
#   - Allow "Sign in with Google" prompts   default of ContentSettingsType.IRIS_GOOGLE_SIGNIN (BLOCK by default)
# Per-site choices (WebGL/sign-in exceptions, browser identity, canvas/audio reading, forget this site) are per-site
# UI = Page Info / Site settings work, not here. English-only labels (no new grit IDs).
# Needs apply-android-screenshot-protection.sh first (anchors on its block).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
s = open(p).read()
MARK = '// Iris: "Iris" section'
if MARK in s:
    print("SKIP already applied: %s (Iris section)" % p); sys.exit(0)
a1 = '        // Iris: "Block screenshots" (screenshot protection, on by default).\n'
a2 = "        getPreferenceScreen().addPreference(irisScreenshots);\n"
for a in (a1, a2):
    if s.count(a) != 1: die("%s: screenshot block not found (run apply-android-screenshot-protection.sh first)" % p)
CAT = ('        // Iris: "Iris" section (Iris\'s own privacy switches; English-only labels).\n'
       '        androidx.preference.PreferenceCategory irisCategory =\n'
       '                new androidx.preference.PreferenceCategory(getPreferenceManager().getContext());\n'
       '        irisCategory.setKey("iris_section");\n'
       '        irisCategory.setTitle("Iris");\n'
       '        getPreferenceScreen().addPreference(irisCategory);\n')
CS = "org.chromium.components.content_settings.ContentSetting"
def content_switch(var, key, ctype, title, summary):
    return ('        ChromeSwitchPreference %s =\n'
            '                new ChromeSwitchPreference(getPreferenceManager().getContext());\n'
            '        %s.setKey("%s");\n'
            '        %s.setPersistent(false);\n'
            '        %s.setTitle("%s");\n'
            '        %s.setSummary(\n'
            '                "%s");\n'
            '        %s.setChecked(\n'
            '                WebsitePreferenceBridge.getDefaultContentSetting(\n'
            '                                getProfile(), ContentSettingsType.%s)\n'
            '                        == %s.ALLOW);\n'
            '        %s.setOnPreferenceChangeListener(\n'
            '                (preference, newValue) -> {\n'
            '                    WebsitePreferenceBridge.setDefaultContentSetting(\n'
            '                            getProfile(),\n'
            '                            ContentSettingsType.%s,\n'
            '                            (Boolean) newValue ? %s.ALLOW : %s.BLOCK);\n'
            '                    return true;\n'
            '                });\n'
            '        irisCategory.addPreference(%s);\n') % (
            var, var, key, var, var, title, var, summary, var, ctype, CS, var, ctype, CS, CS, var)
MORE = ('        ChromeSwitchPreference irisShredding =\n'
        '                new ChromeSwitchPreference(getPreferenceManager().getContext());\n'
        '        irisShredding.setKey("iris_shredding");\n'
        '        irisShredding.setPersistent(false);\n'
        '        irisShredding.setTitle("Delete browsing data automatically");\n'
        '        irisShredding.setSummary(\n'
        '                "Every hour: cookies and site data older than 24 hours, cache older than 12 hours,"\n'
        '                        + " downloads list older than 7 days. Text copied in Iris is cleared from the"\n'
        '                        + " clipboard after 30 seconds.");\n'
        '        irisShredding.setChecked(UserPrefs.get(getProfile()).getBoolean("iris.shredding.enabled"));\n'
        '        irisShredding.setOnPreferenceChangeListener(\n'
        '                (preference, newValue) -> {\n'
        '                    UserPrefs.get(getProfile())\n'
        '                            .setBoolean("iris.shredding.enabled", (Boolean) newValue);\n'
        '                    return true;\n'
        '                });\n'
        '        irisCategory.addPreference(irisShredding);\n'
        + content_switch("irisWebgl", "iris_webgl", "IRIS_WEBGL", "Allow WebGL",
                         "3D graphics for websites. Off by default: WebGL exposes details of your graphics"
                         " hardware that can be used to identify you.")
        + content_switch("irisGoogleSignin", "iris_google_signin", "IRIS_GOOGLE_SIGNIN",
                         "Allow \\\"Sign in with Google\\\" prompts",
                         "Google's sign-in pop-ups on other websites. Off by default. Signing in on Google's"
                         " own sites is not affected."))
s = s.replace(a1, CAT + a1, 1)
s = s.replace(a2, "        irisCategory.addPreference(irisScreenshots);\n" + MORE, 1)
open(p, "w").write(s)
print("OK   %s : Iris section (screenshots, automatic deletion, WebGL, Google sign-in prompts)" % p)
PY
