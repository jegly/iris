#!/usr/bin/env bash
# Iris — Safety Hub (chrome://settings/safetyCheck): drop two items that are wrong for Iris (jegly 2026-10-04;
# verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# 1. Passwords card under "Safety at a glance": Iris turns password saving off on purpose, and Chromium then shows
#    "No saved passwords / Your organization turned off saving passwords"
#    (chrome/browser/ui/safety_hub/password_status_check_service.cc picks ..._NO_PASSWORDS_POLICY whenever saving is
#    off), which reads as if the browser were managed by an organisation (MDM). Iris has no management.
# 2. "Learn how Iris keeps you safe" box (shown when there is nothing to review): its three links go to Google's
#    Chrome pages (kChromeSafePageURL, kIncognitoHelpCenterURL, kSafeBrowsingUseInChromeURL in
#    settings_localized_strings_provider.cc) and the blanket rename turned "Chromium Incognito" into "Iris Incognito".
# The page template changes (safety_hub_page.html.ts) and the element-id list in safety_hub_page.ts; the TS
# methods behind the two items stay (unused, harmless). The version and Safe Browsing cards and the review modules
# (notifications, unused permissions, extensions) and the "nothing to review" message stay.
# STATUS 2026-10-04: copy-tested only, NOT compile-proven (settings WebUI build: tsc + lit template).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
# The page's TypeScript lists the element ids it expects; the build's lint rule (lit-element-invalid-interface) fails
# if one is listed but missing from the template (found 2026-10-06 in the first real build): drop `passwords` there.
t = "chrome/browser/resources/settings/safety_hub/safety_hub_page.ts"
ts = open(t).read()
ID = "    passwords: SettingsSafetyHubCardElement,\n"
if ID in ts:
    if ts.count(ID) != 1 or "$.passwords" in ts: die("%s: unexpected use of the passwords id (drift?)" % t)
    open(t, "w").write(ts.replace(ID, "", 1)); print("OK   %s : passwords id removed from the element interface" % t)
else:
    print("SKIP already applied: %s (passwords id)" % t)

p = "chrome/browser/resources/settings/safety_hub/safety_hub_page.html.ts"
s = open(p).read()
MARK = "<!-- Iris: no passwords card"
if MARK in s:
    print("SKIP already applied: %s" % p); sys.exit(0)
card = ('    <settings-safety-hub-card id="passwords" class="card box"\n'
        '        .data="${this.passwordCardData_}" @click="${this.onPasswordsClick_}"\n'
        '        tabindex="0" @keydown="${this.onPasswordsKeydown_}" role="link"\n'
        '        aria-description="$i18n{safetyHubPasswordNavigationAriaLabel}">\n'
        '    </settings-safety-hub-card>\n')
edu = ('    <settings-safety-hub-module\n'
       '        id="userEducationModule"\n'
       '        @sh-module-item-link-click="${this.onShModuleItemLinkClick_}"\n'
       '        class="module box"\n'
       '        header="$i18n{safetyHubUserEduModuleHeader}"\n'
       '        header-icon="settings20:lightbulb-2"\n'
       '        .sites="${this.userEducationItemList_}">\n'
       '    </settings-safety-hub-module>\n')
for blk, what in ((card, "passwords card"), (edu, "user education module")):
    if s.count(blk) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
s = s.replace(card, "    <!-- Iris: no passwords card (saving is off by design; the card claimed an organisation"
              " turned it off) -->\n", 1)
s = s.replace(edu, "    <!-- Iris: no 'Learn how ... keeps you safe' box (links to Google's Chrome pages) -->\n", 1)
open(p, "w").write(s)
print("OK   %s : passwords card + 'keeps you safe' box removed" % p)
PY
echo "=== Safety Hub trim complete ==="
