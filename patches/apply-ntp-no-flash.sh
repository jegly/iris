#!/usr/bin/env bash
# Iris — no white/black flash when opening a new tab (jegly 2026-11-06: "+ new tab ... flashes" - black with GNOME
# dark, pure white with GNOME light, with an Iris palette; stock Chromium shows no visible flash).
# Verified against 157.0.8103.38: the new tab page Iris uses (chrome://new-tab-page-third-party, DuckDuckGo default)
# paints its own background: the HTML bakes colorBackground at creation (new_tab_page_third_party_ui.cc) and the page
# re-applies theme.colorBackground from NewTabPageThirdPartyHandler::NotifyAboutTheme(). Both read
# web_contents->GetColorProvider(), and a new tab's WebContents is created BEFORE it joins the browser window, so that
# first colour is the plain default (white/black, following GNOME), not the Iris palette -> a flash until the page is
# re-themed. Stock Chromium's default new tab colour IS white/black, so the same moment is invisible there.
# Iris v2 (2026-11-08): the baked colours (background, text, dark/light) come from the WINDOW the new tab opens in
# (the profile's last active browser window, its widget's ColorProvider), so the first paint is already the Iris
# palette (no flash). Theme updates (handler) use the page's own colours again: the tab is in its window by then.
# Transparent only in the see-through glass window (pref iris.glass.window), as apply-glass-window.sh did.
# v1 (0.0.0.11, 0.0.0.12) was always "transparent": outside glass mode the renderer's base colour under the page is
# white, so with Iris DARK the new tab page was white (only Iris light had been tested; jegly 2026-11-08).
# Fallback when no window of the profile is active yet (first window): the tab's own colours, as upstream.
# STATUS v2 2026-11-08: copy-tested; compile-proof before a build. Test: Iris dark + light, GNOME dark + light, glass
# on/off, a palette, a new window (Ctrl+N), incognito.
# Needs apply-glass-window (anchor). Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PYEOF'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

UI = "chrome/browser/ui/webui/new_tab_page_third_party/new_tab_page_third_party_ui.cc"
edit(UI,
     "#include \"chrome/browser/ui/webui/ntp/ntp_resource_cache.h\"\n"
     "#include \"chrome/browser/ui/webui/util/webui_util_desktop.h\"\n#endif\n",
     "#include \"chrome/browser/ui/webui/ntp/ntp_resource_cache.h\"\n"
     "#include \"chrome/browser/ui/webui/util/webui_util_desktop.h\"\n"
     "// Iris (apply-ntp-no-flash.sh): the colours of the window the new tab opens in.\n"
     "#include \"chrome/browser/ui/browser_window/public/browser_window_interface.h\"\n"
     "#include \"chrome/browser/ui/browser_window/public/global_browser_collection.h\"\n"
     "#include \"ui/base/base_window.h\"\n"
     "#include \"ui/views/widget/widget.h\"\n#endif\n",
     "// Iris (apply-ntp-no-flash.sh): the colours of the window", "includes")
edit(UI,
     "namespace {\nvoid CreateAndAddNewTabPageThirdPartyUiHtmlSource(Profile* profile,\n",
     "namespace {\n"
     "#if !BUILDFLAG(IS_ANDROID)\n"
     "// Iris (apply-ntp-no-flash.sh): a new tab's WebContents gets its colours only when it joins the\n"
     "// window, so its own ColorProvider is still the plain default (white/black) here. Use the colours\n"
     "// of the profile's active window instead (the window the tab opens in); nullptr if there is none.\n"
     "const ui::ColorProvider* IrisWindowColorProvider(Profile* profile) {\n"
     "  BrowserWindowInterface* browser =\n"
     "      GlobalBrowserCollection::GetInstance()->GetLastActiveBrowser();\n"
     "  if (!browser || browser->GetProfile() != profile || !browser->GetWindow()) {\n"
     "    return nullptr;\n"
     "  }\n"
     "  views::Widget* widget = views::Widget::GetWidgetForNativeWindow(\n"
     "      browser->GetWindow()->GetNativeWindow());\n"
     "  return widget ? widget->GetColorProvider() : nullptr;\n"
     "}\n"
     "#endif  // !BUILDFLAG(IS_ANDROID)\n\n"
     "void CreateAndAddNewTabPageThirdPartyUiHtmlSource(Profile* profile,\n",
     "const ui::ColorProvider* IrisWindowColorProvider(Profile* profile) {", "window colour helper")
edit(UI,
     "  if (theme_provider) {\n"
     "    const ui::ColorProvider& color_provider = web_contents->GetColorProvider();\n",
     "  if (theme_provider) {\n"
     "    // Iris (apply-ntp-no-flash.sh): the window's colours, else the tab's own.\n"
     "    const ui::ColorProvider* iris_window_colors = IrisWindowColorProvider(profile);\n"
     "    const ui::ColorProvider& color_provider =\n"
     "        iris_window_colors ? *iris_window_colors : web_contents->GetColorProvider();\n",
     "// Iris (apply-ntp-no-flash.sh): the window's colours, else the tab's own.", "baked colours from the window")
edit(UI,
     "    // Iris: see-through glass window -> transparent new tab page\n"
     "    // (apply-glass-window.sh).\n"
     "    source->AddString(\n"
     "        \"colorBackground\",\n"
     "        profile->GetPrefs()->GetBoolean(\"iris.glass.window\")\n"
     "            ? std::string(\"transparent\")\n"
     "            : color_utils::SkColorToRgbaString(GetThemeColor(\n"
     "                  webui::GetNativeThemeDeprecated(web_contents),\n"
     "                  color_provider, kColorNewTabPageBackground)));\n",
     "    // Iris: see-through glass window -> transparent new tab page\n"
     "    // (apply-glass-window.sh); otherwise the window's new tab colour (apply-ntp-no-flash.sh).\n"
     "    source->AddString(\n"
     "        \"colorBackground\",\n"
     "        profile->GetPrefs()->GetBoolean(\"iris.glass.window\")\n"
     "            ? std::string(\"transparent\")\n"
     "            : color_utils::SkColorToRgbaString(\n"
     "                  color_provider.GetColor(kColorNewTabPageBackground)));\n",
     "otherwise the window's new tab colour (apply-ntp-no-flash.sh)", "baked background")
edit("chrome/browser/ui/webui/new_tab_page_third_party/new_tab_page_third_party_handler.cc",
     "  theme->color_background = color_utils::SkColorToRgbaString(GetThemeColor(\n"
     "      webui::GetNativeThemeDeprecated(web_contents_),\n"
     "      web_contents_->GetColorProvider(), kColorNewTabPageBackground));\n"
     "  if (theme_provider->HasCustomImage(IDR_THEME_NTP_BACKGROUND)) {\n",
     "  // Iris (apply-ntp-no-flash.sh): transparent only in the see-through glass window;\n"
     "  // the tab is in its window by now, so its own colours are the themed ones.\n"
     "  theme->color_background =\n"
     "      profile_->GetPrefs()->GetBoolean(\"iris.glass.window\")\n"
     "          ? std::string(\"transparent\")\n"
     "          : color_utils::SkColorToRgbaString(GetThemeColor(\n"
     "                webui::GetNativeThemeDeprecated(web_contents_),\n"
     "                web_contents_->GetColorProvider(), kColorNewTabPageBackground));\n"
     "  if (theme_provider->HasCustomImage(IDR_THEME_NTP_BACKGROUND)) {\n",
     "// Iris (apply-ntp-no-flash.sh): transparent only in the see-through glass window;", "theme updates")
PYEOF
echo "=== new tab page without flash complete ==="
