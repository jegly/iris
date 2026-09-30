// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B8): Settings -> Privacy and security -> "Lock Iris with a passphrase". Set, change or turn off
// the app lock (chrome/browser/iris/iris_app_lock.h). Replies: "ok", "wrong" (current passphrase wrong) or
// "empty".

#ifndef CHROME_BROWSER_UI_WEBUI_SETTINGS_IRIS_APP_LOCK_HANDLER_H_
#define CHROME_BROWSER_UI_WEBUI_SETTINGS_IRIS_APP_LOCK_HANDLER_H_

#include "base/values.h"
#include "chrome/browser/ui/webui/settings/settings_page_ui_handler.h"

namespace settings {

class IrisAppLockHandler : public SettingsPageUIHandler {
 public:
  IrisAppLockHandler();
  IrisAppLockHandler(const IrisAppLockHandler&) = delete;
  IrisAppLockHandler& operator=(const IrisAppLockHandler&) = delete;
  ~IrisAppLockHandler() override;

  // SettingsPageUIHandler:
  void RegisterMessages() override;
  void OnJavascriptAllowed() override {}
  void OnJavascriptDisallowed() override {}

 private:
  void HandleGetStatus(const base::ListValue& args);
  void HandleSet(const base::ListValue& args);
  void HandleRemove(const base::ListValue& args);
};

}  // namespace settings

#endif  // CHROME_BROWSER_UI_WEBUI_SETTINGS_IRIS_APP_LOCK_HANDLER_H_
