#!/usr/bin/env bash
# Iris — Phase B9 part 2: the Iris palettes in Chromium's Customize colour picker (jegly 2026-09-27: "build the themes
# into chromium's already existing theme picker"). GetChromeColors() (theme_color_picker_handler.cc) lists the palettes
# of ui/color/iris_palettes.h (branding/gen_palettes.py: Catppuccin x4, Notas, Ptyxis) before Chrome's own colours.
# Each swatch carries the palette's reserved seed; picking it stores that seed as the user colour, and the Iris mixer
# (apply-catppuccin-default.sh) applies the palette exactly. Needs apply-catppuccin-default.sh (copies the header).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/ui/webui/cr_components/theme_color_picker/theme_color_picker_handler.cc"
s = open(p).read()
if "iris::kPaletteCount" in s: print("SKIP already applied: " + p); sys.exit(0)
old = ("  std::vector<theme_color_picker::mojom::ChromeColorPtr> colors;\n"
       "  for (const auto& color_info : kDynamicCustomizeChromeColors) {\n")
new = ("  std::vector<theme_color_picker::mojom::ChromeColorPtr> colors;\n"
       "  // Iris (B9): the Iris palettes first; the colour mixer applies them exactly.\n"
       "  for (size_t i = 0; i < ui::iris::kPaletteCount; ++i) {\n"
       "    const ui::iris::Palette& palette = ui::iris::kPalettes[i];\n"
       "    auto color = theme_color_picker::mojom::ChromeColor::New();\n"
       "    color->name = palette.name;\n"
       "    color->seed = ui::iris::IrisPaletteSeed(i);\n"
       "    color->background = palette.colors[ui::iris::kTokenPrimary];\n"
       "    color->foreground = palette.colors[ui::iris::kTokenBase];\n"
       "    color->base = palette.colors[ui::iris::kTokenBaseContainer];\n"
       "    color->variant = ui::mojom::BrowserColorVariant::kTonalSpot;\n"
       "    colors.push_back(std::move(color));\n"
       "  }\n"
       "  for (const auto& color_info : kDynamicCustomizeChromeColors) {\n")
if s.count(old) != 1: die(p + ": GetChromeColors changed (drift?)")
s = s.replace(old, new, 1)
a = '#include "chrome/browser/ui/webui/cr_components/theme_color_picker/theme_color_picker_handler.h"\n'
if s.count(a) != 1: die(p + ": own include not found")
s = s.replace(a, a + '#include "ui/color/iris_palettes.h"  // Iris (B9)\n', 1)
open(p, "w").write(s); print("OK   " + p + " : Iris palettes in the colour picker")
PY
echo "=== palettes in the colour picker complete ==="
