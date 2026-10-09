// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/views/toolbar/iris_toolbar_buttons.h"

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/time/time.h"
#include "chrome/app/vector_icons/vector_icons.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_remover_constants.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/iris/iris_app_lock.h"  // nogncheck
#include "chrome/browser/iris/iris_fingerprint_host.h"  // nogncheck
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/chrome_pages.h"
#include "chrome/browser/ui/views/location_bar/location_bar_bubble_delegate_view.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/toolbar/toolbar_button.h"
#include "chrome/common/url_constants.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browsing_data_remover.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/models/simple_combobox_model.h"
#include "ui/color/color_id.h"
#include "ui/color/color_provider.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/views/accessibility/view_accessibility.h"
#include "ui/views/bubble/bubble_anchor.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"
#include "ui/views/controls/button/checkbox.h"
#include "ui/views/controls/combobox/combobox.h"
#include "ui/views/controls/label.h"
#include "ui/views/controls/link.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/style/typography.h"
#include "ui/views/widget/widget.h"
#include "url/gurl.h"

namespace {

constexpr base::TimeDelta kArmedFor = base::Seconds(4);

std::u16string CountText(int count) {
  if (count <= 0) {
    return std::u16string();
  }
  return count > 99 ? u"99+" : base::NumberToString16(count);
}

void ReloadTab(content::WebContents* web_contents) {
  if (web_contents) {
    web_contents->GetController().Reload(content::ReloadType::NORMAL, true);
  }
}

}  // namespace

// The panel that opens from the shield button.
class IrisShieldBubble : public LocationBarBubbleDelegateView,
                         public iris::ShieldStats::Observer {
  METADATA_HEADER(IrisShieldBubble, LocationBarBubbleDelegateView)

 public:
  static void Show(views::View* anchor,
                   BrowserWindowInterface* browser,
                   content::WebContents* web_contents) {
    auto bubble = std::make_unique<IrisShieldBubble>(anchor, browser, web_contents);
    IrisShieldBubble* raw_bubble = bubble.get();
    views::BubbleDialogDelegateView::CreateBubble(std::move(bubble));
    raw_bubble->ShowForReason(LocationBarBubbleDelegateView::USER_GESTURE);
  }

  IrisShieldBubble(views::View* anchor,
                   BrowserWindowInterface* browser,
                   content::WebContents* web_contents)
      : LocationBarBubbleDelegateView(anchor, web_contents),
        browser_(browser),
        web_contents_(web_contents->GetWeakPtr()),
        stats_(iris::ShieldStats::FromWebContents(web_contents)) {
    SetButtons(static_cast<int>(ui::mojom::DialogButton::kNone));
    set_margins(gfx::Insets(16));
    SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kVertical, gfx::Insets(), 8));

    AddChildView(std::make_unique<views::Label>(
        u"Iris shield", views::style::CONTEXT_DIALOG_TITLE));
    total_ = AddChildView(std::make_unique<views::Label>());
    total_->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    ads_ = AddChildView(std::make_unique<views::Label>());
    ads_->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    cookies_ = AddChildView(std::make_unique<views::Label>());
    cookies_->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    fingerprints_ = AddChildView(std::make_unique<views::Label>());
    fingerprints_->SetHorizontalAlignment(gfx::ALIGN_LEFT);

    const GURL url = web_contents->GetLastCommittedURL();
    const bool web = url.SchemeIsHTTPOrHTTPS();

    ads_switch_ = AddChildView(std::make_unique<views::Checkbox>(
        u"Block ads and trackers on this site",
        base::BindRepeating(&IrisShieldBubble::OnAdsChanged,
                            base::Unretained(this))));
    ads_switch_->SetEnabled(web);
    if (web) {
      HostContentSettingsMap* map =
          HostContentSettingsMapFactory::GetForProfile(browser->GetProfile());
      ads_switch_->SetChecked(
          map->GetContentSetting(url, url, ContentSettingsType::ADS) !=
          CONTENT_SETTING_ALLOW);
    }

    AddChildView(std::make_unique<views::Label>(
        u"Canvas and audio reading on this site"));
    std::vector<ui::SimpleComboboxModel::Item> items;
    items.emplace_back(u"Protected (small random changes)");
    items.emplace_back(u"Real (nothing changed)");
    items.emplace_back(u"Blank (empty data)");
    fingerprint_box_ = AddChildView(std::make_unique<views::Combobox>(
        std::make_unique<ui::SimpleComboboxModel>(std::move(items))));
    fingerprint_box_->GetViewAccessibility().SetName(
        u"Canvas and audio reading");
    fingerprint_box_->SetEnabled(web);
    if (web) {
      const std::string preset =
          iris::GetFingerprintReadsPreset(browser->GetProfile(), url);
      fingerprint_box_->SetSelectedIndex(preset == "real"    ? 1
                                         : preset == "blank" ? 2
                                                             : 0);
    }
    fingerprint_box_->SetCallback(base::BindRepeating(
        &IrisShieldBubble::OnFingerprintChanged, base::Unretained(this)));

    auto* link = AddChildView(
        std::make_unique<views::Link>(u"Iris hardening settings"));
    link->SetCallback(base::BindRepeating(&IrisShieldBubble::OpenSettings,
                                          base::Unretained(this)));
    link->SetHorizontalAlignment(gfx::ALIGN_LEFT);

    if (stats_) {
      stats_->AddObserver(this);
    }
    UpdateCounts();
  }

  ~IrisShieldBubble() override {
    if (stats_) {
      stats_->RemoveObserver(this);
    }
  }

  // iris::ShieldStats::Observer:
  void OnShieldStatsChanged() override { UpdateCounts(); }

 private:
  void UpdateCounts() {
    if (!stats_) {
      return;
    }
    total_->SetText(base::NumberToString16(stats_->total()) +
                    u" blocked on this page");
    ads_->SetText(u"Ads and trackers: " + base::NumberToString16(stats_->ads()));
    cookies_->SetText(u"Cookies: " + base::NumberToString16(stats_->cookies()));
    fingerprints_->SetText(u"Fingerprint reads protected: " +
                           base::NumberToString16(stats_->fingerprints()));
  }

  void OnAdsChanged() {
    if (!web_contents_) {
      return;
    }
    const GURL url = web_contents_->GetLastCommittedURL();
    HostContentSettingsMap* map =
        HostContentSettingsMapFactory::GetForProfile(browser_->GetProfile());
    // Blocking is the default: "on" removes the exception, "off" allows ads here.
    map->SetContentSettingDefaultScope(
        url, GURL(), ContentSettingsType::ADS,
        ads_switch_->GetChecked() ? CONTENT_SETTING_DEFAULT
                                  : CONTENT_SETTING_ALLOW);
    ReloadTab(web_contents_.get());
  }

  void OnFingerprintChanged() {
    if (!web_contents_ || !fingerprint_box_->GetSelectedIndex()) {
      return;
    }
    const size_t index = *fingerprint_box_->GetSelectedIndex();
    iris::SetFingerprintReadsPreset(
        browser_->GetProfile(), web_contents_->GetLastCommittedURL(),
        index == 1 ? "real" : index == 2 ? "blank" : "protected");
    ReloadTab(web_contents_.get());
  }

  void OpenSettings() {
    chrome::ShowSettingsSubPage(browser_, "irisHardening");
    GetWidget()->Close();
  }

  raw_ptr<BrowserWindowInterface> browser_;
  base::WeakPtr<content::WebContents> web_contents_;
  raw_ptr<iris::ShieldStats> stats_;
  raw_ptr<views::Label> total_ = nullptr;
  raw_ptr<views::Label> ads_ = nullptr;
  raw_ptr<views::Label> cookies_ = nullptr;
  raw_ptr<views::Label> fingerprints_ = nullptr;
  raw_ptr<views::Checkbox> ads_switch_ = nullptr;
  raw_ptr<views::Combobox> fingerprint_box_ = nullptr;
};

BEGIN_METADATA(IrisShieldBubble)
END_METADATA

// IrisToolbarButtons ---------------------------------------------------------

IrisToolbarButtons::IrisToolbarButtons(BrowserWindowInterface* browser) : browser_(browser) {
  SetLayoutManager(std::make_unique<views::BoxLayout>(
      views::BoxLayout::Orientation::kHorizontal));

  auto make_button = [this](void (IrisToolbarButtons::*handler)(),
                            const gfx::VectorIcon& icon,
                            const std::u16string& name) {
    auto button = std::make_unique<ToolbarButton>(
        base::BindRepeating(handler, base::Unretained(this)));
    button->SetVectorIcon(icon);
    button->SetTooltipText(name);
    button->GetViewAccessibility().SetName(name);
    return AddChildView(std::move(button));
  };
  shield_ = make_button(&IrisToolbarButtons::OnShieldPressed, kIrisShieldIcon,
                        u"Iris shield");
  javascript_ = make_button(&IrisToolbarButtons::OnJavaScriptPressed,
                            kIrisJavascriptIcon, u"JavaScript on this site");
  new_identity_ = make_button(&IrisToolbarButtons::OnNewIdentityPressed,
                              kIrisFlameIcon, u"New identity");
  lock_ = make_button(&IrisToolbarButtons::OnLockPressed, kIrisLockIcon,
                      u"Lock and close Iris");

  browser_->GetTabStripModel()->AddObserver(this);
  pref_registrar_.Init(browser_->GetProfile()->GetPrefs());
  for (const char* pref :
       {kShieldPref, kJavaScriptPref, kNewIdentityPref, kLockPref}) {
    pref_registrar_.Add(pref,
                        base::BindRepeating(&IrisToolbarButtons::UpdateVisibility,
                                            base::Unretained(this)));
  }
  UpdateVisibility();
  BindToActiveTab();
}

IrisToolbarButtons::~IrisToolbarButtons() {
  if (stats_) {
    stats_->RemoveObserver(this);
  }
  browser_->GetTabStripModel()->RemoveObserver(this);
}

void IrisToolbarButtons::AddedToWidget() {
  UpdateAll();
}

void IrisToolbarButtons::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  if (selection.active_tab_changed()) {
    BindToActiveTab();
  }
}

void IrisToolbarButtons::DidFinishNavigation(
    content::NavigationHandle* handle) {
  if (handle->IsInPrimaryMainFrame() && handle->HasCommitted()) {
    UpdateJavaScript();
  }
}

void IrisToolbarButtons::OnShieldStatsChanged() {
  UpdateShield();
}

void IrisToolbarButtons::BindToActiveTab() {
  if (stats_) {
    stats_->RemoveObserver(this);
    stats_ = nullptr;
  }
  content::WebContents* web_contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  Observe(web_contents);
  if (web_contents) {
    stats_ = iris::ShieldStats::FromWebContents(web_contents);
    if (stats_) {
      stats_->AddObserver(this);
    }
  }
  UpdateAll();
}

void IrisToolbarButtons::UpdateAll() {
  UpdateShield();
  UpdateJavaScript();
}

void IrisToolbarButtons::UpdateVisibility() {
  PrefService* prefs = browser_->GetProfile()->GetPrefs();
  shield_->SetVisible(prefs->GetBoolean(kShieldPref));
  javascript_->SetVisible(prefs->GetBoolean(kJavaScriptPref));
  new_identity_->SetVisible(prefs->GetBoolean(kNewIdentityPref));
  lock_->SetVisible(prefs->GetBoolean(kLockPref) &&
                    g_browser_process->local_state() &&
                    iris_app_lock::IsEnabled(g_browser_process->local_state()));
}

void IrisToolbarButtons::UpdateShield() {
  shield_->SetHighlight(stats_ ? CountText(stats_->total()) : std::u16string(),
                        std::nullopt);
  if (stats_) {
    shield_->SetTooltipText(
        u"Iris shield: " + base::NumberToString16(stats_->total()) +
        u" blocked on this page");
  }
}

void IrisToolbarButtons::UpdateJavaScript() {
  content::WebContents* web_contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  const GURL url =
      web_contents ? web_contents->GetLastCommittedURL() : GURL();
  const bool web = url.SchemeIsHTTPOrHTTPS();
  javascript_->SetEnabled(web);
  if (!web) {
    javascript_->SetHighlight(std::u16string(), std::nullopt);
    return;
  }
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(browser_->GetProfile());
  const bool allowed =
      map->GetContentSetting(url, url, ContentSettingsType::JAVASCRIPT) !=
      CONTENT_SETTING_BLOCK;
  if (allowed) {
    javascript_->SetHighlight(std::u16string(), std::nullopt);
    javascript_->SetTooltipText(
        u"JavaScript is on for this site. Click to turn it off.");
  } else {
    std::optional<SkColor> color;
    if (GetWidget()) {
      color = GetColorProvider()->GetColor(ui::kColorAlertHighSeverity);
    }
    javascript_->SetHighlight(u"off", color);
    javascript_->SetTooltipText(
        u"JavaScript is off for this site. Click to turn it on.");
  }
}

void IrisToolbarButtons::OnShieldPressed() {
  content::WebContents* web_contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  if (web_contents) {
    IrisShieldBubble::Show(shield_, browser_, web_contents);
  }
}

void IrisToolbarButtons::OnJavaScriptPressed() {
  content::WebContents* web_contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  if (!web_contents) {
    return;
  }
  const GURL url = web_contents->GetLastCommittedURL();
  if (!url.SchemeIsHTTPOrHTTPS()) {
    return;
  }
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(browser_->GetProfile());
  const bool allowed =
      map->GetContentSetting(url, url, ContentSettingsType::JAVASCRIPT) !=
      CONTENT_SETTING_BLOCK;
  map->SetContentSettingDefaultScope(
      url, GURL(), ContentSettingsType::JAVASCRIPT,
      allowed ? CONTENT_SETTING_BLOCK : CONTENT_SETTING_ALLOW);
  UpdateJavaScript();
  ReloadTab(web_contents);
}

void IrisToolbarButtons::OnNewIdentityPressed() {
  if (!new_identity_armed_) {
    new_identity_armed_ = true;
    std::optional<SkColor> color;
    if (GetWidget()) {
      color = GetColorProvider()->GetColor(ui::kColorAlertHighSeverity);
    }
    new_identity_->SetHighlight(u"Click again", color);
    new_identity_->SetTooltipText(
        u"Click again to erase site data, cache, history and downloads, "
        u"close the other tabs and start fresh.");
    disarm_timer_.Start(FROM_HERE, kArmedFor,
                        base::BindOnce(&IrisToolbarButtons::DisarmNewIdentity,
                                       base::Unretained(this)));
    return;
  }
  DisarmNewIdentity();

  Profile* profile = browser_->GetProfile();
  profile->GetBrowsingDataRemover()->Remove(
      base::Time(), base::Time::Max(),
      chrome_browsing_data_remover::DATA_TYPE_SITE_DATA |
          chrome_browsing_data_remover::DATA_TYPE_HISTORY |
          content::BrowsingDataRemover::DATA_TYPE_CACHE |
          content::BrowsingDataRemover::DATA_TYPE_DOWNLOADS,
      content::BrowsingDataRemover::ORIGIN_TYPE_UNPROTECTED_WEB |
          content::BrowsingDataRemover::ORIGIN_TYPE_PROTECTED_WEB);
  iris::RerollFingerprintSeed();

  TabStripModel* model = browser_->GetTabStripModel();
  chrome::AddAndReturnTabAt(browser_, GURL(chrome::kChromeUINewTabURL), -1,
                            true);
  for (int i = model->count() - 2; i >= 0; --i) {
    model->CloseWebContentsAt(i, TabCloseTypes::CLOSE_NONE);
  }
}

void IrisToolbarButtons::DisarmNewIdentity() {
  disarm_timer_.Stop();
  new_identity_armed_ = false;
  new_identity_->SetHighlight(std::u16string(), std::nullopt);
  new_identity_->SetTooltipText(u"New identity");
}

void IrisToolbarButtons::OnLockPressed() {
  chrome::AttemptUserExit();
}

BEGIN_METADATA(IrisToolbarButtons)
END_METADATA
