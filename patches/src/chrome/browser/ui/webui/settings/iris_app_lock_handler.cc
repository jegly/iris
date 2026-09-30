// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/webui/settings/iris_app_lock_handler.h"

#include <string>

#include "base/functional/bind.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/iris/iris_app_lock.h"

namespace settings {

namespace {

base::Value ResultValue(iris_app_lock::Result result) {
  switch (result) {
    case iris_app_lock::Result::kOk:
      return base::Value("ok");
    case iris_app_lock::Result::kWrongPassphrase:
      return base::Value("wrong");
    case iris_app_lock::Result::kEmptyPassphrase:
      return base::Value("empty");
  }
}

std::u16string Arg(const base::ListValue& args, size_t index) {
  const std::string* value =
      args.size() > index ? args[index].GetIfString() : nullptr;
  return value ? base::UTF8ToUTF16(*value) : std::u16string();
}

}  // namespace

IrisAppLockHandler::IrisAppLockHandler() = default;
IrisAppLockHandler::~IrisAppLockHandler() = default;

void IrisAppLockHandler::RegisterMessages() {
  web_ui()->RegisterMessageCallback(
      "irisAppLockGetStatus",
      base::BindRepeating(&IrisAppLockHandler::HandleGetStatus,
                          base::Unretained(this)));
  web_ui()->RegisterMessageCallback(
      "irisAppLockSet", base::BindRepeating(&IrisAppLockHandler::HandleSet,
                                            base::Unretained(this)));
  web_ui()->RegisterMessageCallback(
      "irisAppLockRemove",
      base::BindRepeating(&IrisAppLockHandler::HandleRemove,
                          base::Unretained(this)));
}

void IrisAppLockHandler::HandleGetStatus(const base::ListValue& args) {
  AllowJavascript();
  ResolveJavascriptCallback(
      args[0],
      base::Value(iris_app_lock::IsEnabled(g_browser_process->local_state())));
}

// args: callback id, current passphrase (ignored when the lock is off), new.
void IrisAppLockHandler::HandleSet(const base::ListValue& args) {
  AllowJavascript();
  ResolveJavascriptCallback(
      args[0], ResultValue(iris_app_lock::SetPassphrase(
                   g_browser_process->local_state(), Arg(args, 1),
                   Arg(args, 2))));
}

// args: callback id, current passphrase.
void IrisAppLockHandler::HandleRemove(const base::ListValue& args) {
  AllowJavascript();
  ResolveJavascriptCallback(
      args[0], ResultValue(iris_app_lock::Remove(
                   g_browser_process->local_state(), Arg(args, 1))));
}

}  // namespace settings
