#!/usr/bin/env bash
# Iris — ignore the desktop accent colour on Linux (jegly 2026-09-27: "when opening a new tab the screen flashes a
# weird brown colour"; verified against this checkout).
# ui::NativeTheme copies the OS accent (GNOME/Ubuntu: orange by default) and colour source "accent" into the base
# colour key (ui/native_theme/native_theme.cc). Surfaces built from that key without the profile's theme (e.g. a new
# tab's first paint) got a palette generated from the orange (dark brown), and the Catppuccin mixer
# (apply-catppuccin-default.sh) rightly skips non-baseline sources. Iris uses its own palette, so on Linux the
# desktop accent is ignored: no user colour, source baseline. Colours picked in Iris's own Customize panel still work.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "ui/native_theme/native_theme.cc"
s = open(p).read()
marker = "// Iris: ignore the desktop accent colour"
if marker in s: print("SKIP already applied: " + p); sys.exit(0)
old = ("  const auto new_user_color = os_settings_provider.AccentColor();\n"
       "  const auto new_scheme_variant = os_settings_provider.SchemeVariant();\n"
       "  const auto new_preferred_color_source =\n"
       "      os_settings_provider.PreferredColorSource();\n")
new = ("#if BUILDFLAG(IS_LINUX)\n"
       "  // Iris: ignore the desktop accent colour; Iris uses its own palette\n"
       "  // (a GNOME orange accent otherwise tints new surfaces brown).\n"
       "  const std::optional<SkColor> new_user_color = std::nullopt;\n"
       "  const auto new_preferred_color_source =\n"
       "      ColorProviderKey::UserColorSource::kBaseline;\n"
       "#else\n"
       "  const auto new_user_color = os_settings_provider.AccentColor();\n"
       "  const auto new_preferred_color_source =\n"
       "      os_settings_provider.PreferredColorSource();\n"
       "#endif\n"
       "  const auto new_scheme_variant = os_settings_provider.SchemeVariant();\n")
if s.count(old) != 1: sys.stderr.write("ERROR: %s: accent block changed (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : desktop accent ignored on Linux")
PY
echo "=== no desktop accent complete ==="
