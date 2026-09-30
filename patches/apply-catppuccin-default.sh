#!/usr/bin/env bash
# Iris — Phase B9 part 1: dark mode by default + Catppuccin Mocha colours for the default dark UI (jegly 2026-09-26;
# verified against this checkout 2026-09-27). Desktop only (Android theming = Phase C).
# 1. Dark by default: prefs::kBrowserColorScheme default kSystem -> kDark (chrome/browser/themes/theme_service.cc).
#    Users can still pick Light / Device in Settings -> Appearance -> Mode.
# 2. Catppuccin Mocha (https://catppuccin.com/palette, MIT), accent GREEN (jegly 2026-09-27: no blue highlight),
#    secondary teal: an Iris mixer right after AddSysColorMixer in
#    ui/color/color_mixers.cc sets the Material "sys" tokens (kColorSys*). Every later mixer (core, UI, Chrome's browser
#    mixers) and the built-in pages (chrome://theme/colors.css --color-sys-*) derive from those tokens, so the frame,
#    tabs, toolbar, omnibox, menus, dialogs and Settings/History/Downloads all follow.
#    Applied ONLY for: dark mode, normal contrast, no installed theme and no GTK/Qt theme (both = custom_theme), no colour picked
#    in "Customize Chrome". Any user choice therefore still wins; high contrast is never overridden.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
IRIS_PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
IRIS_PATCH_DIR="$IRIS_PATCH_DIR" python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

edit("chrome/browser/themes/theme_service.cc",
     "  registry->RegisterIntegerPref(\n"
     "      prefs::kBrowserColorScheme,\n"
     "      std::to_underlying(ThemeService::BrowserColorScheme::kSystem));\n",
     "  registry->RegisterIntegerPref(\n"
     "      prefs::kBrowserColorScheme,\n"
     "      std::to_underlying(ThemeService::BrowserColorScheme::kDark));  // Iris\n",
     "BrowserColorScheme::kDark));  // Iris", "dark mode by default")

# 1b. (2026-09-27, found in jegly's first look: Settings showed "Theme: GTK") On Linux the default theme is GTK
#     (ui::GetDefaultSystemTheme()), which (a) is excluded from the Catppuccin mixer below and (b) forces the colour
#     scheme to follow the system (ThemeServiceAuraLinux::GetBrowserColorScheme). Iris defaults to Classic; GTK/Qt stay
#     one click away (Settings -> Appearance -> Theme).
edit("chrome/browser/themes/theme_service.cc",
     "  registry->RegisterIntegerPref(prefs::kSystemTheme,\n"
     "                                static_cast<int>(ui::GetDefaultSystemTheme()));\n",
     "  registry->RegisterIntegerPref(\n"
     "      prefs::kSystemTheme,\n"
     "      static_cast<int>(ui::SystemTheme::kDefault));  // Iris: Classic, not GTK\n",
     "ui::SystemTheme::kDefault));  // Iris: Classic", "Classic (not GTK) theme by default on Linux")

# Catppuccin Mocha
C = dict(crust=0x11111B, mantle=0x181825, base=0x1E1E2E, surface0=0x313244, surface1=0x45475A, surface2=0x585B70,
         overlay0=0x6C7086, overlay1=0x7F849C, subtext0=0xA6ADC8, subtext1=0xBAC2DE, text=0xCDD6F4,
         lavender=0xB4BEFE, blue=0x89B4FA, green=0xA6E3A1, teal=0x94E2D5, mauve=0xCBA6F7, red=0xF38BA8, pink=0xF5C2E7,
         # blends of the palette for the Material surface/container steps (base -> surface0), accent containers
         s1=0x232335, s2=0x28283C, s3=0x2C2D41, s5=0x363849, blue_container=0x34405E, mauve_container=0x3E3656,
         red_container=0x4A2A3A, latte_blue=0x1E66F5, elevated=0x3A3B50,
         green_container=0x52645E, latte_green=0x40A02B)
tokens = [
  ("Header", "crust"), ("HeaderInactive", "crust"), ("HeaderContainer", "mantle"),
  ("HeaderContainerInactive", "mantle"), ("OnHeaderPrimary", "text"), ("OnHeaderPrimaryInactive", "subtext0"),
  ("OnHeaderDivider", "surface0"), ("OnHeaderDividerInactive", "surface0"),
  ("Base", "base"), ("BaseContainer", "surface0"), ("BaseContainerElevated", "elevated"),
  ("BaseTonalContainer", "surface0"), ("OnBaseTonalContainer", "text"),
  ("Surface", "base"), ("Surface1", "s1"), ("Surface2", "s2"), ("Surface3", "s3"), ("Surface4", "surface0"),
  ("Surface5", "s5"), ("SurfaceVariant", "surface0"), ("OmniboxContainer", "surface0"),
  ("OnSurface", "text"), ("OnSurfacePrimary", "text"), ("OnSurfaceSecondary", "subtext1"),
  ("OnSurfaceSubtle", "subtext0"), ("OnSurfaceVariant", "subtext0"),
  ("Primary", "green"), ("OnPrimary", "crust"), ("PrimaryContainer", "green_container"),
  ("OnPrimaryContainer", "text"), ("Secondary", "teal"), ("OnSecondary", "crust"),
  ("SecondaryContainer", "surface0"), ("OnSecondaryContainer", "text"), ("Tertiary", "mauve"),
  ("OnTertiary", "crust"), ("TertiaryContainer", "mauve_container"), ("OnTertiaryContainer", "text"),
  ("Error", "red"), ("OnError", "crust"), ("ErrorContainer", "red_container"), ("OnErrorContainer", "pink"),
  ("TonalContainer", "surface0"), ("OnTonalContainer", "text"), ("NeutralContainer", "surface0"),
  ("Outline", "overlay0"), ("NeutralOutline", "surface2"), ("TonalOutline", "overlay1"), ("Divider", "surface0"),
  ("InverseSurface", "text"), ("InverseOnSurface", "base"), ("InversePrimary", "latte_green"),
  ("StateFocusRing", "green"),
]
body = "".join("  mixer[kColorSys%s] = {SkColorSetRGB(0x%02X, 0x%02X, 0x%02X)};  // %s\n"
               % (t, (C[c] >> 16) & 255, (C[c] >> 8) & 255, C[c] & 255, c) for t, c in tokens)
fn = ("namespace {\n\n"
      "// Iris: Catppuccin Mocha by default + the Iris palettes (B9). Palettes come from\n"
      "// ui/color/iris_palettes.h (generated by branding/gen_palettes.py) and are picked\n"
      "// in Customize (reserved seed colours). Sets the Material sys tokens, from which\n"
      "// all later mixers and the WebUI colors derive. Mocha applies only to the plain\n"
      "// dark theme; an installed/GTK/Qt theme (custom_theme), an ordinary picked\n"
      "// color, grey, device colors or high contrast keep Chromium's behavior.\n"
      "void AddIrisCatppuccinMochaMixer(ColorProvider* provider,\n"
      "                                 const ColorProviderKey& key) {\n"
      "  if (key.contrast_mode == ColorProviderKey::ContrastMode::kHigh ||\n"
      "      key.custom_theme) {\n"
      "    return;\n"
      "  }\n"
      "  const iris::Palette* palette = iris::PaletteForSeed(key.user_color);\n"
      "  if (!palette) {\n"
      "    if (key.color_mode != ColorProviderKey::ColorMode::kDark ||\n"
      "        key.user_color_source !=\n"
      "            ColorProviderKey::UserColorSource::kBaseline) {\n"
      "      return;\n"
      "    }\n"
      "    palette = &iris::kPalettes[iris::kDefaultPalette];\n"
      "  }\n"
      "  ColorMixer& mixer = provider->AddMixer();\n"
      "  for (size_t i = 0; i < std::size(iris::kPaletteTokens); ++i) {\n"
      "    mixer[iris::kPaletteTokens[i]] = {palette->colors[i]};\n"
      "  }\n"
      "}\n\n"
      "}  // namespace\n\n")

# 3. (2026-09-27, measured over DevTools) Settings ignores theme colours unless the in-development
#    Settings/WebUI "Refresh 2026" features are on: it then only adds chrome://theme/colors.css (addThemedColors_) and
#    starts the live colour updater; otherwise every --cr-* colour falls back to fixed Chrome greys (#292a2d cards).
#    Iris always loads the themed colours, WITHOUT turning on the unfinished redesign.
edit("chrome/browser/resources/settings/settings_ui/settings_ui.ts",
     "    const enableThemedColors =\n"
     "        loadTimeData.getString('webuiRefresh2026') !== '' ||\n",
     "    // Iris: always use the theme colours (Catppuccin by default, or the user's\n"
     "    // pick), without the unfinished Refresh 2026 layout.\n"
     "    const enableThemedColors = true ||\n"
     "        loadTimeData.getString('webuiRefresh2026') !== '' ||\n",
     "const enableThemedColors = true ||", "Settings uses theme colours")

# 4. In dark mode the built-in pages' page/card/menu colours are fixed Google greys (cr_shared_vars.css dark block,
#    md_colors.css) unless the unfinished Refresh 2026 attribute is set. Iris maps them to the theme tokens (from
#    chrome://theme/colors.css, loaded by step 3), keeping the old greys as fallbacks.
edit("ui/webui/resources/cr_elements/cr_shared_vars.css",
     "html[webui-refresh-2026] {\n  --cr-card-background-color: var(--color-webui-card-background);\n}\n",
     "html[webui-refresh-2026] {\n  --cr-card-background-color: var(--color-webui-card-background);\n}\n\n"
     "/* Iris: built-in pages follow the theme colours in dark mode (Catppuccin Mocha by\n"
     " * default, or the user's pick); the Google greys stay as fallbacks. */\n"
     "@media (prefers-color-scheme: dark) {\n"
     "  html:not([webui-refresh-2026]) {\n"
     "    --md-background-color: var(--color-sys-base, rgb(32, 33, 36));\n"
     "    --cr-card-background-color: var(--color-sys-base-container,\n"
     "        var(--google-grey-900-white-4-percent));\n"
     "    --cr-menu-background-color: var(--color-sys-base-container-elevated,\n"
     "        var(--google-grey-900));\n"
     "    --cr-separator-color: var(--color-sys-divider, rgba(255, 255, 255, .1));\n"
     "  }\n"
     "}\n",
     "Iris: built-in pages follow the theme colours", "WebUI dark greys -> theme tokens")

# 5. Side-menu (Settings sidebar etc.) dark colours are fixed Google values, e.g. the selected item = Google Blue 300.
#    Iris points them at the theme tokens (old values as fallbacks): selected item = accent (green) with dark text.
edit("ui/webui/resources/cr_elements/cr_nav_menu_item_style_lit.css",
     "    --cr-nav-menu-item-color: white;\n"
     "    --cr-nav-menu-item-color-selected: var(--google-grey-900);\n"
     "\n"
     "    --cr-nav-menu-item-background-color-hover: var(--google-grey-800);\n"
     "    --cr-nav-menu-item-background-color-selected: var(--google-blue-300);\n"
     "\n"
     "    --cr-nav-menu-item-icon-color: var(--google-grey-500);\n"
     "    --cr-nav-menu-item-icon-color-hover: white;\n"
     "    --cr-nav-menu-item-icon-color-selected: black;\n",
     "    /* Iris: theme colours (apply-catppuccin-default.sh), Google values as fallbacks. */\n"
     "    --cr-nav-menu-item-color: var(--color-sys-on-surface, white);\n"
     "    --cr-nav-menu-item-color-selected: var(--color-sys-on-primary,\n"
     "        var(--google-grey-900));\n"
     "\n"
     "    --cr-nav-menu-item-background-color-hover: var(--color-sys-base-container,\n"
     "        var(--google-grey-800));\n"
     "    --cr-nav-menu-item-background-color-selected: var(--color-sys-primary,\n"
     "        var(--google-blue-300));\n"
     "\n"
     "    --cr-nav-menu-item-icon-color: var(--color-sys-on-surface-subtle,\n"
     "        var(--google-grey-500));\n"
     "    --cr-nav-menu-item-icon-color-hover: var(--color-sys-on-surface, white);\n"
     "    --cr-nav-menu-item-icon-color-selected: var(--color-sys-on-primary, black);\n",
     "Iris: theme colours (apply-catppuccin-default.sh)", "side-menu colours -> theme tokens")

import shutil, filecmp, os
src_h = os.path.join(os.environ["IRIS_PATCH_DIR"], "src/ui/color/iris_palettes.h")
if not os.path.exists("ui/color/iris_palettes.h") or not filecmp.cmp(src_h, "ui/color/iris_palettes.h", shallow=False):
    shutil.copyfile(src_h, "ui/color/iris_palettes.h"); print("OK   ui/color/iris_palettes.h (palette table)")
else:
    print("SKIP up to date: ui/color/iris_palettes.h")
p = "ui/color/color_mixers.cc"
edit(p, '#include "ui/color/sys_color_mixer.h"\n',
     '#include "ui/color/sys_color_mixer.h"\n'
     '#include "third_party/skia/include/core/SkColor.h"  // Iris: Catppuccin\n'
     '#include "ui/color/color_id.h"                      // Iris\n'
     '#include "ui/color/color_mixer.h"                   // Iris\n'
     '#include "ui/color/color_provider.h"                // Iris\n'
     '#include "ui/color/color_provider_key.h"            // Iris\n'
     '#include "ui/color/system_theme.h"                  // Iris\n',
     "// Iris: Catppuccin", "includes")
edit(p, '#include "ui/color/color_provider_key.h"            // Iris\n',
     '#include "ui/color/color_provider_key.h"            // Iris\n'
     '#include "ui/color/color_recipe.h"                  // Iris: mixer[id] = {...}\n',
     'color_recipe.h"                  // Iris', "include color_recipe.h")
edit(p, '#include "ui/color/color_recipe.h"                  // Iris: mixer[id] = {...}\n',
     '#include "ui/color/color_recipe.h"                  // Iris: mixer[id] = {...}\n'
     '#include "ui/color/iris_palettes.h"                 // Iris (B9)\n',
     'ui/color/iris_palettes.h"', "include palette table")
src = open(p).read()
begin = src.find("namespace {\n\n// Iris: Catppuccin Mocha")
if begin >= 0:  # already present: replace it with the current version (idempotent)
    end = src.index("}  // namespace\n\n", begin) + len("}  // namespace\n\n")
    if src[begin:end] == fn: print("SKIP already applied: %s (Catppuccin Mocha mixer)" % p)
    else: open(p, "w").write(src[:begin] + fn + src[end:]); print("OK   %s : Catppuccin Mocha mixer updated" % p)
else:
    edit(p, "namespace ui {\n\nvoid AddColorMixers(",
         "namespace ui {\n\n" + fn + "void AddColorMixers(",
         "AddIrisCatppuccinMochaMixer(ColorProvider*", "Catppuccin Mocha mixer")
src = open(p).read()
dbg = '\n#include "base/logging.h"  // IRISDBG temporary\n'
if dbg in src: open(p, "w").write(src.replace(dbg, "\n", 1)); print("OK   %s : removed temporary debug include" % p)
edit(p, "  AddSysColorMixer(provider, key);\n",
     "  AddSysColorMixer(provider, key);\n"
     "#if !BUILDFLAG(IS_ANDROID)\n"
     "  AddIrisCatppuccinMochaMixer(provider, key);  // Iris\n"
     "#endif\n",
     "AddIrisCatppuccinMochaMixer(provider, key);", "mixer runs right after the sys tokens")
s = open(p).read()
if "build/build_config.h" not in s and "buildflag" not in s.lower():
    die(p + ": BUILDFLAG(IS_ANDROID) needs build/build_config.h (not included?)")
PY
echo "=== Catppuccin Mocha + dark default complete ==="
