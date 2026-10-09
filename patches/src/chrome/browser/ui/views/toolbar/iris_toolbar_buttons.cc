// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/views/toolbar/iris_toolbar_buttons.h"

#include <array>
#include <memory>
#include <string>
#include <string_view>
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
#include "chrome/browser/content_settings/cookie_settings_factory.h"
#include "chrome/browser/iris/iris_tls_info.h"  // nogncheck
#include "components/content_settings/core/browser/cookie_settings.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "ui/base/models/image_model.h"
#include "ui/views/background.h"
#include "ui/views/controls/button/md_text_button.h"
#include "ui/views/controls/button/toggle_button.h"
#include "ui/views/controls/image_view.h"
#include "ui/views/controls/separator.h"
#include "ui/views/view_class_properties.h"
#include "ui/views/layout/fill_layout.h"
#include "ui/views/controls/scroll_view.h"
#include "chrome/browser/iris/iris_app_lock.h"  // nogncheck
#include "chrome/browser/iris/iris_fingerprint_host.h"  // nogncheck
#include "chrome/browser/iris/iris_user_agent.h"  // nogncheck
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
#include "ui/views/view_tracker.h"
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

// The panel that opens from the shield button: one place for everything Iris does for the current site.
// Compact on purpose; the content sits in a scroll view capped in height so nothing is ever cut off.
class IrisShieldBubble : public LocationBarBubbleDelegateView,
                         public iris::ShieldStats::Observer {
  METADATA_HEADER(IrisShieldBubble, LocationBarBubbleDelegateView)

 public:
  static IrisShieldBubble* Show(views::View* anchor,
                                BrowserWindowInterface* browser,
                                content::WebContents* web_contents,
                                base::OnceClosure on_closed) {
    auto bubble = std::make_unique<IrisShieldBubble>(anchor, browser,
                                                     web_contents);
    IrisShieldBubble* raw_bubble = bubble.get();
    raw_bubble->on_closed_ = std::move(on_closed);
    views::BubbleDialogDelegateView::CreateBubble(std::move(bubble));
    raw_bubble->ShowForReason(LocationBarBubbleDelegateView::USER_GESTURE);
    return raw_bubble;
  }

  IrisShieldBubble(views::View* anchor,
                   BrowserWindowInterface* browser,
                   content::WebContents* web_contents)
      : LocationBarBubbleDelegateView(anchor, web_contents),
        browser_(browser),
        web_contents_(web_contents->GetWeakPtr()),
        stats_(iris::ShieldStats::FromWebContents(web_contents)),
        url_(web_contents->GetLastCommittedURL()),
        web_(url_.SchemeIsHTTPOrHTTPS()) {
    SetButtons(static_cast<int>(ui::mojom::DialogButton::kNone));
    set_margins(gfx::Insets::VH(12, 14));
    set_fixed_width(332);
    SetLayoutManager(std::make_unique<views::FillLayout>());
    auto* scroll = AddChildView(std::make_unique<views::ScrollView>());
    scroll->SetHorizontalScrollBarMode(
        views::ScrollView::ScrollBarMode::kDisabled);
    scroll->ClipHeightTo(0, kMaxHeight);
    body_ = scroll->SetContents(std::make_unique<views::View>());
    body_->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kVertical, gfx::Insets(), 4));

    BuildHeader();
    BuildCounts();
    BuildSiteControls();
    BuildConnection(web_contents);
    BuildFooter();

    if (stats_) {
      stats_->AddObserver(this);
    }
    UpdateCounts();
    SyncControls();
  }

  ~IrisShieldBubble() override {
    if (stats_) {
      stats_->RemoveObserver(this);
    }
    if (on_closed_) {
      std::move(on_closed_).Run();
    }
  }

  // iris::ShieldStats::Observer:
  void OnShieldStatsChanged() override { UpdateCounts(); }

 private:
  static constexpr int kMaxHeight = 600;

  static void Bold(views::Label* label, int size_delta) {
    label->SetFontList(label->font_list().Derive(
        size_delta, gfx::Font::NORMAL, gfx::Font::Weight::BOLD));
  }

  static views::Label* AddSecondary(views::View* parent,
                                    const std::u16string& text) {
    auto* label = parent->AddChildView(std::make_unique<views::Label>(
        text, views::style::CONTEXT_LABEL, views::style::STYLE_SECONDARY));
    label->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    return label;
  }

  void AddSection(const std::u16string& title) {
    auto* separator = body_->AddChildView(std::make_unique<views::Separator>());
    separator->SetProperty(views::kMarginsKey, gfx::Insets::VH(4, 0));
    auto* label = AddSecondary(body_, title);
    Bold(label, 0);
  }

  // One line: label on the left, switch on the right.
  views::ToggleButton* AddToggleRow(const std::u16string& text,
                                    base::RepeatingClosure callback) {
    auto* row = body_->AddChildView(std::make_unique<views::View>());
    auto* layout = row->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kHorizontal, gfx::Insets::VH(2, 0), 8));
    layout->set_cross_axis_alignment(
        views::BoxLayout::CrossAxisAlignment::kCenter);
    auto* label = row->AddChildView(std::make_unique<views::Label>(text));
    label->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    layout->SetFlexForView(label, 1);
    auto* toggle = row->AddChildView(std::make_unique<views::ToggleButton>(
        base::BindRepeating(
            [](base::RepeatingClosure closure) { closure.Run(); },
            std::move(callback))));
    toggle->GetViewAccessibility().SetName(text);
    toggle->SetEnabled(web_);
    return toggle;
  }

  // One line: label on the left, drop-down on the right.
  views::Combobox* AddComboRow(const std::u16string& text,
                               const std::vector<std::u16string>& items,
                               base::RepeatingClosure callback) {
    auto* row = body_->AddChildView(std::make_unique<views::View>());
    auto* layout = row->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kHorizontal, gfx::Insets::VH(2, 0), 8));
    layout->set_cross_axis_alignment(
        views::BoxLayout::CrossAxisAlignment::kCenter);
    auto* label = row->AddChildView(std::make_unique<views::Label>(text));
    label->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    layout->SetFlexForView(label, 1);
    std::vector<ui::SimpleComboboxModel::Item> model_items;
    for (const std::u16string& item : items) {
      model_items.emplace_back(item);
    }
    auto* box = row->AddChildView(std::make_unique<views::Combobox>(
        std::make_unique<ui::SimpleComboboxModel>(std::move(model_items))));
    box->GetViewAccessibility().SetName(text);
    box->SetEnabled(web_);
    box->SetCallback(std::move(callback));
    return box;
  }

  void BuildHeader() {
    auto* header = body_->AddChildView(std::make_unique<views::View>());
    auto* layout = header->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kHorizontal, gfx::Insets(), 10));
    layout->set_cross_axis_alignment(
        views::BoxLayout::CrossAxisAlignment::kCenter);
    header->AddChildView(std::make_unique<views::ImageView>(
        ui::ImageModel::FromVectorIcon(kIrisShieldIcon, ui::kColorSysPrimary,
                                       24)));
    auto* column = header->AddChildView(std::make_unique<views::View>());
    column->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kVertical));
    layout->SetFlexForView(column, 1);
    auto* host = column->AddChildView(std::make_unique<views::Label>(
        web_ ? base::UTF8ToUTF16(url_.host()) : u"This page"));
    host->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    host->SetElideBehavior(gfx::ELIDE_HEAD);
    Bold(host, 1);
    status_ = AddSecondary(column, u"");
    master_ = header->AddChildView(std::make_unique<views::ToggleButton>(
        base::BindRepeating(&IrisShieldBubble::OnMaster,
                            base::Unretained(this))));
    master_->GetViewAccessibility().SetName(u"Shield for this site");
    master_->SetEnabled(web_);
  }

  void BuildCounts() {
    auto* card = body_->AddChildView(std::make_unique<views::View>());
    card->SetProperty(views::kMarginsKey, gfx::Insets::VH(6, 0));
    card->SetBackground(views::CreateRoundedRectBackground(
        ui::kColorSysTonalContainer, 10));
    auto* layout = card->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kHorizontal, gfx::Insets::VH(8, 12),
        12));
    layout->set_cross_axis_alignment(
        views::BoxLayout::CrossAxisAlignment::kCenter);
    total_ = card->AddChildView(std::make_unique<views::Label>(u"0"));
    Bold(total_, 12);
    total_->SetEnabledColor(ui::kColorSysOnTonalContainer);
    auto* column = card->AddChildView(std::make_unique<views::View>());
    column->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kVertical));
    layout->SetFlexForView(column, 1);
    auto* caption = column->AddChildView(
        std::make_unique<views::Label>(u"blocked on this page"));
    caption->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    caption->SetEnabledColor(ui::kColorSysOnTonalContainer);
    breakdown_ = column->AddChildView(std::make_unique<views::Label>());
    breakdown_->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    breakdown_->SetEnabledColor(ui::kColorSysOnTonalContainer);
    lifetime_ = AddSecondary(body_, u"");
  }

  void BuildSiteControls() {
    AddSection(u"This site");
    ads_toggle_ = AddToggleRow(
        u"Block ads and trackers",
        base::BindRepeating(&IrisShieldBubble::OnAds, base::Unretained(this)));
    cookie_toggle_ = AddToggleRow(
        u"Block cross-site cookies",
        base::BindRepeating(&IrisShieldBubble::OnCookies,
                            base::Unretained(this)));
    js_toggle_ = AddToggleRow(
        u"JavaScript",
        base::BindRepeating(&IrisShieldBubble::OnJavaScript,
                            base::Unretained(this)));
    jit_toggle_ = AddToggleRow(
        u"JavaScript optimisation (faster, less secure)",
        base::BindRepeating(&IrisShieldBubble::OnJit, base::Unretained(this)));
    webgl_toggle_ = AddToggleRow(
        u"WebGL (3D graphics)",
        base::BindRepeating(&IrisShieldBubble::OnWebGL, base::Unretained(this)));
    signin_toggle_ = AddToggleRow(
        u"Google sign-in prompts",
        base::BindRepeating(&IrisShieldBubble::OnSignIn,
                            base::Unretained(this)));
    forget_toggle_ = AddToggleRow(
        u"Forget this site when I close Iris",
        base::BindRepeating(&IrisShieldBubble::OnForget,
                            base::Unretained(this)));
    fingerprint_box_ = AddComboRow(
        u"Canvas and audio", {u"Protected", u"Real", u"Blank"},
        base::BindRepeating(&IrisShieldBubble::OnFingerprint,
                            base::Unretained(this)));
    std::vector<std::u16string> names;
    for (const Identity& identity : kIdentities) {
      names.emplace_back(identity.name);
    }
    identity_box_ = AddComboRow(
        u"Browser identity", names,
        base::BindRepeating(&IrisShieldBubble::OnIdentity,
                            base::Unretained(this)));
  }

  // "Name: value (0x1234)" lines from iris::GetTlsDetailsText -> the value of the line starting with `prefix`,
  // without the code point.
  static std::u16string TlsValue(const std::vector<std::u16string>& lines,
                                 std::u16string_view prefix) {
    for (const std::u16string& line : lines) {
      if (line.starts_with(prefix)) {
        std::u16string value = line.substr(prefix.size());
        const size_t code = value.find(u" (0x");
        if (code != std::u16string::npos) {
          value.resize(code);
        }
        return value;
      }
    }
    return std::u16string();
  }

  void BuildConnection(content::WebContents* web_contents) {
    AddSection(u"Connection");
    const std::vector<std::u16string> lines = base::SplitString(
        iris::GetTlsDetailsText(web_contents), u"\n", base::TRIM_WHITESPACE,
        base::SPLIT_WANT_NONEMPTY);
    if (lines.empty()) {
      AddSecondary(body_, web_ ? u"Not encrypted" : u"No connection details");
      return;
    }
    // One summary line, the full list on demand.
    std::vector<std::u16string> parts;
    for (std::u16string_view prefix :
         {std::u16string_view(u"Protocol: "),
          std::u16string_view(u"Key exchange: ")}) {
      std::u16string value = TlsValue(lines, prefix);
      if (!value.empty()) {
        parts.push_back(std::move(value));
      }
    }
    const std::u16string ech = TlsValue(lines, u"Encrypted Client Hello: ");
    if (!ech.empty()) {
      parts.push_back(u"ECH " + ech);
    }
    auto* row = body_->AddChildView(std::make_unique<views::View>());
    auto* layout = row->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kHorizontal, gfx::Insets(), 8));
    auto* summary = AddSecondary(row, base::JoinString(parts, u" · "));
    summary->SetElideBehavior(gfx::ELIDE_TAIL);
    layout->SetFlexForView(summary, 1);
    details_link_ = row->AddChildView(std::make_unique<views::Link>(u"Details"));
    details_link_->SetCallback(base::BindRepeating(
        &IrisShieldBubble::ToggleDetails, base::Unretained(this)));
    details_ = body_->AddChildView(std::make_unique<views::View>());
    details_->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kVertical));
    for (const std::u16string& line : lines) {
      auto* label = AddSecondary(details_, line);
      label->SetMultiLine(true);
    }
    details_->SetVisible(false);
  }

  void BuildFooter() {
    auto* footer = body_->AddChildView(std::make_unique<views::View>());
    footer->SetProperty(views::kMarginsKey, gfx::Insets::TLBR(8, 0, 0, 0));
    auto* layout = footer->SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kHorizontal, gfx::Insets(), 12));
    layout->set_cross_axis_alignment(
        views::BoxLayout::CrossAxisAlignment::kCenter);
    auto* reset = footer->AddChildView(std::make_unique<views::MdTextButton>(
        base::BindRepeating(&IrisShieldBubble::OnReset, base::Unretained(this)),
        u"Reset this site"));
    reset->SetEnabled(web_);
    auto* link = footer->AddChildView(
        std::make_unique<views::Link>(u"Iris hardening settings"));
    link->SetCallback(base::BindRepeating(&IrisShieldBubble::OpenSettings,
                                          base::Unretained(this)));
    layout->SetFlexForView(link, 1);
    link->SetHorizontalAlignment(gfx::ALIGN_RIGHT);
  }

  void ToggleDetails() {
    const bool show = !details_->GetVisible();
    details_->SetVisible(show);
    details_link_->SetText(show ? u"Hide" : u"Details");
    SizeToContents();
  }

  // --- state ---------------------------------------------------------------

  HostContentSettingsMap* Map() {
    return HostContentSettingsMapFactory::GetForProfile(browser_->GetProfile());
  }

  scoped_refptr<content_settings::CookieSettings> Cookies() {
    return CookieSettingsFactory::GetForProfile(browser_->GetProfile());
  }

  ContentSetting Get(ContentSettingsType type) {
    return Map()->GetContentSetting(url_, url_, type);
  }

  void Set(ContentSettingsType type, ContentSetting setting) {
    Map()->SetContentSettingDefaultScope(url_, GURL(), type, setting);
  }

  void UpdateCounts() {
    if (!stats_) {
      return;
    }
    total_->SetText(base::NumberToString16(stats_->total()));
    breakdown_->SetText(base::NumberToString16(stats_->ads()) + u" ads, trackers · " +
                        base::NumberToString16(stats_->cookies()) + u" cookies · " +
                        base::NumberToString16(stats_->fingerprints()) +
                        u" fingerprints");
    lifetime_->SetText(base::NumberToString16(stats_->lifetime()) +
                       u" blocked since you started using Iris");
  }

  void SyncControls() {
    if (!web_) {
      status_->SetText(u"Not used on this page");
      return;
    }
    const bool ads_on = Get(ContentSettingsType::ADS) != CONTENT_SETTING_ALLOW;
    master_->SetIsOn(ads_on);
    status_->SetText(ads_on ? u"Shield is on" : u"Shield is off for this site");
    ads_toggle_->SetIsOn(ads_on);
    cookie_toggle_->SetIsOn(!Cookies()->IsThirdPartyAccessAllowed(url_));
    js_toggle_->SetIsOn(Get(ContentSettingsType::JAVASCRIPT) !=
                        CONTENT_SETTING_BLOCK);
    jit_toggle_->SetIsOn(Get(ContentSettingsType::JAVASCRIPT_JIT) ==
                         CONTENT_SETTING_ALLOW);
    webgl_toggle_->SetIsOn(Get(ContentSettingsType::IRIS_WEBGL) ==
                           CONTENT_SETTING_ALLOW);
    signin_toggle_->SetIsOn(Get(ContentSettingsType::IRIS_GOOGLE_SIGNIN) ==
                            CONTENT_SETTING_ALLOW);
    forget_toggle_->SetIsOn(Get(ContentSettingsType::COOKIES) ==
                            CONTENT_SETTING_SESSION_ONLY);
    const std::string fingerprint =
        iris::GetFingerprintReadsPreset(browser_->GetProfile(), url_);
    fingerprint_box_->SetSelectedIndex(fingerprint == "real"    ? 1
                                       : fingerprint == "blank" ? 2
                                                                : 0);
    const std::string identity =
        iris::GetUserAgentPreset(browser_->GetProfile(), url_);
    size_t identity_index = 0;
    for (size_t i = 0; i < kIdentities.size(); ++i) {
      if (identity == kIdentities[i].id) {
        identity_index = i;
      }
    }
    identity_box_->SetSelectedIndex(identity_index);
  }

  void Changed(bool reload = true) {
    SyncControls();
    if (reload) {
      ReloadTab(web_contents_.get());
    }
  }

  // --- actions -------------------------------------------------------------

  void OnMaster() {
    if (master_->GetIsOn()) {
      Set(ContentSettingsType::ADS, CONTENT_SETTING_DEFAULT);
      Cookies()->ResetThirdPartyCookieSetting(url_);
      iris::SetFingerprintReadsPreset(browser_->GetProfile(), url_,
                                      "protected");
    } else {
      Set(ContentSettingsType::ADS, CONTENT_SETTING_ALLOW);
      Cookies()->SetThirdPartyCookieSetting(url_, CONTENT_SETTING_ALLOW);
      iris::SetFingerprintReadsPreset(browser_->GetProfile(), url_, "real");
    }
    Changed();
  }

  void OnAds() {
    Set(ContentSettingsType::ADS, ads_toggle_->GetIsOn()
                                      ? CONTENT_SETTING_DEFAULT
                                      : CONTENT_SETTING_ALLOW);
    Changed();
  }

  void OnCookies() {
    if (cookie_toggle_->GetIsOn()) {
      Cookies()->ResetThirdPartyCookieSetting(url_);
    } else {
      Cookies()->SetThirdPartyCookieSetting(url_, CONTENT_SETTING_ALLOW);
    }
    Changed();
  }

  void OnJavaScript() {
    Set(ContentSettingsType::JAVASCRIPT, js_toggle_->GetIsOn()
                                             ? CONTENT_SETTING_ALLOW
                                             : CONTENT_SETTING_BLOCK);
    Changed();
  }

  void OnJit() {
    Set(ContentSettingsType::JAVASCRIPT_JIT, jit_toggle_->GetIsOn()
                                                 ? CONTENT_SETTING_ALLOW
                                                 : CONTENT_SETTING_BLOCK);
    Changed();
  }

  void OnWebGL() {
    Set(ContentSettingsType::IRIS_WEBGL, webgl_toggle_->GetIsOn()
                                             ? CONTENT_SETTING_ALLOW
                                             : CONTENT_SETTING_DEFAULT);
    Changed();
  }

  void OnSignIn() {
    Set(ContentSettingsType::IRIS_GOOGLE_SIGNIN, signin_toggle_->GetIsOn()
                                                     ? CONTENT_SETTING_ALLOW
                                                     : CONTENT_SETTING_DEFAULT);
    Changed();
  }

  void OnForget() {
    Set(ContentSettingsType::COOKIES, forget_toggle_->GetIsOn()
                                          ? CONTENT_SETTING_SESSION_ONLY
                                          : CONTENT_SETTING_DEFAULT);
    Changed(/*reload=*/false);
  }

  void OnFingerprint() {
    const std::optional<size_t> index = fingerprint_box_->GetSelectedIndex();
    iris::SetFingerprintReadsPreset(
        browser_->GetProfile(), url_,
        index == 1u ? "real" : index == 2u ? "blank" : "protected");
    Changed();
  }

  void OnIdentity() {
    const std::optional<size_t> index = identity_box_->GetSelectedIndex();
    if (!index || *index >= kIdentities.size()) {
      return;
    }
    iris::SetUserAgentPreset(browser_->GetProfile(), url_,
                             kIdentities[*index].id);
    Changed();
  }

  void OnReset() {
    Set(ContentSettingsType::ADS, CONTENT_SETTING_DEFAULT);
    Set(ContentSettingsType::JAVASCRIPT, CONTENT_SETTING_DEFAULT);
    Set(ContentSettingsType::JAVASCRIPT_JIT, CONTENT_SETTING_DEFAULT);
    Set(ContentSettingsType::IRIS_WEBGL, CONTENT_SETTING_DEFAULT);
    Set(ContentSettingsType::IRIS_GOOGLE_SIGNIN, CONTENT_SETTING_DEFAULT);
    Set(ContentSettingsType::COOKIES, CONTENT_SETTING_DEFAULT);
    Cookies()->ResetThirdPartyCookieSetting(url_);
    iris::SetFingerprintReadsPreset(browser_->GetProfile(), url_, "protected");
    iris::SetUserAgentPreset(browser_->GetProfile(), url_, "");
    Changed();
  }

  void OpenSettings() {
    chrome::ShowSettingsSubPage(browser_, "irisHardening");
    GetWidget()->Close();
  }

  struct Identity {
    const char* id;
    const char16_t* name;
  };
  static constexpr auto kIdentities = std::to_array<Identity>({
      {"", u"Iris default"},
      {"firefox_linux", u"Firefox, Linux"},
      {"firefox_windows", u"Firefox, Windows"},
      {"firefox_mac", u"Firefox, macOS"},
      {"firefox_android", u"Firefox, Android"},
      {"chrome_windows", u"Chrome, Windows"},
      {"chrome_mac", u"Chrome, macOS"},
      {"chrome_linux", u"Chrome, Linux"},
      {"chrome_android", u"Chrome, Android"},
      {"chrome_ios", u"Chrome, iPhone"},
      {"edge_windows", u"Edge, Windows"},
      {"safari_mac", u"Safari, macOS"},
      {"safari_ios", u"Safari, iPhone"},
      {"samsung_android", u"Samsung Internet"},
  });

  raw_ptr<BrowserWindowInterface> browser_;
  base::WeakPtr<content::WebContents> web_contents_;
  raw_ptr<iris::ShieldStats> stats_;
  GURL url_;
  bool web_;
  raw_ptr<views::View> body_ = nullptr;
  raw_ptr<views::Label> status_ = nullptr;
  raw_ptr<views::ToggleButton> master_ = nullptr;
  raw_ptr<views::Label> total_ = nullptr;
  raw_ptr<views::Label> breakdown_ = nullptr;
  raw_ptr<views::Label> lifetime_ = nullptr;
  raw_ptr<views::ToggleButton> ads_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> cookie_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> js_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> jit_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> webgl_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> signin_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> forget_toggle_ = nullptr;
  raw_ptr<views::Combobox> fingerprint_box_ = nullptr;
  raw_ptr<views::Combobox> identity_box_ = nullptr;
  raw_ptr<views::Link> details_link_ = nullptr;
  raw_ptr<views::View> details_ = nullptr;
  base::OnceClosure on_closed_;
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
    javascript_->SetHighlight(u"off", std::nullopt);
    javascript_->SetTooltipText(
        u"JavaScript is off for this site. Click to turn it on.");
  }
}

void IrisToolbarButtons::OnShieldPressed() {
  content::WebContents* web_contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  if (!web_contents) {
    return;
  }
  // A second click on the shield closes the panel. Pressing the button also
  // deactivates (and so already closes) the panel before this click arrives,
  // so a panel that closed a moment ago counts as "still open".
  if (shield_bubble_.view()) {
    shield_bubble_.view()->GetWidget()->Close();
    return;
  }
  if (base::TimeTicks::Now() - shield_bubble_closed_at_ <
      base::Milliseconds(400)) {
    return;
  }
  shield_bubble_.SetView(IrisShieldBubble::Show(
      shield_, browser_, web_contents,
      base::BindOnce(&IrisToolbarButtons::OnShieldBubbleClosed,
                     weak_factory_.GetWeakPtr())));
}

void IrisToolbarButtons::OnShieldBubbleClosed() {
  shield_bubble_closed_at_ = base::TimeTicks::Now();
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
    new_identity_->SetHighlight(u"Sure?", std::nullopt);
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
