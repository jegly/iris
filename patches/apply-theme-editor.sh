#!/usr/bin/env bash
# Iris — Theme editor (0.0.0.7 item 11, jegly 2026-10-10: "theme the top bar like individual components, change
# accent colours, change font colours etc, highly customisable all under appearance, like Firefox Color"; + new tab
# page background and side panel; desktop only; verified against 156.0.8078.11).
#  - Settings > Appearance > "Theme editor" (new sub-page /themeEditor, Lit element iris_theme_editor_page.ts):
#      groups Whole browser (accent, text, secondary text, background, menus/dialogs/cards), Title bar and tabs,
#      Toolbar, Address bar, Pages and panels (new tab page, side panel); each row: colour picker, "From your palette"
#      when unset, Reset; "Reset all". Websites: "Recolour websites" + brightness/contrast (apply-web-recolor.sh).
#      Your themes: save the current colours under a name, use, delete. Share: "Copy my code" / "Apply code"
#      (IRIS-THEME-1:<base64 JSON>, colours only, nothing uploaded).
#  - chrome/browser/ui/color/iris_theme_mixer.{h,cc}: the colours, added after Chrome's mixers and before the glass
#    mixer. Whole-browser colours override the Material sys tokens (references resolve against the final mixer, so
#    derived colours follow); the others set one part of the window. Skipped in high-contrast mode.
#  - ThemeService: pref iris.theme.custom -> browser-wide state, colour-provider cache dropped, windows repaint (same
#    as the glass switch). Prefs registered by IrisShredder; allowlisted for Settings here.
# Needs apply-glass-window.sh (mixer/ThemeService/allowlist anchors), apply-traffic-lights.sh (Appearance page),
#   apply-web-recolor.sh (website prefs).
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (iris_theme_mixer.o, theme_service.o, prefs_util.o,
#   settings TS build). UI not seen.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in chrome/browser/ui/color/iris_theme_mixer.h chrome/browser/ui/color/iris_theme_mixer.cc \
         chrome/browser/resources/settings/appearance_page/iris_theme_editor_page.ts \
         chrome/browser/resources/settings/appearance_page/iris_theme_editor_page.html.ts; do
  from="$DIR/src/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$f"; then echo "SKIP up to date: $f"; else cp "$from" "$f"; echo "OK   $f"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

C = "chrome/browser/ui/color/"
edit(C + "BUILD.gn", '    "iris_glass_mixer.cc",  # Iris\n',
     '    "iris_glass_mixer.cc",  # Iris\n'
     '    "iris_theme_mixer.cc",  # Iris (apply-theme-editor.sh)\n'
     '    "iris_theme_mixer.h",  # Iris (apply-theme-editor.sh)\n',
     '"iris_theme_mixer.cc"', "mixer sources")
m = C + "chrome_color_mixers.cc"
edit(m, '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n',
     '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n'
     '#include "chrome/browser/ui/color/iris_theme_mixer.h"  // Iris\n',
     'iris_theme_mixer.h"  // Iris', "mixer include")
edit(m, "  iris_glass::AddIrisGlassMixer(provider, key);\n",
     "  // Iris: Theme editor colours, before glass (apply-theme-editor.sh).\n"
     "  iris_theme::AddIrisThemeMixer(provider, key);\n"
     "  iris_glass::AddIrisGlassMixer(provider, key);\n",
     "iris_theme::AddIrisThemeMixer(provider, key);", "add mixer")

t = "chrome/browser/themes/theme_service.cc"
edit(t, '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n',
     '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n'
     '#include "chrome/browser/ui/color/iris_theme_mixer.h"  // Iris\n',
     'iris_theme_mixer.h"  // Iris', "ThemeService include")
edit(t, "  // Iris: see-through glass window (apply-glass-window.sh). The state is\n",
     "  // Iris: Theme editor colours (apply-theme-editor.sh); browser-wide like\n"
     "  // glass, so cached colour providers are dropped before windows repaint.\n"
     "  {\n"
     "    auto iris_apply_theme = [](ThemeService* self) {\n"
     "      iris_theme::SetCustomColors(\n"
     "          self->profile_->GetPrefs()->GetDict(iris_theme::kCustomColorsPref));\n"
     "      ui::ColorProviderManager::Get().ResetColorProviderCache();\n"
     "      self->NotifyThemeChanged();\n"
     "    };\n"
     "    pref_change_registrar_.Add(\n"
     "        iris_theme::kCustomColorsPref,\n"
     "        base::BindRepeating(iris_apply_theme, base::Unretained(this)));\n"
     "    iris_theme::SetCustomColors(\n"
     "        profile_->GetPrefs()->GetDict(iris_theme::kCustomColorsPref));\n"
     "  }\n"
     "  // Iris: see-through glass window (apply-glass-window.sh). The state is\n",
     "iris_apply_theme", "ThemeService: watch the colours")

edit("chrome/browser/extensions/api/settings_private/prefs_util.cc", "  // Iris: apply-glass-window.sh\n",
     "  // Iris: apply-theme-editor.sh, apply-web-recolor.sh\n"
     "  (*s_allowlist)[\"iris.theme.custom\"] = settings_api::PrefType::kDictionary;\n"
     "  (*s_allowlist)[\"iris.theme.saved\"] = settings_api::PrefType::kList;\n"
     "  (*s_allowlist)[\"iris.web_recolor.enabled\"] = settings_api::PrefType::kBoolean;\n"
     "  (*s_allowlist)[\"iris.web_recolor.brightness\"] = settings_api::PrefType::kNumber;\n"
     "  (*s_allowlist)[\"iris.web_recolor.contrast\"] = settings_api::PrefType::kNumber;\n"
     "  // Iris: apply-glass-window.sh\n",
     '"iris.theme.custom"', "Settings allowlist")

R = "chrome/browser/resources/settings/"
edit(R + "route.ts", "    r.FONTS = r.APPEARANCE.createChild('/fonts');\n",
     "    r.FONTS = r.APPEARANCE.createChild('/fonts');\n"
     "    r.IRIS_THEME_EDITOR = r.APPEARANCE.createChild('/themeEditor');  // Iris\n",
     "r.IRIS_THEME_EDITOR", "route")
edit(R + "router.ts", "  FONTS: Route;\n", "  FONTS: Route;\n  IRIS_THEME_EDITOR: Route;  // Iris\n",
     "IRIS_THEME_EDITOR: Route;", "routes interface")
edit(R + "appearance_page/appearance_page_index.html.ts",
     "  </settings-appearance-fonts-page>\n",
     "  </settings-appearance-fonts-page>\n\n"
     "  <!-- Iris: apply-theme-editor.sh -->\n"
     "  <settings-iris-theme-editor-page slot=\"view\" id=\"irisThemeEditor\"\n"
     "      data-parent-view-id=\"parent\"\n"
     "      route-path=\"${this.routes_.IRIS_THEME_EDITOR.path}\">\n"
     "  </settings-iris-theme-editor-page>\n",
     "settings-iris-theme-editor-page", "index view")
edit(R + "lazy_load.ts", "import './appearance_page/appearance_fonts_page.js';\n",
     "import './appearance_page/appearance_fonts_page.js';\n"
     "import './appearance_page/iris_theme_editor_page.js';  // Iris\n",
     "iris_theme_editor_page.js';  // Iris\n", "lazy-load import")
edit(R + "lazy_load.ts",
     "export {SettingsAppearanceFontsPageElement} from './appearance_page/appearance_fonts_page.js';\n",
     "export {SettingsAppearanceFontsPageElement} from './appearance_page/appearance_fonts_page.js';\n"
     "export {SettingsIrisThemeEditorPageElement} from './appearance_page/iris_theme_editor_page.js';  // Iris\n",
     "export {SettingsIrisThemeEditorPageElement}", "lazy-load export")
edit(R + "BUILD.gn", '    "appearance_page/appearance_fonts_page.ts",\n',
     '    "appearance_page/appearance_fonts_page.ts",\n'
     '    "appearance_page/iris_theme_editor_page.html.ts",  # Iris\n'
     '    "appearance_page/iris_theme_editor_page.ts",  # Iris\n',
     'appearance_page/iris_theme_editor_page.ts', "BUILD")

A = R + "appearance_page/"
edit(A + "appearance_page.html.ts", '    <settings-toggle-button id="irisGlassWindowToggle" class="hr"\n',
     '    <cr-link-row class="hr" id="irisThemeEditorTrigger"\n'
     '        label="Theme editor"\n'
     '        sub-label="Colours for each part of the window, and for websites"\n'
     '        @click="${this.onIrisThemeEditorClick_}">\n'
     '    </cr-link-row>\n'
     '    <settings-toggle-button id="irisGlassWindowToggle" class="hr"\n',
     'id="irisThemeEditorTrigger"', "link row")
p = A + "appearance_page.ts"
edit(p, "  protected onCustomizeFontsClick_() {\n",
     "  // Iris: apply-theme-editor.sh\n"
     "  protected onIrisThemeEditorClick_() {\n"
     "    Router.getInstance().navigateTo(routes.IRIS_THEME_EDITOR);\n"
     "  }\n\n"
     "  protected onCustomizeFontsClick_() {\n",
     "onIrisThemeEditorClick_() {", "link row click")
edit(p, "    if (routes.FONTS) {\n      map.set(routes.FONTS.path, '#customize-fonts-subpage-trigger');\n    }\n",
     "    if (routes.FONTS) {\n      map.set(routes.FONTS.path, '#customize-fonts-subpage-trigger');\n    }\n"
     "    if (routes.IRIS_THEME_EDITOR) {  // Iris\n"
     "      map.set(routes.IRIS_THEME_EDITOR.path, '#irisThemeEditorTrigger');\n"
     "    }\n",
     "'#irisThemeEditorTrigger');", "focus config")
edit(p, "    assert(childViewId === 'fonts');\n"
        "    const control = this.shadowRoot.querySelector<HTMLElement>(\n"
        "        '#customize-fonts-subpage-trigger');\n",
     "    assert(childViewId === 'fonts' || childViewId === 'irisThemeEditor');\n"
     "    const control = this.shadowRoot.querySelector<HTMLElement>(\n"
     "        childViewId === 'fonts' ? '#customize-fonts-subpage-trigger'\n"
     "                                : '#irisThemeEditorTrigger');  // Iris\n",
     "childViewId === 'irisThemeEditor'", "associated control")
# The Appearance section switches views per route; without this the link row changes the URL but shows nothing
# (jegly's test 2026-10-10: "clicking on theme editor does nothing").
edit(A + "appearance_page_index.ts",
     "        case routes.FONTS:\n          this.$.viewManager.switchView(\n              'fonts', 'no-animation', 'no-animation');\n          break;\n",
     "        case routes.FONTS:\n          this.$.viewManager.switchView(\n              'fonts', 'no-animation', 'no-animation');\n          break;\n"
     "        case routes.IRIS_THEME_EDITOR:  // Iris\n          this.$.viewManager.switchView(\n"
     "              'irisThemeEditor', 'no-animation', 'no-animation');\n          break;\n",
     "case routes.IRIS_THEME_EDITOR:", "view switch")
# Built-in pages in LIGHT mode: Chromium hardcodes white cards and a grey page there, so the palette and the Theme
# editor's Background never reached Settings (jegly 2026-10-10: "anyway to make the page thats white on settings change
# colour"). Same idea as the dark-mode block of apply-catppuccin-default.sh: page = base container (a slightly darker
# shade), cards and menus = base. Dark mode is unchanged (its block comes later in the file and wins there).
edit("ui/webui/resources/cr_elements/cr_shared_vars.css",
     "/* Iris: built-in pages follow the theme colours in dark mode (Catppuccin Mocha by\n",
     "/* Iris: built-in pages follow the theme colours in light mode too\n"
     " * (apply-theme-editor.sh): a slightly darker page, cards and menus in the\n"
     " * theme background. */\n"
     "html:not([webui-refresh-2026]) {\n"
     "  --md-background-color: var(--color-sys-base-container, rgb(248, 249, 250));\n"
     "  --cr-card-background-color: var(--color-sys-base, white);\n"
     "  --cr-menu-background-color: var(--color-sys-base, white);\n"
     "}\n\n"
     "/* Iris: built-in pages follow the theme colours in dark mode (Catppuccin Mocha by\n",
     "follow the theme colours in light mode too", "light-mode page colours")
PY
echo "=== Theme editor complete ==="
