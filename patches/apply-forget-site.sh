#!/usr/bin/env bash
# Iris — Phase B6: "Forget this site when I close Iris" (verified against this checkout 2026-09-27).
# A toggle in Page Info -> "Cookies and site data" (chrome/browser/ui/views/page_info/page_info_cookies_content_view.*).
# On = the site's cookie setting becomes CONTENT_SETTING_SESSION_ONLY, Chromium's built-in "delete on exit": the site's
# cookies and site storage are removed when Iris closes. Off = the exception is removed (back to the default).
# Same setting as Settings -> Privacy -> Third-party cookies -> "Sites that clear cookies when you close all windows".
# Strings IDS_PAGE_INFO_IRIS_FORGET_SITE{,_ON} come from apply-iris-permissions.sh (run it first).
# PageInfo gets a small public accessor for its WebContents (components/page_info/page_info.h).
# Guarded; idempotent; fails loudly on drift.
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
if "IDS_PAGE_INFO_IRIS_FORGET_SITE" not in open("components/page_info_strings.grdp").read():
    die("strings missing: run apply-iris-permissions.sh first")

edit("components/page_info/page_info.h",
     "  const GURL& site_url() const { return site_url_; }\n",
     "  const GURL& site_url() const { return site_url_; }\n"
     "  // Iris: used by the \"Forget this site\" toggle (apply-forget-site.sh).\n"
     "  content::WebContents* iris_web_contents() const {\n"
     "    return web_contents_.get();\n  }\n",
     "iris_web_contents()", "PageInfo WebContents accessor")

h = "chrome/browser/ui/views/page_info/page_info_cookies_content_view.h"
edit(h, "  raw_ptr<PageInfo, DanglingUntriaged> presenter_ = nullptr;\n",
     "  raw_ptr<PageInfo, DanglingUntriaged> presenter_ = nullptr;\n\n"
     "  // Iris (B6): \"Forget this site when I close Iris\".\n"
     "  void AddIrisForgetSiteRow();\n"
     "  void OnIrisForgetSiteToggled();\n"
     "  raw_ptr<views::ToggleButton> iris_forget_site_toggle_ = nullptr;\n"
     "  raw_ptr<views::Label> iris_forget_site_note_ = nullptr;\n",
     "AddIrisForgetSiteRow", "declarations")

c = "chrome/browser/ui/views/page_info/page_info_cookies_content_view.cc"
edit(c, "#include \"chrome/browser/ui/views/page_info/page_info_main_view.h\"\n",
     "#include \"chrome/browser/ui/views/page_info/page_info_main_view.h\"\n"
     "#include \"chrome/app/vector_icons/vector_icons.h\"  // Iris: kDeleteIcon\n"
     "#include \"chrome/browser/content_settings/host_content_settings_map_factory.h\"  // Iris\n"
     "#include \"components/content_settings/core/browser/host_content_settings_map.h\"  // Iris\n"
     "#include \"content/public/browser/web_contents.h\"  // Iris\n",
     "// Iris: kDeleteIcon", "includes")
edit(c, "  AddThirdPartyCookiesContainer();\n\n#if BUILDFLAG(IS_CHROMEOS)\n  MaybeAddSyncDisclaimer();\n",
     "  AddThirdPartyCookiesContainer();\n  AddIrisForgetSiteRow();  // Iris (B6)\n\n"
     "#if BUILDFLAG(IS_CHROMEOS)\n  MaybeAddSyncDisclaimer();\n",
     "  AddIrisForgetSiteRow();  // Iris (B6)", "row added to the page")
impl = '''
// Iris (B6): "Forget this site when I close Iris" = cookie setting SESSION_ONLY
// ("delete on exit") for this site; off removes the exception.
void PageInfoCookiesContentView::AddIrisForgetSiteRow() {
  content::WebContents* web_contents = presenter_->iris_web_contents();
  const GURL& site = presenter_->site_url();
  if (!web_contents || !site.SchemeIsHTTPOrHTTPS()) {
    return;
  }
  HostContentSettingsMap* map = HostContentSettingsMapFactory::GetForProfile(
      web_contents->GetBrowserContext());
  if (!map) {
    return;
  }
  auto* row = AddChildView(std::make_unique<RichControlsContainerView>());
  const std::u16string title =
      l10n_util::GetStringUTF16(IDS_PAGE_INFO_IRIS_FORGET_SITE);
  row->SetTitle(title);
  row->SetIcon(PageInfoViewFactory::GetImageModel(kDeleteIcon));
  row->SetTitleTextStyleAndColor(views::style::STYLE_BODY_3_MEDIUM,
                                 kColorPageInfoForeground);
  iris_forget_site_note_ = row->AddSecondaryLabel(
      l10n_util::GetStringUTF16(IDS_PAGE_INFO_IRIS_FORGET_SITE_ON));
  iris_forget_site_note_->SetTextStyle(views::style::STYLE_BODY_4);
  iris_forget_site_note_->SetEnabledColor(kColorPageInfoSubtitleForeground);
  iris_forget_site_toggle_ = row->AddControl(
      std::make_unique<views::ToggleButton>(base::BindRepeating(
          &PageInfoCookiesContentView::OnIrisForgetSiteToggled,
          base::Unretained(this))));
  iris_forget_site_toggle_->GetViewAccessibility().SetName(title);
  const bool on = map->GetContentSetting(site, site,
                                         ContentSettingsType::COOKIES) ==
                  CONTENT_SETTING_SESSION_ONLY;
  iris_forget_site_toggle_->SetIsOn(on);
  iris_forget_site_note_->SetVisible(on);
}

void PageInfoCookiesContentView::OnIrisForgetSiteToggled() {
  content::WebContents* web_contents = presenter_->iris_web_contents();
  if (!web_contents || !iris_forget_site_toggle_) {
    return;
  }
  HostContentSettingsMap* map = HostContentSettingsMapFactory::GetForProfile(
      web_contents->GetBrowserContext());
  if (!map) {
    return;
  }
  const bool on = iris_forget_site_toggle_->GetIsOn();
  map->SetContentSettingDefaultScope(
      presenter_->site_url(), GURL(), ContentSettingsType::COOKIES,
      on ? CONTENT_SETTING_SESSION_ONLY : CONTENT_SETTING_DEFAULT);
  iris_forget_site_note_->SetVisible(on);
  PreferredSizeChanged();
}
'''
edit(c, "PageInfoCookiesContentView::~PageInfoCookiesContentView() = default;\n",
     "PageInfoCookiesContentView::~PageInfoCookiesContentView() = default;\n" + impl,
     "void PageInfoCookiesContentView::AddIrisForgetSiteRow()", "row implementation")
PY
echo "=== forget a site complete ==="
