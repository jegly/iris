#!/usr/bin/env bash
# Iris — Settings "Autofill and passwords" (Your saved info): remove the Google-only parts (jegly 2026-10-04;
# verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# chrome/browser/resources/settings/autofill_page/autofill_page.html:
#  - <settings-account-card>: the Google account / sign-in card at the top (Iris has no Google sign-in)
#  - "Related services": the Google Wallet and Google Account links (both open Google sites)
#  - the "Suggestions from Gemini" card (AI; Iris has none)
# Kept: Password Manager, Payment methods, Addresses and more, the autofill switches, and the identity-docs / travel /
# shopping cards: those have subpages that autofill_page.ts finds by element id (getAssociatedControlFor asserts the
# element exists), so removing them could break back-navigation; the cards hold only data saved on this device.
# STATUS 2026-10-04: copy-tested only, NOT compile-proven (settings WebUI build).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/resources/settings/autofill_page/autofill_page.html"
s = open(p).read()
MARK = "<!-- Iris: no Google account card"
if MARK in s:
    print("SKIP already applied: %s" % p); sys.exit(0)
CUTS = [
    ('<settings-account-card prefs="{{prefs}}">\n'
     '</settings-account-card>\n',
     '<!-- Iris: no Google account card (apply-autofill-page-trim.sh) -->\n', "Google account card"),
    ('    <cr-link-row id="googleWalletButton" label="$i18n{googleWalletTitle}"\n'
     '        on-click="onGoogleWalletRelatedServiceClick_"\n'
     '        start-icon="settings20:wallet" external>\n'
     '    </cr-link-row>\n'
     '    <cr-link-row id="googleAccountButton" label="$i18n{googleAccount}"\n'
     '        on-click="onGoogleAccountRelatedServiceClick_"\n'
     '        start-icon="settings20:google" external>\n'
     '    </cr-link-row>\n',
     '    <!-- Iris: no Google Wallet / Google Account links -->\n', "Google Wallet + Google Account links"),
    ('  <template is="dom-if" if="[[showSuggestionsFromGeminiSettings_]]">\n'
     '    <div id="suggestionsFromGeminiCard">\n'
     '      <cr-link-row id="suggestionsFromGeminiLinkRow"\n'
     '        label="$i18n{autofillPersonalContextSettingsTitle}"\n'
     '        on-click="onSuggestionsFromGeminiClick_">\n'
     '      </cr-link-row>\n'
     '      <hr>\n'
     '      <div id="suggestionsFromGeminiSubLabel" class="secondary">\n'
     '        <cr-icon icon="[[spark_]]" aria-hidden="true"></cr-icon>\n'
     '        $i18n{autofillPersonalContextSettingsSummary}\n'
     '      </div>\n'
     '    </div>\n'
     '  </template>\n',
     '  <!-- Iris: no Gemini suggestions card -->\n', "Gemini suggestions card"),
]
for old, new, what in CUTS:
    if s.count(old) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
    s = s.replace(old, new, 1)
open(p, "w").write(s)
print("OK   %s : Google account card, Google Wallet/Account links, Gemini card removed" % p)
PY
echo "=== autofill page trim complete ==="
