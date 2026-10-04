#!/usr/bin/env bash
# Iris — no "Google Translate" settings (jegly 2026-10-04; verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# Translation is Google's server (translate.googleapis.com). Iris already turns the translate offer off
# (apply-privacy-batch1.sh: kOfferTranslateEnabled false, ranker off), but Settings still offered to switch it on.
# Desktop: Settings -> Languages loses its "Google Translate" card (<settings-translate-page>, the "Use Google
#   Translate" toggle + target/always/never lists) in languages_page_index.html.ts, and languages_page_index.ts no
#   longer asks cr-view-manager to show it (switchViews() asserts every listed view exists).
# Android: Settings -> Languages hides the "Translation" section (translation_settings_section) on the detailed page
#   and the translate switch on the old basic page (LanguageSettings.java). The app-language and content-language
#   lists stay.
# STATUS 2026-10-04: copy-tested only, NOT compile-proven (settings WebUI build, chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label, count=1):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != count: die("%s: anchor for %s found %d times, expected %d (drift?)" % (p, label, s.count(old), count))
    open(p, "w").write(s.replace(old, new)); print("OK   %s : %s" % (p, label))

L = "chrome/browser/resources/settings/languages_page/"
edit(L + "languages_page_index.html.ts",
     '  <settings-translate-page slot="view" id="translate">\n'
     '  </settings-translate-page>\n',
     '  <!-- Iris: no Google Translate card (apply-no-translate-settings.sh) -->\n',
     "<!-- Iris: no Google Translate card", "Languages: Google Translate card removed")
edit(L + "languages_page_index.ts",
     "        ['languages', 'spellCheck', 'translate'], 'no-animation',\n",
     "        ['languages', 'spellCheck'], 'no-animation',  // Iris: no translate view\n",
     "// Iris: no translate view", "Languages: default views without translate")

p = ("chrome/browser/language/android/java/src/org/chromium/chrome/browser/language/settings/"
     "LanguageSettings.java")
edit(p,
     "        translateSwitch.setChecked(isTranslateEnabled);\n",
     "        translateSwitch.setChecked(isTranslateEnabled);\n"
     "        translateSwitch.setVisible(false); // Iris: no Google Translate\n",
     "translateSwitch.setVisible(false); // Iris: no Google Translate", "Android: translate switch hidden", count=2)
edit(p,
     "        setupTranslateSection(languageListPref);\n",
     "        setupTranslateSection(languageListPref);\n"
     "        // Iris: no Google Translate section (the translate offer is off: apply-privacy-batch1.sh).\n"
     "        Preference irisTranslateSection = findPreference(\"translation_settings_section\");\n"
     "        if (irisTranslateSection != null) irisTranslateSection.setVisible(false);\n",
     "Preference irisTranslateSection", "Android: Translation section hidden")
PY
echo "=== translate settings removal complete ==="
