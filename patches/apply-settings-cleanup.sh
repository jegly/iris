#!/usr/bin/env bash
# Iris — desktop Settings / new tab clean-up (jegly 2026-10-09: "security check needs to be removed ... along with the web
# store showing on the home page by default ... need to hide the privacy / security check up that's there on start in
# settings"; verified against 156.0.8078.11).
#  1. Safety Hub ("Safety check": "Iris regularly checks to make sure your browser has the safest settings...") gone from
#     Settings: createPageVisibility() (page_visibility.ts) returns {safetyHub: false} for normal profiles, the same
#     switch Chromium uses for guest profiles. The entry card on Privacy and security, the /safetyCheck route and the
#     page disappear together (route.ts and privacy_page_index check visibility.safetyHub).
#  2. Privacy Guide ("review key privacy and security controls" promo on top of Settings, its row and page): settings_ui.cc
#     sets showPrivacyGuide = false, as Chromium does for managed and child profiles. It walks through Google services
#     and Safe Browsing levels that Iris already decides.
#  3. "Web Store" shortcut on the new tab page: the only pre-filled top site (top_sites_factory.cc) is skipped when the
#     HideWebStoreIcon pref is true; Iris registers it as true by default (browser_ui_prefs.cc). The Web Store itself
#     still works (extensions are allowed).
# Desktop only (all three files are desktop code). STATUS 2026-10-09: copy-tested only, NOT compile-proven.
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
edit("chrome/browser/resources/settings/page_visibility.ts",
     "  if (!loadTimeData.getBoolean('isGuest')) {\n    return undefined;\n  }\n",
     "  if (!loadTimeData.getBoolean('isGuest')) {\n"
     "    // Iris: no Safety Hub (apply-settings-cleanup.sh).\n"
     "    return {safetyHub: false};\n  }\n",
     "Iris: no Safety Hub (apply-settings-cleanup.sh)", "Safety Hub hidden")
edit("chrome/browser/ui/webui/settings/settings_ui.cc",
     "  bool show_privacy_guide =\n"
     "      base::FeatureList::IsEnabled(features::kPrivacyGuideForceAvailable) ||\n"
     "      (!ShouldDisplayManagedUi(profile) && !profile->IsChild());\n",
     "  // Iris: no Privacy Guide, promo or page (apply-settings-cleanup.sh).\n"
     "  bool show_privacy_guide = false;\n",
     "Iris: no Privacy Guide", "Privacy Guide hidden")
edit("chrome/browser/ui/browser_ui_prefs.cc",
     "  registry->RegisterBooleanPref(policy::policy_prefs::kHideWebStoreIcon, false);\n",
     "  // Iris: no \"Web Store\" shortcut on the new tab page (apply-settings-cleanup.sh).\n"
     "  registry->RegisterBooleanPref(policy::policy_prefs::kHideWebStoreIcon, true);\n",
     "kHideWebStoreIcon, true);", "Web Store tile hidden")
PY
echo "=== settings clean-up complete ==="
