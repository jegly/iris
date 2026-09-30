#!/usr/bin/env bash
# Iris — the address-bar chip on chrome:// pages shows the REAL orb image, not a vector approximation
# (jegly 2026-09-27: the vector orb "looks like sharp lines rather than a nice soft blur"; verified against this checkout).
# Vector icons (.icon) can't draw gradients or blur; the orb is a soft conic gradient. OmniboxView::GetIcon
# (chrome/browser/ui/omnibox/omnibox_view.cc) turns the page's vector icon into an image; for the two Iris orb vector
# icons (omnibox::kChromeProductIcon / kProductChromeRefreshOldIcon, set by apply-orb-logo.sh) it now returns the orb
# PNG (IDR_PRODUCT_LOGO_32: 32 px, 64 px at 2x, from apply-rebrand-logos.sh) resized to the requested size.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/ui/omnibox/omnibox_view.cc"
s = open(p).read()
marker = "// Iris: chrome:// pages show the real orb"
if marker in s: print("SKIP already applied: " + p); sys.exit(0)
old = ("  if (controller()->edit_model()->ShouldShowCurrentPageIcon()) {\n"
       "    return ui::ImageModel::FromVectorIcon(\n"
       "        controller()->client()->GetVectorIcon(), color_current_page_icon,\n"
       "        dip_size);\n"
       "  }\n")
new = ("  if (controller()->edit_model()->ShouldShowCurrentPageIcon()) {\n"
       "    const gfx::VectorIcon& page_icon = controller()->client()->GetVectorIcon();\n"
       "    // Iris: chrome:// pages show the real orb image (a soft gradient that a\n"
       "    // vector icon cannot draw), resized to the requested size.\n"
       "    if (&page_icon == &omnibox::kChromeProductIcon ||\n"
       "        &page_icon == &omnibox::kProductChromeRefreshOldIcon) {\n"
       "      const gfx::ImageSkia* orb =\n"
       "          ui::ResourceBundle::GetSharedInstance().GetImageSkiaNamed(\n"
       "              IDR_PRODUCT_LOGO_32);\n"
       "      if (orb) {\n"
       "        return ui::ImageModel::FromImageSkia(\n"
       "            gfx::ImageSkiaOperations::CreateResizedImage(\n"
       "                *orb, skia::ImageOperations::RESIZE_BEST,\n"
       "                gfx::Size(dip_size, dip_size)));\n"
       "      }\n"
       "    }\n"
       "    return ui::ImageModel::FromVectorIcon(page_icon, color_current_page_icon,\n"
       "                                          dip_size);\n"
       "  }\n")
if s.count(old) != 1: die(p + ": current-page icon block changed (drift?)")
s = s.replace(old, new, 1)
anchor = '#include "chrome/browser/ui/omnibox/omnibox_edit_model.h"\n'
if s.count(anchor) != 1: die(p + ": include anchor missing")
s = s.replace(anchor, anchor +
    '#include "chrome/grit/theme_resources.h"        // Iris: orb image\n'
    '#include "skia/ext/image_operations.h"          // Iris\n'
    '#include "ui/base/resource/resource_bundle.h"   // Iris\n'
    '#include "ui/gfx/image/image_skia_operations.h"  // Iris\n', 1)
open(p, "w").write(s); print("OK   " + p + " : chrome:// chip shows the orb image")
PY
echo "=== omnibox orb image complete ==="
