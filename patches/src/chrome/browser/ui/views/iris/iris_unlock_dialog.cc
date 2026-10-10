// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/views/iris/iris_unlock_dialog.h"

#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/run_loop.h"
#include "chrome/grit/generated_resources.h"
#include "third_party/boringssl/src/include/openssl/mem.h"
#include "ui/base/ime/text_input_type.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/color/color_id.h"
#include "ui/color/color_provider_key.h"
#include "ui/color/iris_palettes.h"
#include "ui/gfx/geometry/insets.h"
#include "ui/views/accessibility/view_accessibility.h"
#include "ui/views/controls/label.h"
#include "ui/views/controls/textfield/textfield.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/widget/widget.h"

namespace {
constexpr int kInsets = 16;
constexpr int kSpacing = 8;
constexpr int kWidth = 380;
}  // namespace

// static
bool IrisUnlockDialog::Run(TryUnlock try_unlock, int palette, int color_scheme) {
  base::RunLoop run_loop;
  bool unlocked = false;
  auto done = base::BindOnce(
      [](bool* unlocked_ptr, base::RepeatingClosure quit, bool success) {
        *unlocked_ptr = success;
        quit.Run();
      },
      &unlocked, run_loop.QuitClosure());

  views::Widget* widget = views::DialogDelegate::CreateDialogWidget(
      new IrisUnlockDialog(std::move(try_unlock), std::move(done)), nullptr,
      nullptr);
  // Same look as the browser (no profile is loaded yet, so the window cannot
  // ask ThemeService; the values come from Local State, see the header).
  if (color_scheme == 1) {
    widget->SetColorModeOverride(ui::ColorProviderKey::ColorMode::kLight);
  } else if (color_scheme == 2) {
    widget->SetColorModeOverride(ui::ColorProviderKey::ColorMode::kDark);
  }  // 0: follow the system, as the browser does
  if (palette >= 0 && static_cast<size_t>(palette) < ui::iris::kPaletteCount) {
    widget->SetUserColorOverride(
        ui::iris::IrisPaletteSeed(static_cast<size_t>(palette)));
  }
  widget->Show();
  base::WeakPtr<views::Widget> weak_widget = widget->GetWeakPtr();

  run_loop.Run();

  if (weak_widget) {
    weak_widget->CloseNow();
  }
  return unlocked;
}

// static
void IrisUnlockDialog::ShowWhileRunning(TryUnlock try_unlock,
                                        int palette,
                                        int color_scheme,
                                        base::OnceCallback<void(bool)> done) {
  views::Widget* widget = views::DialogDelegate::CreateDialogWidget(
      new IrisUnlockDialog(std::move(try_unlock), std::move(done)), nullptr,
      nullptr);
  if (color_scheme == 1) {
    widget->SetColorModeOverride(ui::ColorProviderKey::ColorMode::kLight);
  } else if (color_scheme == 2) {
    widget->SetColorModeOverride(ui::ColorProviderKey::ColorMode::kDark);
  }
  if (palette >= 0 && static_cast<size_t>(palette) < ui::iris::kPaletteCount) {
    widget->SetUserColorOverride(
        ui::iris::IrisPaletteSeed(static_cast<size_t>(palette)));
  }
  widget->Show();
}

IrisUnlockDialog::IrisUnlockDialog(TryUnlock try_unlock,
                                   base::OnceCallback<void(bool)> done)
    : try_unlock_(std::move(try_unlock)), done_(std::move(done)) {
  SetTitle(l10n_util::GetStringUTF16(IDS_IRIS_UNLOCK_TITLE));
  SetButtons(static_cast<int>(ui::mojom::DialogButton::kOk) |
             static_cast<int>(ui::mojom::DialogButton::kCancel));
  SetButtonLabel(ui::mojom::DialogButton::kOk,
                 l10n_util::GetStringUTF16(IDS_IRIS_UNLOCK_BUTTON));
  SetButtonLabel(ui::mojom::DialogButton::kCancel,
                 l10n_util::GetStringUTF16(IDS_IRIS_UNLOCK_QUIT));
  set_fixed_width(kWidth);

  auto content = std::make_unique<views::View>();
  content->SetLayoutManager(std::make_unique<views::BoxLayout>(
      views::BoxLayout::Orientation::kVertical, gfx::Insets(kInsets),
      kSpacing));

  const std::u16string prompt =
      l10n_util::GetStringUTF16(IDS_IRIS_UNLOCK_PROMPT);
  auto* label = content->AddChildView(std::make_unique<views::Label>(prompt));
  label->SetHorizontalAlignment(gfx::ALIGN_LEFT);

  field_ = content->AddChildView(std::make_unique<views::Textfield>());
  field_->SetTextInputType(ui::TEXT_INPUT_TYPE_PASSWORD);
  field_->GetViewAccessibility().SetName(prompt);

  // Kept in the layout (empty) so showing the error does not resize the window.
  error_ = content->AddChildView(std::make_unique<views::Label>(u" "));
  error_->SetHorizontalAlignment(gfx::ALIGN_LEFT);
  error_->SetEnabledColor(ui::kColorAlertHighSeverity);

  SetInitiallyFocusedView(field_);
  SetContentsView(std::move(content));
}

IrisUnlockDialog::~IrisUnlockDialog() = default;

bool IrisUnlockDialog::Accept() {
  std::u16string passphrase(field_->GetText());
  const bool unlocked = try_unlock_.Run(passphrase);
  // Wipe this window's copies of the passphrase (0.0.0.7 memory hardening).
  // Best effort: the field's text renderer and the input method may still
  // hold copies until that memory is reused.
  OPENSSL_cleanse(passphrase.data(), passphrase.size() * sizeof(char16_t));
  field_->SetText(std::u16string());
  field_->ClearEditHistory();
  if (unlocked) {
    Finish(true);
    return true;
  }
  error_->SetText(l10n_util::GetStringUTF16(IDS_IRIS_UNLOCK_WRONG));
  field_->RequestFocus();
  return false;  // keep the window open
}

bool IrisUnlockDialog::Cancel() {
  Finish(false);
  return true;
}

void IrisUnlockDialog::WindowClosing() {
  Finish(false);
}

void IrisUnlockDialog::Finish(bool unlocked) {
  if (done_) {
    std::move(done_).Run(unlocked);
  }
}
