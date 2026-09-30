#!/usr/bin/env bash
# Iris — visible "Chrome" wording that apply-rebrand.sh (Chromium -> Iris) does not catch (2026-09-28).
# English text only; message names unchanged, so no C++ rebuild (only the .pak files). Other locales keep the
# upstream translation until re-translated (TODO release: localization). "Chrome Web Store" / "Chrome Apps" stay
# (real product names). Strings for sign-in, sync, Safe Browsing, ChromeOS and Google services are left alone:
# Iris never shows them.
#  - Generic: "Chrome" -> "Iris" ("a Chrome" -> "an Iris") in the listed messages.
#  - Special: theme sub-label "Chrome Colors" -> "Iris Colors"; side panel "Chrome Panels" -> "Built-in panels";
#    auto-pin tab groups loses "created on any device" (there is no sync in Iris).
# Guarded; idempotent; fails loudly on drift (every listed message must exist).
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)

GENERIC = {
  "chrome/app/settings_strings.grdp": [
    "IDS_SETTINGS_HOME_AND_WORK_ADDRESS_REMOVE",
    "IDS_SETTINGS_HOME_ADDRESS_REMOVE_CONFIRMATION_DIALOG_TITLE",
    "IDS_SETTINGS_WORK_ADDRESS_REMOVE_CONFIRMATION_DIALOG_TITLE",
    "IDS_SETTINGS_NAME_EMAIL_ADDRESS_REMOVE_CONFIRMATION_DIALOG_TITLE",
    "IDS_SETTINGS_RESET_AUTOMATED_DIALOG_V2_TITLE",
    "IDS_SETTINGS_RESET_AUTOMATED_DIALOG_V2_BODY",
    "IDS_SETTINGS_SEARCH_ENGINES_SITE_SEARCH_EXPLANATION",
    "IDS_SETTINGS_SEARCH_ENGINES_EXTENSION_ENGINES_EXPLANATION",
    "IDS_SETTINGS_SITE_SETTINGS_PDF_DOWNLOAD_PDFS",
    "IDS_SETTINGS_SITE_SETTINGS_BLOCK_AUTOPLAY",
  ],
  "chrome/app/generated_resources.grd": [
    "IDS_NEAR_OOM_REDUCTION_MESSAGE_DESCRIPTION",
    "IDS_KILLED_TAB_BY_OOM_MESSAGE",
    "IDS_EXTENSION_EXTERNAL_INSTALL_ALERT_BUBBLE_HEADING_APP",
    "IDS_EXTENSION_EXTERNAL_INSTALL_ALERT_BUBBLE_HEADING_EXTENSION",
    "IDS_EXTENSION_EXTERNAL_INSTALL_ALERT_BUBBLE_HEADING_THEME",
    "IDS_DEV_TOOLS_CONNECTION_DIALOG_MESSAGE_PART_1",
    "IDS_UTILITY_PROCESS_FILE_UTILITY_NAME",
    "IDS_SERVICE_PROCESS_DOCUMENT_ANALYSIS_NAME",
    "IDS_NTP_CUSTOMIZE_NO_BACKGROUND_LABEL",
    "IDS_NTP_CUSTOMIZE_CHROME_RESET_TO_CLASSIC_CHROME_COMPLETE",
    "IDS_SHOW_CUSTOMIZE_CHROME_SIDE_PANEL",
    "IDS_INTENT_PICKER_BUBBLE_VIEW_STAY_IN_CHROME",
    "IDS_MEDIA_TAB_CAPTURE_NOTIFICATION_TEXT",
    "IDS_MEDIA_TAB_CAPTURE_WITH_AUDIO_NOTIFICATION_TEXT",
    "IDS_CONTROLLED_BY_AUTOMATION",
    "IDS_BAD_FLAGS_FROM_FILE_WARNING_MESSAGE",
    "IDS_EXTENSIONS_BLOCKLISTED_POTENTIALLY_UNWANTED",
    "IDS_TRIGGERED_RESET_PROFILE_SETTINGS_EXPLANATION",
    "IDS_ZOOMLEVELS_CHROME_ERROR_PAGES_LABEL",
    "IDS_TUTORIAL_CUSTOMIZE_CHROME_START_TUTORIAL_IPH",
    "IDS_TUTORIAL_CUSTOMIZE_CHROME_OPEN_SIDE_PANEL",
    "IDS_TUTORIAL_CUSTOMIZE_CHROME_SUCCESS_BODY",
    "IDS_EXTENSIONS_ZERO_STATE_PROMO_CUSTOM_ACTION_IPH_DESCRIPTION",
  ],
}
SPECIAL = {
  "chrome/app/settings_strings.grdp": {
    "IDS_SETTINGS_CHROME_COLORS": ("Chrome Colors", "Iris Colors"),
    "IDS_SETTINGS_SIDE_PANEL_ALIGNMENT_CHROME_PANELS": ("Chrome Panels", "Built-in panels"),
    "IDS_SETTINGS_AUTO_PIN_NEW_TAB_GROUPS": ("Automatically pin new tab groups created on any device to the bookmarks bar",
                                             "Automatically pin new tab groups to the bookmarks bar"),
  },
}
WORD = re.compile(r"\b(an? )?Chrome\b(?! Web Store)(?! [Aa]pps?\b)")
def generic(text):
    return WORD.sub(lambda m: ("an " if m.group(1) else "") + "Iris", text)

def msg_re(name):
    # The text part only (after the opening tag), so attributes like desc="... Chrome ..." stay untouched.
    return re.compile(r'(<message name="%s"[^>]*>)(.*?)(</message>)' % re.escape(name), re.S)

files = set(GENERIC) | set(SPECIAL)
for p in sorted(files):
    s = open(p).read()
    changed = 0
    for name in GENERIC.get(p, []):
        r = msg_re(name)
        if not r.search(s): die("%s: message %s not found (drift?)" % (p, name))
        def fix(m):
            body = re.sub(r"(<ph[^>]*>.*?</ph>)|([^<]+)",
                          lambda x: x.group(1) or generic(x.group(2)), m.group(2), flags=re.S)
            return m.group(1) + body + m.group(3)
        s2 = r.sub(fix, s)
        if s2 != s: changed += 1; s = s2
    for name, (old, new) in SPECIAL.get(p, {}).items():
        r = msg_re(name)
        m = r.search(s)
        if not m: die("%s: message %s not found (drift?)" % (p, name))
        if new in m.group(2): continue
        if old not in m.group(2): die("%s: %s text changed upstream (drift?)" % (p, name))
        s = r.sub(lambda x: x.group(1) + x.group(2).replace(old, new) + x.group(3), s)
        changed += 1
    if changed:
        open(p, "w").write(s); print("OK   %s : %d messages reworded" % (p, changed))
    else:
        print("SKIP already applied: " + p)
PY
echo "=== visible Chrome wording -> Iris complete ==="
