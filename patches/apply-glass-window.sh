#!/usr/bin/env bash
# Iris — see-through "glass" window, like Notas (jegly 2026-10-08; phase 1: title bar, tab strip, toolbar; phase 2:
# Iris's own chrome:// pages; websites stay opaque; verified against 156.0.8078.11). Off by default; Settings -> Appearance: switch + opacity slider 30-100 %
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
# STATUS 2026-10-08: phase 1 seen working in jegly's dev build; top-bar flicker fix (opaque region) NOT yet seen.
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
# Fix (jegly 2026-10-08, "flickers in the top bar", Notas does not): the Linux frame told the compositor the whole
# window was opaque (BrowserFrameViewLinux::GetTranslucentTopAreaHeight() returned 0 -> opaque region = everything), so
# GNOME skipped drawing what is behind the see-through bar and stale pixels flickered there. With glass on it now
# reports the top container (tab strip + toolbar + bookmarks bar, plus slack for a bar that appears later) as
# translucent - the same thing upstream's GTK frame does when its frame is translucent. Toggling glass / the slider
# fires a native-theme update, which makes BrowserDesktopWindowTreeHostLinux::UpdateFrameHints() resend the region.
fv = "chrome/browser/ui/views/frame/browser_frame_view_linux.cc"
edit(fv, '#include "chrome/browser/ui/views/frame/browser_frame_view_linux.h"\n',
     '#include "chrome/browser/ui/views/frame/browser_frame_view_linux.h"\n\n'
     '#include <algorithm>  // Iris\n\n'
     '#include "base/numerics/safe_conversions.h"  // Iris\n'
     '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n',
     "iris_glass_mixer.h\"  // Iris", "frame: includes")
edit(fv, "int BrowserFrameViewLinux::GetTranslucentTopAreaHeight() const {\n  return 0;\n}\n",
     "int BrowserFrameViewLinux::GetTranslucentTopAreaHeight() const {\n"
     "  // Iris: see-through glass window (apply-glass-window.sh). Report the top\n"
     "  // bar as translucent, or the compositor skips what is behind it and the\n"
     "  // bar flickers. 40 DIP slack covers a bookmarks bar shown later.\n"
     "  if (iris_glass::IsWindowGlassEnabled()) {\n"
     "    int height = GetTopAreaHeight();\n"
     "    if (const views::View* top = GetBrowserView()->top_container()) {\n"
     "      gfx::RectF top_bounds(top->GetLocalBounds());\n"
     "      views::View::ConvertRectToTarget(top, this, &top_bounds);\n"
     "      height = std::max(height, base::ClampCeil(top_bounds.bottom()));\n"
     "    }\n"
     "    return height + 40;\n"
     "  }\n"
     "  return 0;\n}\n",
     "iris_glass::IsWindowGlassEnabled()", "frame: translucent top area")
edit(fv, '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n',
     '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n'
     '#include "chrome/browser/ui/views/frame/top_container_view.h"  // Iris\n',
     'top_container_view.h"  // Iris', "frame: include top container")
t2 = "chrome/browser/themes/theme_service.cc"
edit(t2, "      ui::ColorProviderManager::Get().ResetColorProviderCache();\n      self->NotifyThemeChanged();\n",
     "      ui::ColorProviderManager::Get().ResetColorProviderCache();\n"
     "      // Also resends the window's opaque region (frame hints) on Linux.\n"
     "      ui::NativeTheme::GetInstanceForNativeUi()->NotifyOnNativeThemeUpdated();\n"
     "      self->NotifyThemeChanged();\n",
     "NotifyOnNativeThemeUpdated();\n      self->NotifyThemeChanged();", "native theme update on toggle")
s2 = open(t2).read()
if '#include "ui/native_theme/native_theme.h"' not in s2:
    edit(t2, '#include "ui/color/color_provider_manager.h"  // Iris\n',
         '#include "ui/color/color_provider_manager.h"  // Iris\n#include "ui/native_theme/native_theme.h"  // Iris\n',
         '#include "ui/native_theme/native_theme.h"  // Iris', "include native_theme")
# Phase 2 (jegly 2026-10-08): Iris's own pages (chrome://, incl. the local new tab page) see-through too.
#  - ContentsWebView: while glass is on and the tab shows a chrome:// page, its background layer and the page's
#    renderer background are transparent (the upstream "background not visible" path); re-checked on navigation
#    (PrimaryPageChanged), tab switch (SetWebContents/RenderViewReady) and theme/glass changes (OnThemeChanged).
#    Websites are never made transparent.
#  - colors.css (ThemeSource): the page background is transparent and cards use the theme base colour at Notas'
#    editor level (opacity - 0.15, floor 0.20); refreshed by ThemeService::NotifyThemeChanged on toggle/slider.
cw = "chrome/browser/ui/views/frame/contents_web_view.cc"
edit("chrome/browser/ui/views/frame/contents_web_view.h",
     "#if BUILDFLAG(IS_LINUX) || BUILDFLAG(IS_CHROMEOS)\n  void DidGetUserInteraction(const blink::WebInputEvent& event) override;\n#endif\n",
     "#if BUILDFLAG(IS_LINUX) || BUILDFLAG(IS_CHROMEOS)\n  void DidGetUserInteraction(const blink::WebInputEvent& event) override;\n#endif\n"
     "  // Iris: re-check the see-through glass background (apply-glass-window.sh).\n"
     "  void PrimaryPageChanged(content::Page& page) override;\n",
     "void PrimaryPageChanged(content::Page& page) override;", "contents view: header")
edit(cw, '#include "chrome/browser/ui/color/chrome_color_id.h"\n',
     '#include "chrome/browser/ui/color/chrome_color_id.h"\n'
     '#include "chrome/browser/ui/color/iris_glass_mixer.h"  // Iris\n'
     '#include "content/public/common/url_constants.h"  // Iris\n',
     'iris_glass_mixer.h"  // Iris', "contents view: includes")
edit(cw, "void ContentsWebView::UpdateBackgroundColor() {\n",
     "// Iris: see-through glass window, phase 2 (apply-glass-window.sh): Iris's own\n"
     "// chrome:// pages get a transparent background so the desktop shows through;\n"
     "// websites never do.\n"
     "void ContentsWebView::PrimaryPageChanged(content::Page& page) {\n"
     "  views::WebView::PrimaryPageChanged(page);\n"
     "  if (GetWidget()) {\n    UpdateBackgroundColor();\n  }\n}\n\n"
     "void ContentsWebView::UpdateBackgroundColor() {\n"
     "  const bool iris_glass_page =\n"
     "      iris_glass::IsWindowGlassEnabled() && web_contents() &&\n"
     "      web_contents()->GetLastCommittedURL().SchemeIs(content::kChromeUIScheme);\n"
     "  const bool background_visible = background_visible_ && !iris_glass_page;\n",
     "const bool iris_glass_page =", "contents view: glass pages")
s2 = open(cw).read()
old_tail = ("    if (background_visible_) {\n      return;\n    }\n  }\n\n"
            "  auto* background_layer = layer()->AsSolidColor();\n"
            "  background_layer->SetColor(\n"
            "      SkColor4f::FromColor(background_visible_ ? color : SK_ColorTRANSPARENT));\n\n"
            "  SafeInvoke(web_contents())\n"
            "      .Then(&content::WebContents::GetRenderWidgetHostView)\n"
            "      .Then(&content::RenderWidgetHostView::SetBackgroundColor,\n"
            "            background_visible_ ? color : SK_ColorTRANSPARENT);\n")
new_tail = old_tail.replace("background_visible_", "background_visible")
edit(cw, old_tail, new_tail, "SkColor4f::FromColor(background_visible ? color", "contents view: use glass flag")
# Fixes after jegly's test (2026-10-08: "works for a second, switch back to old tab not on"):
#  - tab switch re-applies the background (SetWebContents did not call UpdateBackgroundColor).
#  - the local new tab page bakes its background colour into the page (colorBackground, kColorNewTabPageBackground)
#    and does not load colors.css -> "transparent" while the glass window is on (new tabs; reload an open one).
edit(cw, "  UpdateIsBlockedByModal();\n\n  if (!status_bubble_) {\n",
     "  UpdateIsBlockedByModal();\n\n"
     "  // Iris: tab switch re-applies the see-through glass background.\n"
     "  if (GetWidget()) {\n    UpdateBackgroundColor();\n  }\n\n"
     "  if (!status_bubble_) {\n",
     "tab switch re-applies the see-through glass background", "contents view: tab switch")
nt = "chrome/browser/ui/webui/new_tab_page_third_party/new_tab_page_third_party_ui.cc"
edit(nt, "    source->AddString(\"colorBackground\",\n"
         "                      color_utils::SkColorToRgbaString(GetThemeColor(\n"
         "                          webui::GetNativeThemeDeprecated(web_contents),\n"
         "                          color_provider, kColorNewTabPageBackground)));\n",
     "    // Iris: see-through glass window -> transparent new tab page\n"
     "    // (apply-glass-window.sh).\n"
     "    source->AddString(\n"
     "        \"colorBackground\",\n"
     "        profile->GetPrefs()->GetBoolean(\"iris.glass.window\")\n"
     "            ? std::string(\"transparent\")\n"
     "            : color_utils::SkColorToRgbaString(GetThemeColor(\n"
     "                  webui::GetNativeThemeDeprecated(web_contents),\n"
     "                  color_provider, kColorNewTabPageBackground)));\n",
     "see-through glass window -> transparent new tab page", "new tab page: transparent")
ts = "chrome/browser/ui/webui/theme_source.cc"
edit(ts, "  std::move(callback).Run(\n      base::MakeRefCounted<base::RefCountedString>(std::move(*css_content)));\n",
     "  // Iris: see-through glass window, phase 2 (apply-glass-window.sh): the page\n"
     "  // background is transparent (the tab lets the desktop through) and cards\n"
     "  // keep a translucent base colour so text stays readable (Notas' editor\n"
     "  // level: opacity - 0.15, never below 0.20).\n"
     "  {\n"
     "    PrefService* iris_prefs = profile_->GetOriginalProfile()->GetPrefs();\n"
     "    std::string iris_shadow_host;\n"
     "    if (iris_prefs->GetBoolean(\"iris.glass.window\") &&\n"
     "        !(net::GetValueForKeyInQuery(url, \"shadow_host\", &iris_shadow_host) &&\n"
     "          base::EqualsCaseInsensitiveASCII(iris_shadow_host, \"true\"))) {\n"
     "      const float a =\n"
     "          std::clamp(iris_prefs->GetInteger(\"iris.glass.window_opacity\"), 30, 100) /\n"
     "          100.0f;\n"
     "      const SkColor base = color_provider.GetColor(ui::kColorSysBase);\n"
     "      const SkColor line = color_provider.GetColor(ui::kColorSysOnSurface);\n"
     "      css_content->append(base::StringPrintf(\n"
     "          \"html:not(#z),html:not(#z) body{background:transparent !important;}\"\n"
     "          \"html:not(#z){--md-background-color:transparent;\"\n"
     "          \"--cr-card-background-color:rgba(%d,%d,%d,%.3f);\"\n"
     "          \"--iris-glass-border:1px solid rgba(%d,%d,%d,0.12);}\",\n"
     "          SkColorGetR(base), SkColorGetG(base), SkColorGetB(base),\n"
     "          std::max(a - 0.15f, 0.20f), SkColorGetR(line), SkColorGetG(line),\n"
     "          SkColorGetB(line)));\n"
     "    }\n"
     "  }\n\n"
     "  std::move(callback).Run(\n      base::MakeRefCounted<base::RefCountedString>(std::move(*css_content)));\n",
     "see-through glass window, phase 2", "colors.css: transparent pages")
s3 = open(ts).read()
if "#include <algorithm>" not in s3:
    edit(ts, '#include "chrome/browser/ui/webui/theme_source.h"\n',
         '#include "chrome/browser/ui/webui/theme_source.h"\n\n#include <algorithm>  // Iris\n',
         "#include <algorithm>  // Iris", "include algorithm")
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
