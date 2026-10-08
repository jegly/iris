#!/usr/bin/env bash
# Iris — macOS-style "traffic light" window buttons on the desktop (Linux) frame (jegly 2026-10-08: "match AV", on by
# default, right side where they are now, colours changeable in Appearance, a switch back to Chromium's buttons;
# verified against 156.0.8078.11).
#  - New views::FrameCaptionButton subclass patches/src/chrome/browser/ui/views/frame/iris_traffic_light_button.* (AV's
#    CSDWindowButton look: 13 px dot, 22 px slot + 2 px, #FF5F57/#FEBC2E/#28C840, glyphs on group hover).
#  - OpaqueBrowserFrameView: when the MD caption buttons would be created (Linux, non-GTK frame) and the profile pref
#    iris.ui.traffic_lights is on (default), the four buttons are IrisTrafficLightButtons. The GTK-native frame
#    (BrowserFrameViewLinuxNative, image buttons) is untouched. New windows pick up a change of the switch.
#  - OpaqueBrowserFrameViewLayout: Iris buttons get kSlotWidth (24 px) instead of the caption-button width.
#  - Prefs (IrisShredder::RegisterProfilePrefs): iris.ui.traffic_lights (true) + iris.ui.traffic_light_{close,minimize,
#    maximize} ("#rrggbb"). Colours repaint live.
#  - Settings -> Appearance: "Traffic-light window buttons" switch + three colour pickers + Reset, and
#    "Show symbols on the window buttons" (iris.ui.traffic_light_symbols, default on; 2026-10-08).
# STATUS 2026-10-08: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in iris_traffic_light_button.h iris_traffic_light_button.cc; do
  to="chrome/browser/ui/views/frame/$f"; from="$DIR/src/$to"
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
F = "chrome/browser/ui/views/frame/"

# BUILD
edit(F + "BUILD.gn", "source_set(\"opaque_browser_frame_view_layout\") {\n",
     "# Iris: traffic-light window buttons (apply-traffic-lights.sh).\n"
     "source_set(\"iris_traffic_light_button\") {\n"
     "  sources = [\n    \"iris_traffic_light_button.cc\",\n    \"iris_traffic_light_button.h\",\n  ]\n"
     "  deps = [\n    \"//base\",\n    \"//cc/paint\",\n    \"//components/prefs\",\n    \"//skia\",\n"
     "    \"//ui/gfx\",\n    \"//ui/views\",\n  ]\n}\n\n"
     "source_set(\"opaque_browser_frame_view_layout\") {\n",
     "source_set(\"iris_traffic_light_button\")", "BUILD: new source set")
edit(F + "BUILD.gn",
     "  deps = [\n    \":caption_button_placeholder_container\",\n    \"//base:i18n\",\n",
     "  deps = [\n    \":caption_button_placeholder_container\",\n    \":iris_traffic_light_button\",  # Iris\n"
     "    \"//base:i18n\",\n",
     "\":iris_traffic_light_button\",  # Iris\n    \"//base:i18n\"", "BUILD: layout dep")
edit(F + "BUILD.gn",
     "      \":caption_button_placeholder_container\",\n      \":opaque_browser_frame_view_layout\",\n",
     "      \":caption_button_placeholder_container\",\n      \":iris_traffic_light_button\",  # Iris\n"
     "      \":opaque_browser_frame_view_layout\",\n",
     "      \":iris_traffic_light_button\",  # Iris\n      \":opaque_browser_frame_view_layout\"",
     "BUILD: frame view dep")

# frame view
v = F + "opaque_browser_frame_view.cc"
edit(v, '#include "chrome/browser/ui/views/frame/opaque_browser_frame_view_layout.h"\n',
     '#include "chrome/browser/ui/views/frame/opaque_browser_frame_view_layout.h"\n'
     '#include "chrome/browser/profiles/profile.h"  // Iris\n'
     '#include "chrome/browser/ui/views/frame/iris_traffic_light_button.h"  // Iris\n'
     '#include "components/prefs/pref_service.h"  // Iris\n',
     "iris_traffic_light_button.h\"  // Iris", "includes")
edit(v, "  if (GetFrameButtonStyle() == FrameButtonStyle::kMdButton) {\n    minimize_button_ = CreateFrameCaptionButton(",
     "  // Iris: traffic-light window buttons, Settings -> Appearance (on by default;\n"
     "  // apply-traffic-lights.sh).\n"
     "  PrefService* const iris_prefs = GetBrowserView()->GetProfile()->GetPrefs();\n"
     "  if (GetFrameButtonStyle() == FrameButtonStyle::kMdButton &&\n"
     "      IrisTrafficLightButton::IsEnabledFor(iris_prefs)) {\n"
     "    minimize_button_ = new IrisTrafficLightButton(\n"
     "        views::CAPTION_BUTTON_ICON_MINIMIZE, HTMINBUTTON,\n"
     "        IrisTrafficLightButton::Glyph::kMinimize, iris_prefs);\n"
     "    maximize_button_ = new IrisTrafficLightButton(\n"
     "        views::CAPTION_BUTTON_ICON_MAXIMIZE_RESTORE, HTMAXBUTTON,\n"
     "        IrisTrafficLightButton::Glyph::kMaximize, iris_prefs);\n"
     "    restore_button_ = new IrisTrafficLightButton(\n"
     "        views::CAPTION_BUTTON_ICON_MAXIMIZE_RESTORE, HTMAXBUTTON,\n"
     "        IrisTrafficLightButton::Glyph::kRestore, iris_prefs);\n"
     "    close_button_ = new IrisTrafficLightButton(\n"
     "        views::CAPTION_BUTTON_ICON_CLOSE, HTCLOSE,\n"
     "        IrisTrafficLightButton::Glyph::kClose, iris_prefs);\n"
     "  } else if (GetFrameButtonStyle() == FrameButtonStyle::kMdButton) {\n"
     "    minimize_button_ = CreateFrameCaptionButton(",
     "IrisTrafficLightButton::IsEnabledFor(iris_prefs)", "create Iris buttons")

# layout
l = F + "opaque_browser_frame_view_layout.cc"
edit(l, '#include "chrome/browser/ui/views/frame/caption_button_placeholder_container.h"\n',
     '#include "chrome/browser/ui/views/frame/caption_button_placeholder_container.h"\n'
     '#include "chrome/browser/ui/views/frame/iris_traffic_light_button.h"  // Iris\n',
     "iris_traffic_light_button.h\"  // Iris", "include")
edit(l, "    button_size = gfx::Size(button_width, height);\n    button->SetPreferredSize(button_size);\n",
     "    button_size = gfx::Size(button_width, height);\n"
     "    // Iris: traffic-light buttons use AV's narrower slot.\n"
     "    if (IrisTrafficLightButton::IsIrisButton(button)) {\n"
     "      button_size.set_width(IrisTrafficLightButton::kSlotWidth);\n    }\n"
     "    button->SetPreferredSize(button_size);\n",
     "IrisTrafficLightButton::IsIrisButton(button)", "slot width")

# prefs (registered with the other Iris profile prefs)
edit("chrome/browser/iris/iris_shredder.cc",
     "  registry->RegisterBooleanPref(kHideInstallButtonPref, false);\n",
     "  registry->RegisterBooleanPref(kHideInstallButtonPref, false);\n"
     "  // Traffic-light window buttons (apply-traffic-lights.sh; names in\n"
     "  // chrome/browser/ui/views/frame/iris_traffic_light_button.h).\n"
     "  registry->RegisterBooleanPref(\"iris.ui.traffic_lights\", true);\n"
     "  registry->RegisterStringPref(\"iris.ui.traffic_light_close\", \"#ff5f57\");\n"
     "  registry->RegisterStringPref(\"iris.ui.traffic_light_minimize\", \"#febc2e\");\n"
     "  registry->RegisterStringPref(\"iris.ui.traffic_light_maximize\", \"#28c840\");\n",
     "iris.ui.traffic_lights", "register prefs")
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-traffic-lights.sh\n"
     "  (*s_allowlist)[\"iris.ui.traffic_lights\"] = settings_api::PrefType::kBoolean;\n"
     + "".join("  (*s_allowlist)[\"iris.ui.traffic_light_%s\"] =\n      settings_api::PrefType::kString;\n" % k
               for k in ("close", "minimize", "maximize"))
     + "  // Iris: apply-privacy-toggles-3.sh\n",
     "\"iris.ui.traffic_lights\"", "allowlist")

# Settings -> Appearance
A = "chrome/browser/resources/settings/appearance_page/"
edit(A + "appearance_page.html.ts", "    <div id=\"toolbarRow\" class=\"settings-row\">\n",
     "    <!-- Iris: traffic-light window buttons (apply-traffic-lights.sh; English-only, TODO localize) -->\n"
     "    <settings-toggle-button id=\"irisTrafficLightsToggle\" class=\"hr\"\n"
     "        pref-key=\"iris.ui.traffic_lights\"\n"
     "        label=\"Traffic-light window buttons\"\n"
     "        sub-label=\"Round coloured close, minimise and maximise buttons. Turn off for Chromium's standard "
     "buttons. New windows use the change.\">\n"
     "    </settings-toggle-button>\n"
     "    <div id=\"irisTrafficLightColors\" class=\"cr-row\"\n"
     "        ?hidden=\"${!this.irisTrafficLightsPref_?.value}\">\n"
     "      <div class=\"flex cr-padded-text\">Window button colours</div>\n"
     "      <input type=\"color\" id=\"irisTrafficClose\" aria-label=\"Close button colour\"\n"
     "          data-pref=\"iris.ui.traffic_light_close\"\n"
     "          .value=\"${this.irisTrafficClosePref_?.value || '#ff5f57'}\"\n"
     "          @change=\"${this.onIrisTrafficColorChange_}\">\n"
     "      <input type=\"color\" id=\"irisTrafficMinimize\" aria-label=\"Minimise button colour\"\n"
     "          data-pref=\"iris.ui.traffic_light_minimize\"\n"
     "          .value=\"${this.irisTrafficMinimizePref_?.value || '#febc2e'}\"\n"
     "          @change=\"${this.onIrisTrafficColorChange_}\">\n"
     "      <input type=\"color\" id=\"irisTrafficMaximize\" aria-label=\"Maximise button colour\"\n"
     "          data-pref=\"iris.ui.traffic_light_maximize\"\n"
     "          .value=\"${this.irisTrafficMaximizePref_?.value || '#28c840'}\"\n"
     "          @change=\"${this.onIrisTrafficColorChange_}\">\n"
     "      <div class=\"separator\"></div>\n"
     "      <cr-button id=\"irisTrafficReset\" @click=\"${this.onIrisTrafficResetClick_}\">\n"
     "        $i18n{resetToDefault}\n      </cr-button>\n"
     "    </div>\n"
     "    <div id=\"toolbarRow\" class=\"settings-row\">\n",
     "irisTrafficLightsToggle", "Appearance markup")
t = A + "appearance_page.ts"
edit(t, "      themeIdPref_: {type: Object},\n",
     "      themeIdPref_: {type: Object},\n"
     "      irisTrafficLightsPref_: {type: Object},     // Iris\n"
     "      irisTrafficClosePref_: {type: Object},      // Iris\n"
     "      irisTrafficMinimizePref_: {type: Object},   // Iris\n"
     "      irisTrafficMaximizePref_: {type: Object},   // Iris\n",
     "irisTrafficLightsPref_: {type: Object}", "properties")
edit(t, "  protected accessor themeIdPref_: PrefObject<string>|undefined = undefined;\n",
     "  protected accessor themeIdPref_: PrefObject<string>|undefined = undefined;\n"
     "  // Iris: traffic-light window buttons (apply-traffic-lights.sh).\n"
     "  protected accessor irisTrafficLightsPref_: PrefObject<boolean>|undefined =\n      undefined;\n"
     "  protected accessor irisTrafficClosePref_: PrefObject<string>|undefined =\n      undefined;\n"
     "  protected accessor irisTrafficMinimizePref_: PrefObject<string>|undefined =\n      undefined;\n"
     "  protected accessor irisTrafficMaximizePref_: PrefObject<string>|undefined =\n      undefined;\n",
     "protected accessor irisTrafficLightsPref_", "accessors")
edit(t, "      'extensions.theme.id': 'themeIdPref_',\n",
     "      'extensions.theme.id': 'themeIdPref_',\n"
     "      'iris.ui.traffic_lights': 'irisTrafficLightsPref_',\n"
     "      'iris.ui.traffic_light_close': 'irisTrafficClosePref_',\n"
     "      'iris.ui.traffic_light_minimize': 'irisTrafficMinimizePref_',\n"
     "      'iris.ui.traffic_light_maximize': 'irisTrafficMaximizePref_',\n",
     "'iris.ui.traffic_lights': 'irisTrafficLightsPref_'", "mirrored prefs")
edit(t, "  protected onThemeClick_() {\n",
     "  // Iris: traffic-light window button colours (apply-traffic-lights.sh).\n"
     "  protected onIrisTrafficColorChange_(e: Event) {\n"
     "    const input = e.target as HTMLInputElement;\n"
     "    const pref = input.dataset['pref'];\n"
     "    if (pref) {\n"
     "      PrefService.getInstance().setPrefValue(pref, input.value);\n"
     "    }\n"
     "  }\n\n"
     "  protected onIrisTrafficResetClick_() {\n"
     "    const prefService = PrefService.getInstance();\n"
     "    prefService.setPrefValue('iris.ui.traffic_light_close', '#ff5f57');\n"
     "    prefService.setPrefValue('iris.ui.traffic_light_minimize', '#febc2e');\n"
     "    prefService.setPrefValue('iris.ui.traffic_light_maximize', '#28c840');\n"
     "  }\n\n"
     "  protected onThemeClick_() {\n",
     "onIrisTrafficColorChange_(e: Event)", "handlers")

# 2026-10-08 (jegly): switch to hide the ×/−/□ symbols (iris.ui.traffic_light_symbols, default true).
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[\"iris.ui.traffic_lights\"] = settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[\"iris.ui.traffic_lights\"] = settings_api::PrefType::kBoolean;\n"
     "  (*s_allowlist)[\"iris.ui.traffic_light_symbols\"] =\n      settings_api::PrefType::kBoolean;\n",
     "\"iris.ui.traffic_light_symbols\"", "allowlist: symbols")
edit(A + "appearance_page.html.ts",
     "    <div id=\"irisTrafficLightColors\" class=\"cr-row\"\n",
     "    <settings-toggle-button id=\"irisTrafficSymbolsToggle\" class=\"hr\"\n"
     "        pref-key=\"iris.ui.traffic_light_symbols\"\n"
     "        label=\"Show symbols on the window buttons\"\n"
     "        sub-label=\"The close, minimise and maximise symbols appear while you point at the buttons.\"\n"
     "        ?hidden=\"${!this.irisTrafficLightsPref_?.value}\">\n"
     "    </settings-toggle-button>\n"
     "    <div id=\"irisTrafficLightColors\" class=\"cr-row\"\n",
     "irisTrafficSymbolsToggle", "Appearance: symbols switch")
PY
echo "=== traffic-light window buttons complete ==="
