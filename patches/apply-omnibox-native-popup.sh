#!/usr/bin/env bash
# Iris — the address-bar dropdown uses Chromium's native (Views) popup, not the WebUI page (jegly 2026-10-10: the
# corner specks were "still not fixed"; verified against 156.0.8078.11).
# In M156 the dropdown is a WebUI page (chrome/browser/ui/omnibox/omnibox_next_features.cc kWebUIOmniboxPopup,
# ENABLED): a WebView with its own rounded corners inside the native frame's rounded layer. Where the two curves
# differ, a few semi-transparent pixels let the toolbar colour through (visible with contrasting Theme editor
# colours). With the feature off, LocationBarView falls back to the native OmniboxPopupViewViews, the path Chromium
# still uses for app windows, DevTools and pop-up windows; its corners are covered by apply-omnibox-corner-fix.sh.
# Also: no separate WebUI renderer starts each time the address bar opens (that page mainly hosts Google's AI Mode
# compose box, which Iris removes). Colours: the native popup uses kColorOmniboxResults* (Theme editor "Suggestions
# list").
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (omnibox_next_features.o). Not seen.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
f=chrome/browser/ui/omnibox/omnibox_next_features.cc
old='BASE_FEATURE(kWebUIOmniboxPopup, ENABLED);'
new='BASE_FEATURE(kWebUIOmniboxPopup, DISABLED);  // Iris: native popup (apply-omnibox-native-popup.sh)'
if grep -Fq "$new" "$f"; then echo "SKIP already applied: $f"
elif [ "$(grep -Fc "$old" "$f")" = 1 ]; then
  OLD="$old" NEW="$new" perl -0777 -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/' "$f"
  grep -Fq "$new" "$f" && echo "OK   $f : WebUI dropdown off (native popup)" || { echo "ERROR: edit failed" >&2; exit 1; }
else echo "ERROR: $f: '$old' not found exactly once (drift?)" >&2; exit 1; fi
echo "=== native address-bar dropdown complete ==="
