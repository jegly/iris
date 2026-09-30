#!/usr/bin/env bash
# Iris — quick browser-identity switcher in Page Info (jegly 2026-09-30, verified against this checkout).
# Lock icon -> "Browser identity  <current>" row -> menu: Iris (default) / Firefox on Linux / Chrome on Windows /
# Safari on macOS. Picking one stores the site's IRIS_USER_AGENT website setting (same storage as Settings -> Site
# settings -> Browser identity, apply-user-agent.sh) and reloads the tab; iris::UserAgentTabHelper applies it in
# DidStartNavigation. http/https pages only. Desktop views only (Android Page Info is Java: Phase C).
# Re-uses the existing IDS_SETTINGS_IRIS_USER_AGENT* strings (no new grit IDs = no long rebuild; already translatable).
# Guarded; idempotent; fails loudly on drift. Needs apply-user-agent.sh + apply-forget-site.sh (iris_web_contents()).
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
if "iris_web_contents()" not in open("components/page_info/page_info.h").read(): die("run apply-forget-site.sh first")
if "IDS_SETTINGS_IRIS_USER_AGENT_SAFARI_MAC" not in open("chrome/app/settings_strings.grdp").read(): die("run apply-iris-permissions.sh first")
if "void SetUserAgentPreset(" not in open("chrome/browser/iris/iris_user_agent.h").read(): die("run apply-user-agent.sh first")

p = "chrome/browser/ui/views/page_info/page_info_main_view.cc"
edit(p, '#include "chrome/browser/browser_process.h"\n',
     '#include <array>\n'
     '#include "base/task/sequenced_task_runner.h"\n'
     '#include "chrome/browser/browser_process.h"\n'
     '#include "chrome/browser/iris/iris_user_agent.h"  // nogncheck  Iris (identity switcher)\n'
     '#include "chrome/grit/generated_resources.h"\n'
     '#include "content/public/browser/navigation_controller.h"\n'
     '#include "content/public/browser/web_contents.h"\n'
     '#include "ui/base/mojom/menu_source_type.mojom.h"\n'
     '#include "ui/menus/simple_menu_model.h"\n'
     '#include "ui/views/controls/menu/menu_runner.h"\n',
     "Iris (identity switcher)", "includes")

CLASS = r'''namespace {

// Iris: quick per-site browser identity switcher (apply-page-info-identity.sh).
struct IrisIdentityPreset {
  const char* id;
  int label_id;
};
constexpr auto kIrisIdentityPresets = std::to_array<IrisIdentityPreset>({
    {"", IDS_SETTINGS_IRIS_USER_AGENT_DEFAULT},
    {"firefox_linux", IDS_SETTINGS_IRIS_USER_AGENT_FIREFOX_LINUX},
    {"chrome_windows", IDS_SETTINGS_IRIS_USER_AGENT_CHROME_WINDOWS},
    {"safari_mac", IDS_SETTINGS_IRIS_USER_AGENT_SAFARI_MAC},
});

class IrisIdentityButton : public RichHoverButton,
                           public ui::SimpleMenuModel::Delegate {
  METADATA_HEADER(IrisIdentityButton, RichHoverButton)

 public:
  IrisIdentityButton(content::WebContents* web_contents, const GURL& url)
      : RichHoverButton(base::BindRepeating(&IrisIdentityButton::ShowMenu,
                                            base::Unretained(this)),
                        PageInfoViewFactory::GetImageModel(
                            vector_icons::kIdCardIcon),
                        l10n_util::GetStringUTF16(IDS_SETTINGS_IRIS_USER_AGENT),
                        std::u16string(),
                        PageInfoViewFactory::GetOpenSubpageIcon()),
        web_contents_(web_contents->GetWeakPtr()),
        url_(url),
        menu_model_(this) {
    int command_id = 0;
    for (const auto& preset : kIrisIdentityPresets) {
      menu_model_.AddRadioItemWithStringId(command_id++, preset.label_id, 0);
    }
    SetTitleTextStyleAndColor(views::style::STYLE_BODY_3_MEDIUM,
                              kColorPageInfoForeground);
    SetSubtitleTextStyleAndColor(views::style::STYLE_BODY_4,
                                 kColorPageInfoSubtitleForeground);
    UpdateSubtitle();
  }

  // ui::SimpleMenuModel::Delegate:
  bool IsCommandIdChecked(int command_id) const override {
    return CurrentPreset() ==
           kIrisIdentityPresets.at(static_cast<size_t>(command_id)).id;
  }
  void ExecuteCommand(int command_id, int event_flags) override {
    if (!web_contents_) {
      return;
    }
    iris::SetUserAgentPreset(web_contents_->GetBrowserContext(), url_,
                             kIrisIdentityPresets.at(static_cast<size_t>(command_id)).id);
    UpdateSubtitle();
    // Reload outside the menu callback; the reload closes this bubble.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<content::WebContents> contents) {
                         if (contents) {
                           contents->GetController().Reload(
                               content::ReloadType::NORMAL, true);
                         }
                       },
                       web_contents_));
  }

 private:
  std::string CurrentPreset() const {
    return web_contents_ ? iris::GetUserAgentPreset(
                               web_contents_->GetBrowserContext(), url_)
                         : std::string();
  }

  void UpdateSubtitle() {
    const std::string current = CurrentPreset();
    for (const auto& preset : kIrisIdentityPresets) {
      if (current == preset.id) {
        SetSubtitleText(l10n_util::GetStringUTF16(preset.label_id));
        return;
      }
    }
  }

  void ShowMenu() {
    menu_runner_ = std::make_unique<views::MenuRunner>(
        &menu_model_, views::MenuRunner::CONTEXT_MENU);
    menu_runner_->RunMenuAt(GetWidget(), nullptr, GetBoundsInScreen(),
                            views::MenuAnchorPosition::kTopLeft,
                            ui::mojom::MenuSourceType::kNone);
  }

  base::WeakPtr<content::WebContents> web_contents_;
  const GURL url_;
  ui::SimpleMenuModel menu_model_;
  std::unique_ptr<views::MenuRunner> menu_runner_;
};

BEGIN_METADATA(IrisIdentityButton)
END_METADATA

}  // namespace

PageInfoMainView::PageInfoMainView(
'''
edit(p, "PageInfoMainView::PageInfoMainView(\n", CLASS, "class IrisIdentityButton", "IrisIdentityButton class")
edit(p, "  site_settings_view_ = AddChildView(CreateContainerView());\n",
     "  site_settings_view_ = AddChildView(CreateContainerView());\n\n"
     "  // Iris: quick per-site browser identity switcher (apply-page-info-identity.sh).\n"
     "  if (presenter_->iris_web_contents() &&\n"
     "      presenter_->site_url().SchemeIsHTTPOrHTTPS()) {\n"
     "    site_settings_view_->AddChildView(std::make_unique<IrisIdentityButton>(\n"
     "        presenter_->iris_web_contents(), presenter_->site_url()));\n"
     "  }\n",
     "std::make_unique<IrisIdentityButton>", "row in the main view")
PY
echo "=== Page Info identity switcher complete ==="
