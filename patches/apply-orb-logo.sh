#!/usr/bin/env bash
# Iris — tab/toolbar/infobar product logo = the orb (approved by jegly 2026-09-26; verified 2026-09-26).
# Chromium's product vector icons (kProductIcon / kProductRefreshIcon: About, infobars, first-run dialogs, menus)
# come from components/vector_icons/${branding_path_component}/product{,_refresh}.icon; Iris is unbranded ->
# branding_path_component = "chromium" (build/config/chrome_build.gni). Replaced with:
#   product.icon          <- branding/icon/product_orb_24.icon      single-colour disc (themed by the UI)
#   product_refresh.icon  <- branding/icon/product_refresh_orb.icon four-colour sectors approximating the gradient
#                            orb (preview: branding/icon/product_refresh_orb_preview.svg)
# .icon cannot express gradients; the raster app icons (apply-rebrand*.sh) keep the real gradient.
# Idempotent (cmp); fails if the target files are missing (drift).
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ICON="$DIR/../branding/icon"
cd "$SRC"
grep -q 'branding_path_component = "chromium"' build/config/chrome_build.gni \
  || { echo "ERROR: build/config/chrome_build.gni no longer maps unbranded builds to 'chromium'" >&2; exit 1; }
put() {
  local from="$1" to="$2"
  [ -f "$to" ] || { echo "ERROR: $to missing (drift?)" >&2; exit 1; }
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$to"; then echo "SKIP already applied: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
}
put "$ICON/product_orb_24.icon"      components/vector_icons/chromium/product.icon
put "$ICON/product_refresh_orb.icon" components/vector_icons/chromium/product_refresh.icon
echo "=== orb product logo complete ==="
