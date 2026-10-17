#!/usr/bin/env bash
# Iris — "Show button names": optional tiny names under the desktop toolbar icons (jegly 2026-10-16: "turn on text so
# its optional sits under the icons so it says what it says"; "very small text, like tiny"; verified against
# 156.0.8078.11 sources fetched from gitiles — no local checkout on the machine that wrote this).
# Switch: Customize toolbar side panel -> Iris -> "Show button names" (profile pref iris.ui.toolbar_labels, default
#   OFF, registered in iris_shredder.cc). It is one more row in the panel's kIrisButtons table
#   (apply-customize-toolbar.sh), so pinning, live updates and "Reset to default" already handle it.
# How (ToolbarButton, the base class of every toolbar icon: back/forward/reload/home, pinned actions, extensions,
#   downloads, app menu, Iris's own buttons):
#   - a views::Label child, 9 px, toolbar icon colour, centred, elided at 64 DIP, ignored by layout/a11y/events.
#   - room for it comes from extra insets (iris_caption_insets_: bottom = caption height, sides only when the name is
#     wider than the button), added in GetTargetInsets(). LabelButton lays the icon out in the remaining area, so the
#     icon stays exactly where it is now; the button just grows downward.
#   - the toolbar grows with it: ToolbarView caps its height at the back button's preferred height (which now
#     includes the caption) — no ToolbarView change needed.
#   - hover / pressed highlight, focus ring and the highlight background exclude the caption area
#     (GetToolbarInkDropInsets + UpdateColorsAndInsets paint insets), so they stay on the icon.
#   - text = the button's accessible name, kept up to date via OnAccessibleNameChanged (Reload <-> Stop);
#     app menu = "Menu"; Iris buttons set short names with SetIrisCaption() (iris_toolbar_buttons.cc in patches/src).
#   - only buttons inside ToolbarView get a caption (found in AddedToWidget; each watches the pref itself).
# Known limits: a button whose own label text changes later (avatar name, "Update" chip) keeps the caption width
#   computed when it was last laid out; dropdown arrows / touch mode untested.
# Needs (anchors): apply-shredder (iris_shredder.cc), apply-toolbar-buttons, apply-customize-toolbar. Run after them.
# STATUS 2026-10-16: copy-tested on upstream 156.0.8078.11 files (+ the anchors the earlier Iris patches create), NOT
#   compile-proven. Prove: toolbar_button.o, toolbar_ink_drop_util.o, iris_toolbar_buttons.o,
#   customize_toolbar_handler.o (+ mojom), iris_shredder.o; then look at it in a dev build (light/dark, hover).
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
PREF = "iris.ui.toolbar_labels"
T = "chrome/browser/ui/views/toolbar/"

# 1. pref
edit("chrome/browser/iris/iris_shredder.cc",
     '  registry->RegisterBooleanPref("iris.ui.toolbar_lock", true);\n',
     '  registry->RegisterBooleanPref("iris.ui.toolbar_lock", true);\n'
     '  registry->RegisterBooleanPref("%s", false);  // apply-toolbar-labels.sh\n' % PREF,
     '"%s", false);' % PREF, "pref")

# 2. ToolbarButton header
H = T + "toolbar_button.h"
edit(H, "class TabStripModel;\n", "class PrefChangeRegistrar;  // Iris\nclass TabStripModel;\n",
     "class PrefChangeRegistrar;  // Iris", "forward decl")
edit(H, "namespace views {\nclass MenuModelAdapter;\n", "namespace views {\nclass Label;  // Iris\nclass MenuModelAdapter;\n",
     "class Label;  // Iris", "forward decl Label")
edit(H, "  void SetLayoutInsetDelta(const gfx::Insets& insets);\n",
     "  void SetLayoutInsetDelta(const gfx::Insets& insets);\n\n"
     "  // Iris: tiny name under the icon when \"Show button names\" is on\n"
     "  // (apply-toolbar-labels.sh). Empty = the accessible name.\n"
     "  void SetIrisCaption(const std::u16string& caption);\n"
     "  const gfx::Insets& iris_caption_insets() const {\n"
     "    return iris_caption_insets_;\n"
     "  }\n",
     "void SetIrisCaption(", "public API")
edit(H, "  std::u16string GetAlternativeAccessibleName() const override;\n",
     "  std::u16string GetAlternativeAccessibleName() const override;\n"
     "  void AddedToWidget() override;  // Iris (apply-toolbar-labels.sh)\n"
     "  void OnAccessibleNameChanged(const std::u16string& new_name) override;  // Iris\n",
     "void OnAccessibleNameChanged(const std::u16string& new_name) override;  // Iris", "overrides")
edit(H, "  // A factory for tasks that show the dropdown context menu for the button.\n"
        "  base::WeakPtrFactory<ToolbarButton> show_menu_factory_{this};\n",
     "  // Iris: caption under the icon (apply-toolbar-labels.sh).\n"
     "  void OnIrisCaptionPrefChanged();\n"
     "  void SetIrisCaptionEnabled(bool enabled);\n"
     "  void UpdateIrisCaption(const std::u16string& accessible_name);\n"
     "  void LayoutIrisCaption();\n"
     "  raw_ptr<views::Label> iris_caption_ = nullptr;\n"
     "  std::u16string iris_caption_override_;\n"
     "  bool iris_caption_enabled_ = false;\n"
     "  gfx::Insets iris_caption_insets_;\n"
     "  std::unique_ptr<PrefChangeRegistrar> iris_caption_pref_;\n\n"
     "  // A factory for tasks that show the dropdown context menu for the button.\n"
     "  base::WeakPtrFactory<ToolbarButton> show_menu_factory_{this};\n",
     "raw_ptr<views::Label> iris_caption_", "members")

# 3. ToolbarButton implementation
C = T + "toolbar_button.cc"
edit(C, '#include "chrome/browser/ui/views/toolbar/toolbar_ink_drop_util.h"\n',
     '#include "chrome/browser/ui/views/toolbar/toolbar_ink_drop_util.h"\n'
     '#include "chrome/browser/profiles/profile.h"  // Iris\n'
     '#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"  // Iris\n'
     '#include "chrome/browser/ui/view_ids.h"  // Iris\n'
     '#include "chrome/browser/ui/views/toolbar/toolbar_view.h"  // Iris\n'
     '#include "components/prefs/pref_change_registrar.h"  // Iris\n'
     '#include "components/prefs/pref_service.h"  // Iris\n'
     '#include "ui/views/accessibility/view_accessibility.h"  // Iris\n'
     '#include "ui/views/controls/label.h"  // Iris\n'
     '#include "ui/views/view_class_properties.h"  // Iris\n'
     '#include "ui/views/view_utils.h"  // Iris\n',
     '#include "ui/views/view_utils.h"  // Iris', "includes")
edit(C, "  return layout_insets_.value_or(::GetLayoutInsets(TOOLBAR_BUTTON)) +\n"
        "         layout_inset_delta_ + *GetProperty(views::kInternalPaddingKey);\n",
     "  return layout_insets_.value_or(::GetLayoutInsets(TOOLBAR_BUTTON)) +\n"
     "         layout_inset_delta_ + *GetProperty(views::kInternalPaddingKey) +\n"
     "         iris_caption_insets_;  // Iris (apply-toolbar-labels.sh)\n",
     "iris_caption_insets_;  // Iris (apply-toolbar-labels.sh)", "target insets")
edit(C, "  const int extra_height =\n"
        "      std::max(0, target_size.height() -\n"
        "                      GetLayoutConstant(LayoutConstant::kLocationBarHeight));\n"
        "  const gfx::Insets paint_insets =\n"
        "      gfx::Insets(extra_height / 2) + *GetProperty(views::kInternalPaddingKey);\n",
     "  // Iris: the caption area (apply-toolbar-labels.sh) is not highlighted.\n"
     "  const int extra_height =\n"
     "      std::max(0, target_size.height() - iris_caption_insets_.height() -\n"
     "                      GetLayoutConstant(LayoutConstant::kLocationBarHeight));\n"
     "  const gfx::Insets paint_insets =\n"
     "      gfx::Insets(extra_height / 2) + *GetProperty(views::kInternalPaddingKey) +\n"
     "      iris_caption_insets_;\n",
     "target_size.height() - iris_caption_insets_.height()", "paint insets")
edit(C, "  if (size() != previous_bounds.size()) {\n"
        "    UpdateColorsAndInsets();\n"
        "  }\n"
        "  LabelButton::OnBoundsChanged(previous_bounds);\n"
        "}\n",
     "  if (size() != previous_bounds.size()) {\n"
     "    UpdateColorsAndInsets();\n"
     "  }\n"
     "  LabelButton::OnBoundsChanged(previous_bounds);\n"
     "  LayoutIrisCaption();  // Iris (apply-toolbar-labels.sh)\n"
     "}\n",
     "  LayoutIrisCaption();  // Iris (apply-toolbar-labels.sh)\n", "caption bounds")
IMPL = r'''// Iris: "Show button names" (apply-toolbar-labels.sh).
namespace {
constexpr char kIrisToolbarLabelsPref[] = "iris.ui.toolbar_labels";
constexpr int kIrisCaptionFontSize = 9;
constexpr int kIrisCaptionMaxWidth = 64;
constexpr int kIrisCaptionSidePadding = 2;
}  // namespace

void ToolbarButton::SetIrisCaption(const std::u16string& caption) {
  iris_caption_override_ = caption;
  UpdateIrisCaption(GetViewAccessibility().GetCachedName());
}

void ToolbarButton::AddedToWidget() {
  LabelButton::AddedToWidget();
  // Only the main toolbar's buttons get a caption.
  const ToolbarView* toolbar = nullptr;
  for (const views::View* view = parent(); view && !toolbar;
       view = view->parent()) {
    toolbar = views::AsViewClass<ToolbarView>(view);
  }
  if (!toolbar || !toolbar->browser() || !toolbar->browser()->GetProfile()) {
    return;
  }
  PrefService* prefs = toolbar->browser()->GetProfile()->GetPrefs();
  if (!prefs->FindPreference(kIrisToolbarLabelsPref)) {
    return;
  }
  iris_caption_pref_ = std::make_unique<PrefChangeRegistrar>();
  iris_caption_pref_->Init(prefs);
  iris_caption_pref_->Add(
      kIrisToolbarLabelsPref,
      base::BindRepeating(&ToolbarButton::OnIrisCaptionPrefChanged,
                          base::Unretained(this)));
  OnIrisCaptionPrefChanged();
}

void ToolbarButton::OnAccessibleNameChanged(const std::u16string& new_name) {
  LabelButton::OnAccessibleNameChanged(new_name);
  if (iris_caption_enabled_ && iris_caption_override_.empty()) {
    UpdateIrisCaption(new_name);
  }
}

void ToolbarButton::OnIrisCaptionPrefChanged() {
  SetIrisCaptionEnabled(
      iris_caption_pref_->prefs()->GetBoolean(kIrisToolbarLabelsPref));
}

void ToolbarButton::SetIrisCaptionEnabled(bool enabled) {
  if (enabled == iris_caption_enabled_) {
    return;
  }
  iris_caption_enabled_ = enabled;
  if (enabled && !iris_caption_) {
    auto caption = std::make_unique<views::Label>();
    const gfx::FontList base_font;
    caption->SetFontList(base_font.DeriveWithSizeDelta(
        kIrisCaptionFontSize - base_font.GetFontSize()));
    caption->SetEnabledColor(kColorToolbarButtonIcon);
    caption->SetAutoColorReadabilityEnabled(false);
    caption->SetSubpixelRenderingEnabled(false);
    caption->SetHorizontalAlignment(gfx::ALIGN_CENTER);
    caption->SetElideBehavior(gfx::ELIDE_TAIL);
    caption->SetHandlesTooltips(false);
    caption->SetCanProcessEventsWithinSubtree(false);
    caption->GetViewAccessibility().SetIsIgnored(true);
    caption->SetProperty(views::kViewIgnoredByLayoutKey, true);
    iris_caption_ = AddChildView(std::move(caption));
  }
  if (iris_caption_) {
    iris_caption_->SetVisible(enabled);
  }
  UpdateIrisCaption(GetViewAccessibility().GetCachedName());
}

void ToolbarButton::UpdateIrisCaption(const std::u16string& accessible_name) {
  gfx::Insets insets;
  if (iris_caption_enabled_ && iris_caption_) {
    std::u16string text = iris_caption_override_;
    if (text.empty()) {
      text = GetID() == VIEW_ID_APP_MENU ? std::u16string(u"Menu")
                                         : accessible_name;
    }
    iris_caption_->SetText(text);
    const gfx::Size caption_size = iris_caption_->GetPreferredSize();
    const int caption_width =
        std::min(caption_size.width(), kIrisCaptionMaxWidth);
    // The button's width without the caption.
    const gfx::Insets base_insets = GetTargetInsets() - iris_caption_insets_;
    const int button_width = CalculatePreferredSize({}).width() -
                             GetInsets().width() + base_insets.width();
    const int extra = std::max(
        0, caption_width + 2 * kIrisCaptionSidePadding - button_width);
    insets = gfx::Insets::TLBR(0, extra / 2, caption_size.height(),
                               extra - extra / 2);
  }
  if (insets != iris_caption_insets_) {
    iris_caption_insets_ = insets;
    UpdateColorsAndInsets();
    PreferredSizeChanged();
  }
  LayoutIrisCaption();
}

void ToolbarButton::LayoutIrisCaption() {
  if (!iris_caption_ || !iris_caption_enabled_) {
    return;
  }
  // Just under the icon (the contents area excludes every inset).
  const gfx::Insets& padding = *GetProperty(views::kInternalPaddingKey);
  iris_caption_->SetBounds(padding.left(), GetContentsBounds().bottom() + 1,
                           std::max(0, width() - padding.width()),
                           iris_caption_insets_.bottom());
}

'''
edit(C, "void ToolbarButton::ClearPendingMenu() {\n", IMPL + "void ToolbarButton::ClearPendingMenu() {\n",
     'constexpr char kIrisToolbarLabelsPref[] = "iris.ui.toolbar_labels";', "caption implementation")

# 4. hover/pressed highlight + focus ring stay on the icon
I = T + "toolbar_ink_drop_util.cc"
edit(I, '#include "chrome/browser/ui/views/chrome_layout_provider.h"\n',
     '#include "chrome/browser/ui/views/chrome_layout_provider.h"\n'
     '#include "chrome/browser/ui/views/toolbar/toolbar_button.h"  // Iris\n',
     'toolbar/toolbar_button.h"  // Iris', "include")
s = open(I).read()
if '#include "ui/views/view_utils.h"' not in s:
    edit(I, '#include "ui/views/view_class_properties.h"\n',
         '#include "ui/views/view_class_properties.h"\n#include "ui/views/view_utils.h"  // Iris\n',
         '#include "ui/views/view_utils.h"  // Iris', "include view_utils")
edit(I, "  const gfx::Size host_size = host_view->size();\n"
        "  const int inkdrop_dimensions =\n"
        "      GetLayoutConstant(LayoutConstant::kLocationBarHeight);\n"
        "  gfx::Insets inkdrop_insets =\n"
        "      margin_insets +\n"
        "      gfx::Insets(std::max(0, (host_size.height() - inkdrop_dimensions) / 2));\n",
     "  // Iris: leave out a caption under the icon (apply-toolbar-labels.sh).\n"
     "  gfx::Insets caption_insets;\n"
     "  if (const auto* button = views::AsViewClass<ToolbarButton>(host_view)) {\n"
     "    caption_insets = button->iris_caption_insets();\n"
     "  }\n"
     "  gfx::Size host_size = host_view->size();\n"
     "  host_size.Enlarge(-caption_insets.width(), -caption_insets.height());\n"
     "  const int inkdrop_dimensions =\n"
     "      GetLayoutConstant(LayoutConstant::kLocationBarHeight);\n"
     "  gfx::Insets inkdrop_insets =\n"
     "      margin_insets + caption_insets +\n"
     "      gfx::Insets(std::max(0, (host_size.height() - inkdrop_dimensions) / 2));\n",
     "caption_insets = button->iris_caption_insets();", "ink drop insets")

# 5. Customize toolbar panel switch
D = "chrome/browser/ui/webui/side_panel/customize_chrome/customize_toolbar/"
edit(D + "customize_toolbar.mojom", "  kIrisLock,\n};\n",
     "  kIrisLock,\n  kIrisToolbarLabels,  // \"Show button names\" (apply-toolbar-labels.sh)\n};\n",
     "kIrisToolbarLabels,", "mojom")
edit(D + "customize_toolbar_handler.cc",
     "     \"Lock Iris (while the app lock is on)\", \"iris.ui.toolbar_lock\",\n"
     "     &kIrisLockIcon},\n"
     "});\n",
     "     \"Lock Iris (while the app lock is on)\", \"iris.ui.toolbar_lock\",\n"
     "     &kIrisLockIcon},\n"
     "    // Not a button: tiny names under the icons (apply-toolbar-labels.sh).\n"
     "    {side_panel::customize_chrome::mojom::ActionId::kIrisToolbarLabels,\n"
     "     \"Show button names\", \"%s\", &vector_icons::kSubtitlesIcon},\n"
     "});\n" % PREF,
     "ActionId::kIrisToolbarLabels,", "panel switch")
PY
echo "=== Toolbar button names complete ==="
