// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B8): the "Iris is locked" window shown before any browser window when the app lock is on
// (chrome_browser_main.cc, next to the Linux EULA dialog, which it mirrors). Unlock checks the passphrase through
// `try_unlock`; a wrong one shows an error and clears the field. Quit (or closing the window) exits Iris.

#ifndef CHROME_BROWSER_UI_VIEWS_IRIS_IRIS_UNLOCK_DIALOG_H_
#define CHROME_BROWSER_UI_VIEWS_IRIS_IRIS_UNLOCK_DIALOG_H_

#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "ui/views/window/dialog_delegate.h"

namespace views {
class Label;
class Textfield;
}  // namespace views

class IrisUnlockDialog : public views::DialogDelegate {
 public:
  using TryUnlock = base::RepeatingCallback<bool(const std::u16string&)>;

  // Shows the dialog and waits (nested run loop) until the passphrase is
  // accepted (true) or the user quits (false).
  // `palette` (index into ui/color/iris_palettes.h, -1 = none) and
  // `color_scheme` (ThemeService::BrowserColorScheme: 0 system, 1 light,
  // 2 dark) give the window the browser's look; the caller reads them from
  // Local State (iris_app_lock::kLockPalettePref / kLockColorSchemePref).
  static bool Run(TryUnlock try_unlock, int palette = -1, int color_scheme = 2);

  IrisUnlockDialog(TryUnlock try_unlock, base::OnceCallback<void(bool)> done);
  IrisUnlockDialog(const IrisUnlockDialog&) = delete;
  IrisUnlockDialog& operator=(const IrisUnlockDialog&) = delete;
  ~IrisUnlockDialog() override;

  // views::DialogDelegate:
  bool Accept() override;
  bool Cancel() override;
  void WindowClosing() override;

 private:
  void Finish(bool unlocked);

  TryUnlock try_unlock_;
  base::OnceCallback<void(bool)> done_;
  raw_ptr<views::Textfield> field_ = nullptr;
  raw_ptr<views::Label> error_ = nullptr;
};

#endif  // CHROME_BROWSER_UI_VIEWS_IRIS_IRIS_UNLOCK_DIALOG_H_
