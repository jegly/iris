#!/usr/bin/env bash
# Iris — Android rebrand (verified against checkout 2026-09-26). Desktop rebrand (apply-rebrand.sh) covers
# the shared product strings (chromium_strings.grd etc.); this covers what is Android-only:
#  - chrome/android/java/res_chromium_base/values/channel_constants.xml: app_name + 3 widget titles
#    ("Chromium", "Chromium bookmarks/search/quick action search") -> Iris
#  - launcher icons (res_chromium_base/mipmap-*/): app_icon.png (legacy, 48-192px),
#    layered_app_icon.png (adaptive foreground over white, orb at 48% like Chromium's logo),
#    layered_app_icon_background.png (round-launcher variant, opaque white + orb)
#  - drawable/themed_app_icon.xml: Android 13+ monochrome silhouette -> plain circle (orb)
# Source assets: ~/Documents/iris/branding/icon/generated-android/ (generated from iris-master-square.png;
# sizes match Chromium's exactly). android_chrome_strings.grd's 3 "Chromium" hits are a translator
# description + two <ex> placeholders (not user-visible) -> intentionally untouched.
# Package name is a gn arg: chrome_public_manifest_package = "io.jegly.iris" (build/args-android.gn).
# Guarded; idempotent.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
ASSETS="$(cd "$(dirname "$0")/.." && pwd)/branding/icon/generated-android"
cd "$SRC"
R=chrome/android/java/res_chromium_base
[ -d "$ASSETS" ] || { echo "ERROR: missing $ASSETS" >&2; exit 1; }

# 1) strings
C=$R/values/channel_constants.xml
for pair in \
  '<string name="app_name" translatable="false">Chromium</string>|<string name="app_name" translatable="false">Iris</string>' \
  '<string name="bookmark_widget_title" translatable="false">Chromium bookmarks</string>|<string name="bookmark_widget_title" translatable="false">Iris bookmarks</string>' \
  '<string name="search_widget_title" translatable="false">Chromium search</string>|<string name="search_widget_title" translatable="false">Iris search</string>' \
  '<string name="quick_action_search_widget_title" translatable="false">Chromium quick action search</string>|<string name="quick_action_search_widget_title" translatable="false">Iris quick action search</string>'; do
  old=${pair%%|*}; new=${pair#*|}
  if grep -Fq -- "$new" "$C"; then echo "SKIP $new"
  elif [ "$(grep -Fc -- "$old" "$C")" -eq 1 ]; then
    perl -0777 -pi -e 'BEGIN{$o=shift;$n=shift} s/\Q$o\E/$n/' "$old" "$new" "$C"; echo "OK   $C : ${new:0:70}"
  else echo "ERROR: not found in $C: $old" >&2; exit 1; fi
done

# 2) icons + themed icon (replace only existing upstream files — never add new resource names)
n=0
for f in $(cd "$ASSETS" && find . -type f \( -name '*.png' -o -name '*.xml' \) | sed 's|^\./||' | sort); do
  dst="$R/$f"
  [ -f "$dst" ] || { echo "ERROR: $dst does not exist upstream (resource layout drifted?)" >&2; exit 1; }
  if cmp -s "$ASSETS/$f" "$dst"; then :; else cp "$ASSETS/$f" "$dst"; n=$((n+1)); fi
done
echo "OK   icons: $n file(s) replaced (0 = already applied)"
echo "=== Android rebrand complete ==="
