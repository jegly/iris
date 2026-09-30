#!/usr/bin/env bash
# Iris — Settings "You and Google" -> "You and Iris" (jegly 2026-09-27: "get to it" on Claude's proposal; verified
# against this checkout).
# The section kept two useful rows (profile card, Import bookmarks and settings) and one Google row: "Google services"
# = settings-personalization-options: allow Google sign-in, "make searches and browsing better" (URL-keyed data
# collection; metrics are not compiled into Iris), enhanced spell check (sends typed text to Google), personalization
# logging, price-tracking emails, search suggestions. In Iris these are dead switches or re-open doors Iris closed.
#  1. Section title "You and Google" -> "You and Iris" (settings_strings.grdp IDS_SETTINGS_PEOPLE; text change only,
#     IDs unchanged -> no big rebuild; other locales keep the old translation until re-translated. TODO release).
#  2. "Google services" row always hidden (people_page.html.ts). The sync row is already hidden (sign-in off).
#  3. The one real choice from that page, "Autocomplete searches and URLs" (pref search.suggest_enabled, sends what you
#     type in the address bar to the search engine; Iris default off), gets its own toggle in Privacy and security
#     (privacy_page.html; pref-key resolves through the global PrefService, strings already loaded by Settings).
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

edit("chrome/app/settings_strings.grdp",
     '    <message name="IDS_SETTINGS_PEOPLE" desc="Name of the settings page which manages the user\'s relationship to Google.">\n'
     '      You and Google\n',
     '    <message name="IDS_SETTINGS_PEOPLE" desc="Name of the settings page which manages the user\'s relationship to Google.">\n'
     '      You and Iris\n',
     "      You and Iris\n", 'section title "You and Iris"')

edit("chrome/browser/resources/settings/people_page/people_page.html.ts",
     '        <cr-link-row id="google-services"\n'
     '            label="$i18n{googleServicesPageTitle}"\n'
     '            @click="${this.onGoogleServicesClick_}"\n'
     '            role-description="$i18n{subpageArrowRoleDescription}"\n'
     '            ?hidden="${!this.shouldHideSyncSetupLinkRow_()}">\n',
     '        <!-- Iris: "Google services" hidden (apply-settings-you-and-iris.sh) -->\n'
     '        <cr-link-row id="google-services"\n'
     '            label="$i18n{googleServicesPageTitle}"\n'
     '            @click="${this.onGoogleServicesClick_}"\n'
     '            role-description="$i18n{subpageArrowRoleDescription}"\n'
     '            hidden>\n',
     '"Google services" hidden', '"Google services" row hidden')

edit("chrome/browser/resources/settings/privacy_page/privacy_page.html",
     '        on-click="onSiteSettingsLinkRowClick_"\n'
     '        role-description="$i18n{subpageArrowRoleDescription}"></cr-link-row>\n',
     '        on-click="onSiteSettingsLinkRowClick_"\n'
     '        role-description="$i18n{subpageArrowRoleDescription}"></cr-link-row>\n'
     '    <!-- Iris: moved here from the hidden "Google services" page (apply-settings-you-and-iris.sh) -->\n'
     '    <settings-toggle-button id="irisSearchSuggestToggle" class="hr"\n'
     '        pref-key="search.suggest_enabled"\n'
     '        label="$i18n{searchSuggestPref}"\n'
     '        sub-label="$i18n{searchSuggestPrefDesc}">\n'
     '    </settings-toggle-button>\n',
     "irisSearchSuggestToggle", "autocomplete toggle in Privacy and security")

p = "chrome/browser/resources/settings/privacy_page/privacy_page.ts"
s = open(p).read()
imp = "import '../controls/settings_toggle_button.js';\n"
if imp in s: print("SKIP already imported: " + p)
else:
    anchor = "import '/shared/settings/prefs/prefs.js';\n"
    if s.count(anchor) != 1: die(p + ": import anchor missing (drift?)")
    open(p, "w").write(s.replace(anchor, anchor + imp, 1)); print("OK   " + p + " : imports settings_toggle_button")
PY
echo "=== Settings: You and Iris complete ==="
