#!/usr/bin/env bash
# Iris — see-through "glass" window, like Notas (jegly 2026-10-08, phase 1: title bar, tab strip, toolbar; web pages
# stay opaque; verified against 156.0.8078.11). Off by default; Settings -> Appearance: switch + opacity slider 30-100 %
# (default 78 %, Notas' rules, see patches/src/chrome/browser/ui/color/iris_glass_mixer.h).
#  - The Linux window already has an alpha channel (browser_native_widget_aura_linux.cc kTranslucent, upstream, for
#    the client-side shadow); the top container layer is already non-opaque (browser_view.cc).
#  - New colour mixer iris_glass_mixer.* added LAST in AddChromeColorMixers(): alpha on the frame, toolbar, bookmarks
#    bar and tab colours (ui::SetAlpha(FromTransformInput())), so it applies on top of any Iris palette. Skipped for
#    installed/GTK/Qt themes and high contrast.
#  - ThemeService: the two prefs set the browser-wide glass state, clear the colour-provider cache (the state is not
#    part of ColorProviderKey) and notify -> open windows repaint at once.
#  - Prefs iris.glass.window (false) + iris.glass.window_opacity (78) registered by IrisShredder.
# Needs apply-glass.sh (anchor in theme_service.cc), apply-traffic-lights.sh (Appearance anchor order), apply-shredder.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven. Visual result unknown until a dev build (jegly to see it).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in iris_glass_mixer.h iris_glass_mixer.cc; do
  to="chrome/browser/ui/color/$f"; from="$DIR/src/$to"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
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
edit(C + "BUILD.gn", "    \"chrome_color_mixers.cc\",\n    \"chrome_color_mixers.h\",\n",
     "    \"chrome_color_mixers.cc\",\n    \"chrome_color_mixers.h\",\n"
     "    \"iris_glass_mixer.cc\",  # Iris\n    \"iris_glass_mixer.h\",  # Iris\n",
     "iris_glass_mixer.cc", "BUILD")
m = C + "chrome_color_mixers.cc"
edit(m, '#include "chrome/browser/ui/color/chrome_color_mixers.h"\n',
     '#include "chrome/browser/ui/color/chrome_color_mixers.h"\n'
     '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n',
     "iris_glass_mixer.h\"  // Iris", "include")
edit(m, "  if (key.app_controller) {\n    key.app_controller->AddColorMixers(provider, key);\n  }\n}\n",
     "  if (key.app_controller) {\n    key.app_controller->AddColorMixers(provider, key);\n  }\n\n"
     "  // Iris: see-through glass window, last so it sees the final colours\n"
     "  // (apply-glass-window.sh).\n"
     "  iris_glass::AddIrisGlassMixer(provider, key);\n}\n",
     "iris_glass::AddIrisGlassMixer(provider, key);", "mixer call")
t = "chrome/browser/themes/theme_service.cc"
edit(t, '#include "chrome/browser/themes/theme_service.h"\n',
     '#include "chrome/browser/themes/theme_service.h"\n'
     '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n'
     '#include "ui/color/color_provider_manager.h"  // Iris\n',
     "iris_glass_mixer.h\"  // Iris", "includes")
edit(t,
     "  // Iris (B9 glass): open built-in pages re-fetch colors.css.\n"
     "  pref_change_registrar_.Add(\n"
     "      \"iris.glass.enabled\",\n"
     "      base::BindRepeating(&ThemeService::NotifyThemeChanged,\n"
     "                          base::Unretained(this)));\n",
     "  // Iris (B9 glass): open built-in pages re-fetch colors.css.\n"
     "  pref_change_registrar_.Add(\n"
     "      \"iris.glass.enabled\",\n"
     "      base::BindRepeating(&ThemeService::NotifyThemeChanged,\n"
     "                          base::Unretained(this)));\n"
     "  // Iris: see-through glass window (apply-glass-window.sh). The state is\n"
     "  // browser-wide and not part of ColorProviderKey, so cached colour\n"
     "  // providers are dropped before windows repaint.\n"
     "  {\n"
     "    auto iris_apply_glass = [](ThemeService* self) {\n"
     "      PrefService* prefs = self->profile_->GetPrefs();\n"
     "      iris_glass::SetWindowGlass(prefs->GetBoolean(iris_glass::kWindowPref),\n"
     "                                 prefs->GetInteger(iris_glass::kOpacityPref));\n"
     "      ui::ColorProviderManager::Get().ResetColorProviderCache();\n"
     "      self->NotifyThemeChanged();\n"
     "    };\n"
     "    for (const char* pref :\n"
     "         {iris_glass::kWindowPref, iris_glass::kOpacityPref}) {\n"
     "      pref_change_registrar_.Add(\n"
     "          pref, base::BindRepeating(iris_apply_glass, base::Unretained(this)));\n"
     "    }\n"
     "    iris_glass::SetWindowGlass(\n"
     "        profile_->GetPrefs()->GetBoolean(iris_glass::kWindowPref),\n"
     "        profile_->GetPrefs()->GetInteger(iris_glass::kOpacityPref));\n"
     "  }\n",
     "iris_apply_glass", "prefs -> glass state")
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-traffic-lights.sh\n",
     "  // Iris: apply-glass-window.sh\n"
     "  (*s_allowlist)[\"iris.glass.window\"] = settings_api::PrefType::kBoolean;\n"
     "  (*s_allowlist)[\"iris.glass.window_opacity\"] =\n      settings_api::PrefType::kNumber;\n"
     "  // Iris: apply-traffic-lights.sh\n",
     "\"iris.glass.window\"", "allowlist")
A = "chrome/browser/resources/settings/appearance_page/"
edit(A + "appearance_page.html.ts", "    <div id=\"toolbarRow\" class=\"settings-row\">\n",
     "    <!-- Iris: see-through glass window (apply-glass-window.sh; English-only, TODO localize) -->\n"
     "    <settings-toggle-button id=\"irisGlassWindowToggle\" class=\"hr\"\n"
     "        pref-key=\"iris.glass.window\"\n"
     "        label=\"See-through window (glass)\"\n"
     "        sub-label=\"The title bar, tabs and toolbar let your desktop show through. Web pages stay solid.\">\n"
     "    </settings-toggle-button>\n"
     "    <div id=\"irisGlassOpacityRow\" class=\"cr-row\"\n"
     "        ?hidden=\"${!this.irisGlassWindowPref_?.value}\">\n"
     "      <div class=\"flex cr-padded-text\">Glass opacity</div>\n"
     "      <input type=\"range\" id=\"irisGlassOpacity\" min=\"30\" max=\"100\" step=\"1\"\n"
     "          aria-label=\"Glass opacity\"\n"
     "          .value=\"${String(this.irisGlassOpacityPref_?.value ?? 78)}\"\n"
     "          @change=\"${this.onIrisGlassOpacityChange_}\">\n"
     "      <div class=\"cr-padded-text\">${this.irisGlassOpacityPref_?.value ?? 78}%</div>\n"
     "    </div>\n"
     "    <div id=\"toolbarRow\" class=\"settings-row\">\n",
     "irisGlassWindowToggle", "Appearance markup")
p = A + "appearance_page.ts"
edit(p, "      irisTrafficLightsPref_: {type: Object},     // Iris\n",
     "      irisTrafficLightsPref_: {type: Object},     // Iris\n"
     "      irisGlassWindowPref_: {type: Object},       // Iris\n"
     "      irisGlassOpacityPref_: {type: Object},      // Iris\n",
     "irisGlassWindowPref_: {type: Object}", "properties")
edit(p, "  // Iris: traffic-light window buttons (apply-traffic-lights.sh).\n"
        "  protected accessor irisTrafficLightsPref_: PrefObject<boolean>|undefined =\n      undefined;\n",
     "  // Iris: see-through glass window (apply-glass-window.sh).\n"
     "  protected accessor irisGlassWindowPref_: PrefObject<boolean>|undefined =\n      undefined;\n"
     "  protected accessor irisGlassOpacityPref_: PrefObject<number>|undefined =\n      undefined;\n"
     "  // Iris: traffic-light window buttons (apply-traffic-lights.sh).\n"
     "  protected accessor irisTrafficLightsPref_: PrefObject<boolean>|undefined =\n      undefined;\n",
     "protected accessor irisGlassWindowPref_", "accessors")
edit(p, "      'iris.ui.traffic_lights': 'irisTrafficLightsPref_',\n",
     "      'iris.ui.traffic_lights': 'irisTrafficLightsPref_',\n"
     "      'iris.glass.window': 'irisGlassWindowPref_',\n"
     "      'iris.glass.window_opacity': 'irisGlassOpacityPref_',\n",
     "'iris.glass.window': 'irisGlassWindowPref_'", "mirrored prefs")
edit(p, "  // Iris: traffic-light window button colours (apply-traffic-lights.sh).\n",
     "  // Iris: glass opacity slider (apply-glass-window.sh).\n"
     "  protected onIrisGlassOpacityChange_(e: Event) {\n"
     "    PrefService.getInstance().setPrefValue(\n"
     "        'iris.glass.window_opacity',\n"
     "        Number((e.target as HTMLInputElement).value));\n"
     "  }\n\n"
     "  // Iris: traffic-light window button colours (apply-traffic-lights.sh).\n",
     "onIrisGlassOpacityChange_(e: Event)", "handler")
PY
echo "=== see-through glass window complete ==="
