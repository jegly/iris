// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/views/toolbar/iris_toolbar_buttons.h"

#include <algorithm>
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
#include "build/build_config.h"
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
#include "ui/compositor/layer.h"
#include "ui/gfx/font_list.h"
#include "ui/views/background.h"
#include "ui/views/border.h"
#include "ui/views/controls/button/md_text_button.h"
#include "ui/views/controls/button/toggle_button.h"
#include "ui/views/controls/image_view.h"
#include "ui/views/controls/separator.h"
#include "components/vector_icons/vector_icons.h"
#include "ui/views/controls/button/image_button_factory.h"
#include "ui/views/view_class_properties.h"
#include "ui/views/layout/fill_layout.h"
#include "ui/views/controls/scroll_view.h"
#include "chrome/browser/iris/iris_app_lock.h"  // nogncheck
#include "chrome/browser/iris/iris_shield_settings.h"  // nogncheck
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "chrome/browser/ui/browser_window/public/browser_collection_observer.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "ui/base/base_window.h"
#if BUILDFLAG(IS_LINUX)
#include "chrome/browser/ui/views/iris/iris_unlock_dialog.h"  // nogncheck
#endif
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

#if BUILDFLAG(IS_LINUX)
// "Lock" with "Lock without closing Iris" on: every Iris window is hidden until
// the passphrase is entered again in the "Iris is locked" window. Windows that
// open meanwhile (for example by starting Iris again) are hidden too. The data
// key stays in memory while Iris runs; "Lock and close" is the stronger lock.
class IrisScreenLock : public BrowserCollectionObserver {
 public:
  static void Lock() {
    static base::NoDestructor<IrisScreenLock> instance;
    instance->Start();
  }

  // BrowserCollectionObserver:
  void OnBrowserCreated(BrowserWindowInterface* browser) override {
    Hide(browser);
  }
  void OnBrowserActivated(BrowserWindowInterface* browser) override {
    Hide(browser);
  }

 private:
  static void Hide(BrowserWindowInterface* browser) {
    if (browser && browser->GetWindow()) {
      browser->GetWindow()->Hide();
    }
  }

  void Start() {
    PrefService* local_state = g_browser_process->local_state();
    if (locked_ || !local_state) {
      return;
    }
    locked_ = true;
    GlobalBrowserCollection* browsers = GlobalBrowserCollection::GetInstance();
    browsers->ForEach([](BrowserWindowInterface* browser) {
      Hide(browser);
      return true;
    });
    observation_.Observe(browsers);
    IrisUnlockDialog::ShowWhileRunning(
        base::BindRepeating([](const std::u16string& passphrase) {
          return iris_app_lock::Unlock(g_browser_process->local_state(),
                                       passphrase);
        }),
        local_state->GetInteger(iris_app_lock::kLockPalettePref),
        local_state->GetInteger(iris_app_lock::kLockColorSchemePref),
        base::BindOnce(&IrisScreenLock::Done, base::Unretained(this)));
  }

  void Done(bool unlocked) {
    observation_.Reset();
    locked_ = false;
    if (!unlocked) {
      chrome::AttemptUserExit();
      return;
    }
    GlobalBrowserCollection::GetInstance()->ForEach(
        [](BrowserWindowInterface* browser) {
          if (browser->GetWindow()) {
            browser->GetWindow()->Show();
          }
          return true;
        });
  }

  bool locked_ = false;
  base::ScopedObservation<GlobalBrowserCollection, BrowserCollectionObserver>
      observation_{this};
};
#endif  // BUILDFLAG(IS_LINUX)

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
    set_fixed_width(kWidth);
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
  static constexpr int kWidth = 360;
  static constexpr int kMaxHeight = 600;
  // Room for text inside the margins and a possible scroll bar.
  static constexpr int kTextWidth = kWidth - 28 - 16;

  static void Bold(views::Label* label, int size_delta) {
    label->SetFontList(label->font_list().Derive(
        size_delta, gfx::Font::NORMAL, gfx::Font::Weight::BOLD));
  }

  static views::Label* AddSecondary(views::View* parent,
                                    const std::u16string& text) {
    auto* label = parent->AddChildView(std::make_unique<views::Label>(
        text, views::style::CONTEXT_LABEL, views::style::STYLE_SECONDARY));
    label->SetHorizontalAlignment(gfx::ALIGN_LEFT);
    label->SetMultiLine(true);
    label->SetMaximumWidth(kTextWidth);
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
    label->SetMultiLine(true);
    label->SetMaximumWidth(kTextWidth - 52);
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
    label->SetMultiLine(true);
    label->SetMaximumWidth(kTextWidth / 2);
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
    host->SetMultiLine(true);
    host->SetMaximumWidth(kTextWidth - 90);
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
    breakdown_->SetMultiLine(true);
    breakdown_->SetMaximumWidth(kTextWidth - 80);
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
    recolor_toggle_ = AddToggleRow(
        u"Recolour this site (Theme editor)",
        base::BindRepeating(&IrisShieldBubble::OnRecolor,
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

  void BuildConnection(content::WebContents* web_contents) {
    AddSection(u"Connection");
    const std::vector<std::u16string> lines = base::SplitString(
        iris::GetTlsDetailsText(web_contents), u"\n", base::TRIM_WHITESPACE,
        base::SPLIT_WANT_NONEMPTY);
    if (lines.empty()) {
      AddSecondary(body_, web_ ? u"Not encrypted" : u"No connection details");
      return;
    }
    // Every line, always visible, wrapped (no "Details" button).
    for (const std::u16string& line : lines) {
      AddSecondary(body_, line);
    }
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
    auto* spacer = footer->AddChildView(std::make_unique<views::View>());
    layout->SetFlexForView(spacer, 1);
    auto* gear = footer->AddChildView(
        views::CreateVectorImageButtonWithNativeTheme(
            base::BindRepeating(&IrisShieldBubble::OpenSettings,
                                base::Unretained(this)),
            vector_icons::kSettingsIcon, 20));
    gear->SetTooltipText(u"Iris hardening settings");
    gear->GetViewAccessibility().SetName(u"Iris hardening settings");
  }

  // --- state ---------------------------------------------------------------

  bool IsOn(iris::shield::Switch which) {
    return iris::shield::IsOn(browser_->GetProfile(), url_, which);
  }

  void SetSwitch(iris::shield::Switch which,
                 views::ToggleButton* toggle,
                 bool reload = true) {
    iris::shield::Set(browser_->GetProfile(), url_, which, toggle->GetIsOn());
    Changed(reload);
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
    using iris::shield::Switch;
    const bool ads_on = IsOn(Switch::kAds);
    master_->SetIsOn(ads_on);
    status_->SetText(ads_on ? u"Shield is on" : u"Shield is off for this site");
    ads_toggle_->SetIsOn(ads_on);
    cookie_toggle_->SetIsOn(IsOn(Switch::kCookies));
    js_toggle_->SetIsOn(IsOn(Switch::kJavaScript));
    jit_toggle_->SetIsOn(IsOn(Switch::kJit));
    // "Turn WebGL off completely" (Iris hardening) wins over the site switch.
    webgl_toggle_->SetIsOn(IsOn(Switch::kWebGL));
    webgl_toggle_->SetEnabled(
        !iris::shield::IsLocked(browser_->GetProfile(), Switch::kWebGL));
    signin_toggle_->SetIsOn(IsOn(Switch::kSignIn));
    forget_toggle_->SetIsOn(IsOn(Switch::kForget));
    recolor_toggle_->SetIsOn(IsOn(Switch::kRecolor));
    recolor_toggle_->SetEnabled(
        !iris::shield::IsLocked(browser_->GetProfile(), Switch::kRecolor));
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
    iris::shield::SetShield(browser_->GetProfile(), url_, master_->GetIsOn());
    Changed();
  }

  void OnAds() {
    SetSwitch(iris::shield::Switch::kAds, ads_toggle_);
  }

  void OnCookies() {
    SetSwitch(iris::shield::Switch::kCookies, cookie_toggle_);
  }

  void OnJavaScript() {
    SetSwitch(iris::shield::Switch::kJavaScript, js_toggle_);
  }

  void OnJit() {
    SetSwitch(iris::shield::Switch::kJit, jit_toggle_);
  }

  void OnWebGL() {
    SetSwitch(iris::shield::Switch::kWebGL, webgl_toggle_);
  }

  void OnSignIn() {
    SetSwitch(iris::shield::Switch::kSignIn, signin_toggle_);
  }

  void OnRecolor() {
    SetSwitch(iris::shield::Switch::kRecolor, recolor_toggle_);
  }

  void OnForget() {
    SetSwitch(iris::shield::Switch::kForget, forget_toggle_, /*reload=*/false);
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
    iris::shield::Reset(browser_->GetProfile(), url_);
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
  raw_ptr<views::ToggleButton> recolor_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> webgl_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> signin_toggle_ = nullptr;
  raw_ptr<views::ToggleButton> forget_toggle_ = nullptr;
  raw_ptr<views::Combobox> fingerprint_box_ = nullptr;
  raw_ptr<views::Combobox> identity_box_ = nullptr;
  base::OnceClosure on_closed_;
};

BEGIN_METADATA(IrisShieldBubble)
END_METADATA

// The shield button: the page's blocked count is a small badge on the icon's
// corner, so the button keeps the size of the other toolbar buttons (jegly
// 2026-10-10: the highlight pill around the shield was too large).
class IrisShieldButton : public ToolbarButton {
  METADATA_HEADER(IrisShieldButton, ToolbarButton)

 public:
  explicit IrisShieldButton(PressedCallback callback)
      : ToolbarButton(std::move(callback)) {
    badge_ = AddChildView(std::make_unique<views::Label>());
    // A fixed small size: deriving from the system font made the badge cover
    // the whole button with large desktop fonts (jegly 2026-10-11).
    badge_->SetFontList(
        views::Label::GetDefaultFontList()
            .DeriveWithWeight(gfx::Font::Weight::BOLD)
            .DeriveWithHeightUpperBound(kBadgeHeight - 2));
    badge_->SetEnabledColor(ui::kColorSysOnPrimary);
    badge_->SetBackground(views::CreateRoundedRectBackground(
        ui::kColorSysPrimary, kBadgeHeight / 2));
    badge_->SetBorder(views::CreateEmptyBorder(gfx::Insets::VH(0, 2)));
    badge_->SetCanProcessEventsWithinSubtree(false);
    // Its own layer, so it is drawn above the icon (which may have one).
    badge_->SetPaintToLayer();
    badge_->layer()->SetFillsBoundsOpaquely(false);
    badge_->SetVisible(false);
  }

  // "" hides the badge.
  void SetCount(const std::u16string& text) {
    badge_->SetText(text);
    badge_->SetVisible(!text.empty());
    PositionBadge();
  }

  // views::View:
  void OnBoundsChanged(const gfx::Rect& previous_bounds) override {
    ToolbarButton::OnBoundsChanged(previous_bounds);
    PositionBadge();
  }

 private:
  void PositionBadge() {
    if (!badge_->GetVisible()) {
      return;
    }
    // A small dot on the button's top-right corner, clear of most of the icon.
    gfx::Size size = badge_->GetPreferredSize();
    size.set_height(kBadgeHeight);
    size.set_width(std::max(size.width(), kBadgeHeight));
    // In the corner, so it only touches the tip of the icon's shoulder.
    badge_->SetBounds(width() - size.width(), 0, size.width(), size.height());
  }

  // Badge height in DIPs (a 20 DIP icon in a 28-34 DIP button).
  static constexpr int kBadgeHeight = 12;

  raw_ptr<views::Label> badge_ = nullptr;
};

BEGIN_METADATA(IrisShieldButton)
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
  {
    auto shield = std::make_unique<IrisShieldButton>(base::BindRepeating(
        &IrisToolbarButtons::OnShieldPressed, base::Unretained(this)));
    shield->SetVectorIcon(kIrisShieldIcon);
    shield->SetTooltipText(u"Iris shield");
    shield->GetViewAccessibility().SetName(u"Iris shield");
    shield_ = AddChildView(std::move(shield));
  }
  javascript_ = make_button(&IrisToolbarButtons::OnJavaScriptPressed,
                            kIrisJavascriptIcon, u"JavaScript on this site");
  new_identity_ = make_button(&IrisToolbarButtons::OnNewIdentityPressed,
                              kIrisFlameIcon, u"New identity");
  lock_ = make_button(&IrisToolbarButtons::OnLockPressed, kIrisLockIcon,
                      u"Lock and close Iris");

  browser_->GetTabStripModel()->AddObserver(this);
  pref_registrar_.Init(browser_->GetProfile()->GetPrefs());
  for (const char* pref :
       {kShieldPref, kJavaScriptPref, kNewIdentityPref, kLockPref,
        kLockKeepOpenPref}) {
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
  const std::u16string lock_name = prefs->GetBoolean(kLockKeepOpenPref)
                                       ? u"Lock Iris"
                                       : u"Lock and close Iris";
  lock_->SetTooltipText(lock_name);
  lock_->GetViewAccessibility().SetName(lock_name);
  lock_->SetVisible(prefs->GetBoolean(kLockPref) &&
                    g_browser_process->local_state() &&
                    iris_app_lock::IsEnabled(g_browser_process->local_state()));
}

void IrisToolbarButtons::UpdateShield() {
  static_cast<IrisShieldButton*>(shield_.get())
      ->SetCount(stats_ ? CountText(stats_->total()) : std::u16string());
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
  const bool allowed = iris::shield::IsOn(
      browser_->GetProfile(), url, iris::shield::Switch::kJavaScript);
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
  Profile* profile = browser_->GetProfile();
  iris::shield::Set(profile, url, iris::shield::Switch::kJavaScript,
                    !iris::shield::IsOn(profile, url,
                                        iris::shield::Switch::kJavaScript));
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
#if BUILDFLAG(IS_LINUX)
  if (browser_->GetProfile()->GetPrefs()->GetBoolean(kLockKeepOpenPref)) {
    IrisScreenLock::Lock();
    return;
  }
#endif
  chrome::AttemptUserExit();
}

BEGIN_METADATA(IrisToolbarButtons)
END_METADATA
