#!/usr/bin/env bash
# Iris — Android: the Iris orb instead of the Chromium logo for pages without their own icon (jegly 2026-10-08: "new
# tab still shows the Chromium logo in the tab strip"; verified against 156.0.8078.11).
# chrome/browser/ui/android/favicon/java/res/drawable-*/chromelogo16.png is the shared 16 dp fallback used by the tab
# strip / grid (TabListFaviconProvider), Page Info, the custom-tab toolbar, FaviconHelper and the web-contents
# delegate. Replaced (same name, every density) with the orb made from branding/icon/iris-master-square.png
# (16/24/32/48/64 px, transparent). No Java changes.
# Guarded (copies only when different); idempotent.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  rel="chrome/browser/ui/android/favicon/java/res/drawable-$d/chromelogo16.png"
  from="$DIR/src/$rel"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  [ -f "$rel" ] || { echo "ERROR: $rel not found (drift?)" >&2; exit 1; }
  if cmp -s "$from" "$rel"; then echo "SKIP up to date: $rel"; else cp "$from" "$rel"; echo "OK   $rel"; fi
done
echo "=== Android orb favicon complete ==="
