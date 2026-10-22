// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: "Block copied commands from websites" (Settings > Privacy and security > Iris hardening > Data;
// apply-clickfix-guard.sh). ClickFix scams put a command on the clipboard ("verify you are human: press Win+R and
// paste") so that the user runs it outside the browser. Every text a web page writes to the clipboard (Ctrl+C,
// copy buttons, navigator.clipboard) passes through ChromeContentBrowserClient::IsClipboardCopyAllowedByPolicy;
// when it looks like one of these commands, a warning is put on the clipboard instead. Everything is decided on the
// device: nothing is sent anywhere (Chrome's version sends the text to Safe Browsing).
// High precision over coverage: a plain installer line from a docs page ("curl -fsSL https://... | sh",
// "irm get.scoop.sh | iex") is let through; what is caught is what such lines never have: hidden windows, encoded
// payloads, mshta and other Windows download tricks, "I am not a robot" comments, padding that hides the command in
// the Run box, and download-and-run from a bare IP address.

#ifndef CHROME_BROWSER_IRIS_IRIS_CLICKFIX_GUARD_H_
#define CHROME_BROWSER_IRIS_IRIS_CLICKFIX_GUARD_H_

#include <optional>
#include <string>
#include <string_view>

namespace content {
class BrowserContext;
}

namespace iris::clickfix {

inline constexpr char kEnabledPref[] = "iris.privacy.clickfix_guard";  // default on

bool LooksLikeClickFixCommand(std::u16string_view text);

// The warning to put on the clipboard instead of `text`, or nullopt to let the copy through.
std::optional<std::u16string> Replacement(content::BrowserContext* context, std::u16string_view text);

}  // namespace iris::clickfix

#endif  // CHROME_BROWSER_IRIS_IRIS_CLICKFIX_GUARD_H_
