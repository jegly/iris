#!/usr/bin/env bash
# Iris — new toolbar icons (jegly 2026-10-09: "refresh = e with dot / bookmark = f bookmark plus / main menu = h gear";
# stop = x for the reload button's other state; verified against 156.0.8078.11).
# Icons are Tabler Icons (MIT, github.com/tabler/tabler-icons v3.34.0) converted to Chromium's .icon vector format by
# tools/svg_to_icon.py (kept locally; the converted files live in patches/src and are copied here).
# REPLACES the content of the icons the toolbar really draws (this build has the "rounded icons" feature off, so the
# "...ChromeRefreshOld" / "...TouchOld" variants are used; both are replaced so touch mode matches):
#   reload (refresh-dot)   components/vector_icons/reload_chrome_refresh_old.icon, chrome/app/vector_icons/reload_touch_old.icon
#   stop (x)               chrome/app/vector_icons/navigate_stop_{chrome_refresh,touch}_old.icon
#   bookmark star          components/omnibox/browser/vector_icons/star_chrome_refresh_old.icon (bookmark-plus) and
#                          star_active_chrome_refresh_old.icon (filled bookmark = already bookmarked)
#   main menu (gear)       chrome/app/vector_icons/browser_tools_{chrome_refresh,touch}_old.icon
# ADDS (chrome/app/vector_icons/BUILD.gn -> kIris*Icon in vector_icons.h) for the Iris toolbar buttons:
#   iris_shield, iris_shield_off, iris_javascript (a </> code icon, not the JS-in-a-shield logo: it looked like the ad-block shield), iris_flame, iris_lock
# Back / forward / home keep their icons (not asked). Each replaced file must already exist (drift check).
# STATUS 2026-10-09: copy-tested only, NOT compile-proven (icons are compiled to C++ at build time: a bad .icon fails there).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
put() {  # replace an existing icon
  local f="$1" from="$DIR/src/$1"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  [ -f "$f" ] || { echo "ERROR: $f missing in the tree (upstream drift?)" >&2; exit 1; }
  if cmp -s "$from" "$f"; then echo "SKIP up to date: $f"; else cp "$from" "$f"; echo "OK   $f"; fi
}
add() {  # new icon
  local f="$1" from="$DIR/src/$1"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$f"; then echo "SKIP up to date: $f"; else cp "$from" "$f"; echo "OK   $f"; fi
}
put components/vector_icons/reload_chrome_refresh_old.icon
put chrome/app/vector_icons/reload_touch_old.icon
put chrome/app/vector_icons/navigate_stop_chrome_refresh_old.icon
put chrome/app/vector_icons/navigate_stop_touch_old.icon
put components/omnibox/browser/vector_icons/star_chrome_refresh_old.icon
put components/omnibox/browser/vector_icons/star_active_chrome_refresh_old.icon
put chrome/app/vector_icons/browser_tools_chrome_refresh_old.icon
put chrome/app/vector_icons/browser_tools_touch_old.icon
for n in shield shield_off javascript flame lock; do add chrome/app/vector_icons/iris_$n.icon; done
python3 - <<'PY'
import sys
B = "chrome/app/vector_icons/BUILD.gn"
s = open(B).read()
if '"iris_shield.icon"' in s:
    print("SKIP already applied: " + B); sys.exit(0)
a = '    "browser_tools_touch_old.icon",\n'
if s.count(a) != 1:
    sys.stderr.write("ERROR: %s: anchor not found exactly once (drift?)\n" % B); sys.exit(1)
add = "".join('    "iris_%s.icon",  # Iris\n' % n for n in ("flame", "javascript", "lock", "shield", "shield_off"))
open(B, "w").write(s.replace(a, a + add, 1)); print("OK   " + B + " : 5 Iris icons registered")
PY
echo "=== toolbar icons complete ==="
