#!/usr/bin/env bash
# Iris — no white/black flash when opening a new tab (jegly 2026-11-06: "+ new tab ... flashes" - black with GNOME
# dark, pure white with GNOME light, with an Iris palette; stock Chromium shows no visible flash).
# Verified against 157.0.8103.38: the new tab page Iris uses (chrome://new-tab-page-third-party, DuckDuckGo default)
# paints its own background: the HTML bakes colorBackground at creation (new_tab_page_third_party_ui.cc) and the page
# re-applies theme.colorBackground from NewTabPageThirdPartyHandler::NotifyAboutTheme(). Both read
# web_contents->GetColorProvider(), and a new tab's WebContents is created BEFORE it joins the browser window, so that
# first colour is the plain default (white/black, following GNOME), not the Iris palette -> a flash until the page is
# re-themed. Stock Chromium's default new tab colour IS white/black, so the same moment is invisible there.
# Iris: the page background is always transparent, so the tab area shows through: ContentsWebView paints
# kColorWebContentsBackground (= the themed new tab colour, chrome_color_mixer.cc) from the WINDOW's colours and
# re-paints on every theme change and tab attach (apply-glass-window.sh calls UpdateBackgroundColor on attach). Custom
# background images are unaffected (background-image). Also what the see-through glass window needs (replaces
# apply-glass-window.sh's "glass -> transparent" choice for the baked colour).
# STATUS 2026-11-06: copy-tested on 157 copies; compile-proven after apply. Behaviour to confirm on the signed build.
# Needs apply-glass-window (anchor). Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
edit("chrome/browser/ui/webui/new_tab_page_third_party/new_tab_page_third_party_ui.cc",
     "    // Iris: see-through glass window -> transparent new tab page\n"
     "    // (apply-glass-window.sh).\n"
     "    source->AddString(\n"
     "        \"colorBackground\",\n"
     "        profile->GetPrefs()->GetBoolean(\"iris.glass.window\")\n"
     "            ? std::string(\"transparent\")\n"
     "            : color_utils::SkColorToRgbaString(GetThemeColor(\n"
     "                  webui::GetNativeThemeDeprecated(web_contents),\n"
     "                  color_provider, kColorNewTabPageBackground)));\n",
     "    // Iris (apply-ntp-no-flash.sh): always transparent; the tab area behind it is\n"
     "    // painted in the themed new tab colour from the window's colours. Baking the\n"
     "    // colour here used the tab's colours from before it joined the window (white\n"
     "    // or black) -> a flash with Iris palettes. Also covers the\n"
     "    // see-through glass window -> transparent new tab page (apply-glass-window.sh).\n"
     "    source->AddString(\"colorBackground\", \"transparent\");\n",
     "// Iris (apply-ntp-no-flash.sh): always transparent", "baked background transparent")
edit("chrome/browser/ui/webui/new_tab_page_third_party/new_tab_page_third_party_handler.cc",
     "  theme->color_background = color_utils::SkColorToRgbaString(GetThemeColor(\n"
     "      webui::GetNativeThemeDeprecated(web_contents_),\n"
     "      web_contents_->GetColorProvider(), kColorNewTabPageBackground));\n"
     "  if (theme_provider->HasCustomImage(IDR_THEME_NTP_BACKGROUND)) {\n",
     "  // Iris (apply-ntp-no-flash.sh): transparent, the tab area shows the themed\n"
     "  // colour (see new_tab_page_third_party_ui.cc).\n"
     "  theme->color_background = \"transparent\";\n"
     "  if (theme_provider->HasCustomImage(IDR_THEME_NTP_BACKGROUND)) {\n",
     "// Iris (apply-ntp-no-flash.sh): transparent", "theme updates transparent")
PY
echo "=== new tab page without flash complete ==="
