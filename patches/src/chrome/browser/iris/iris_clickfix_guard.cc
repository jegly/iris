// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_clickfix_guard.h"

#include <algorithm>
#include <initializer_list>
#include <vector>

#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "components/prefs/pref_service.h"
#include "components/user_prefs/user_prefs.h"
#include "content/public/browser/browser_context.h"

namespace iris::clickfix {

namespace {

// ClickFix payloads are one or two lines; a large copy is a page or a document.
constexpr size_t kMaxCheckedLength = 16 * 1024;
// Spaces between the command and its bait comment push the command out of view in the Run box.
constexpr size_t kPaddingRun = 30;

constexpr char16_t kWarning[] =
    u"# Iris blocked this. The website you were on tried to put a hidden command on your clipboard, the way "
    u"\"ClickFix\" scams do. No real website needs you to paste anything into Run, a terminal or PowerShell to "
    u"prove you are human. Do not run anything that page gave you. (To allow copied commands: Settings > Privacy "
    u"and security > Iris hardening > Block copied commands from websites.)";

bool Has(std::string_view s, std::string_view w) {
  return s.find(w) != std::string_view::npos;
}

bool HasAny(std::string_view s, std::initializer_list<std::string_view> words) {
  for (std::string_view w : words) {
    if (Has(s, w)) {
      return true;
    }
  }
  return false;
}

bool IsPadding(char16_t c) {
  return c == u' ' || c == u'\t' || c == 0x00A0 || (c >= 0x2000 && c <= 0x200B) || c == 0x202F ||
         c == 0x205F || c == 0x3000 || c == 0x3164 || c == 0xFEFF;
}

bool IsLineBreak(char16_t c) {
  return c == u'\n' || c == u'\r' || c == 0x2028 || c == 0x2029;
}

// The longest run of padding with text on both sides on the same line (indentation does not count).
size_t LongestInnerPadding(std::u16string_view t) {
  size_t best = 0;
  size_t i = 0;
  while (i < t.size()) {
    if (!IsPadding(t[i])) {
      ++i;
      continue;
    }
    const size_t start = i;
    while (i < t.size() && IsPadding(t[i])) {
      ++i;
    }
    const bool text_before = start > 0 && !IsLineBreak(t[start - 1]);
    const bool text_after = i < t.size() && !IsLineBreak(t[i]);
    if (text_before && text_after) {
      best = std::max(best, i - start);
    }
  }
  return best;
}

// Lower-case UTF-8 with every run of spaces, tabs, line breaks and invisible padding as one space.
std::string Normalize(std::u16string_view t) {
  std::u16string out;
  out.reserve(t.size());
  bool space = false;
  for (char16_t c : t) {
    if (IsPadding(c) || IsLineBreak(c)) {
      space = true;
      continue;
    }
    if (space && !out.empty()) {
      out.push_back(u' ');
    }
    space = false;
    out.push_back(c);
  }
  return base::ToLowerASCII(base::UTF16ToUTF8(out));
}

// http(s)://1.2.3.4 - installers that are meant to be copied come from a named site.
bool HasBareIpUrl(std::string_view s) {
  for (std::string_view scheme : {"http://", "https://"}) {
    size_t pos = 0;
    while ((pos = s.find(scheme, pos)) != std::string_view::npos) {
      pos += scheme.size();
      size_t i = pos;
      int dots = 0;
      bool digits = false;
      while (i < s.size() && (base::IsAsciiDigit(s[i]) || s[i] == '.')) {
        if (s[i] == '.') {
          ++dots;
        } else {
          digits = true;
        }
        ++i;
      }
      if (digits && dots == 3 && (i == s.size() || s[i] == '/' || s[i] == ':')) {
        return true;
      }
    }
  }
  return false;
}

bool PipesIntoShell(std::string_view s) {
  return HasAny(s, {"|sh", "| sh", "|bash", "| bash", "|zsh", "| zsh", "|iex", "| iex", "iex(", "iex (",
                    "|python", "| python", "&& sh ", "; sh ", "|cmd", "| cmd"});
}

// powershell -e / -ec / -enc / -encodedcommand followed by a base64 blob.
bool HasEncodedPowerShell(std::string_view s) {
  if (!HasAny(s, {"powershell", "pwsh"})) {
    return false;
  }
  std::vector<std::string_view> tokens =
      base::SplitStringPiece(s, " ", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
  for (size_t i = 0; i + 1 < tokens.size(); ++i) {
    std::string_view t = tokens[i];
    if (t == "-e" || t == "-ec" || t == "-en" || t == "-enc" || t == "-enco" || t == "-encodedcommand" ||
        t == "/e" || t == "/enc") {
      if (tokens[i + 1].size() >= 20) {
        return true;
      }
    }
  }
  return false;
}

}  // namespace

bool LooksLikeClickFixCommand(std::u16string_view text) {
  if (text.empty() || text.size() > kMaxCheckedLength) {
    return false;
  }
  const std::string s = Normalize(text);
  const bool command =
      HasAny(s, {"powershell", "pwsh", "cmd", "mshta", "rundll32", "regsvr32", "msiexec", "certutil",
                 "bitsadmin", "curl", "wget", "bash", "zsh", "/bin/sh", "osascript", "iex", "invoke-",
                 "conhost", "wscript", "cscript", "finger", "python", "start-process", "explorer"});
  if (!command) {
    return false;
  }

  // Bait in a comment after the command: "# ✅ I am not a robot - reCAPTCHA Verification ID: 4821".
  const size_t hash = s.find('#');
  if (hash != std::string::npos &&
      HasAny(std::string_view(s).substr(hash),
             {"captcha", "robot", "not a bot", "verify you are", "verification id", "verification code",
              "human verification", "cloudflare", "ray id", "\xe2\x9c\x85" /* ✅ */, "\xe2\x9c\x94" /* ✔ */})) {
    return true;
  }
  // The command pushed out of view in the Run box / address bar, with a comment shown in its place.
  if (LongestInnerPadding(text) >= kPaddingRun && (hash != std::string::npos || Has(s, " rem "))) {
    return true;
  }
  // Hidden or headless windows.
  if (HasAny(s, {"powershell", "pwsh"}) &&
      HasAny(s, {"-w hidden", "-w h ", "-w 1 ", "-wi h", "-win h", "-wind", "-noni -w", "/w hidden"})) {
    return true;
  }
  if (Has(s, "conhost") && Has(s, "--headless")) {
    return true;
  }
  if (Has(s, "start /min") || Has(s, "start \"\" /min")) {
    return true;
  }
  // Encoded payloads.
  if (HasEncodedPowerShell(s) || Has(s, "frombase64string")) {
    return true;
  }
  if (Has(s, "base64") && HasAny(s, {" -d", "--decode", " -d|", " -d |"}) && PipesIntoShell(s)) {
    return true;
  }
  // Windows programs that download and run code.
  if (Has(s, "mshta") && HasAny(s, {"http", "javascript:", "vbscript:", "\\\\"})) {
    return true;
  }
  if ((Has(s, "certutil") && HasAny(s, {"urlcache", "-decode"})) || (Has(s, "bitsadmin") && Has(s, "transfer")) ||
      (Has(s, "regsvr32") && HasAny(s, {"http", "/i:"})) ||
      (Has(s, "rundll32") && HasAny(s, {"http", "javascript:", "\\\\", "davclnt"})) ||
      (Has(s, "msiexec") && Has(s, "http")) || (HasAny(s, {"wscript", "cscript"}) && Has(s, "http"))) {
    return true;
  }
  // finger user@host | cmd (fetches the next stage over the finger protocol).
  if (Has(s, "finger ") && Has(s, "@") && Has(s, "|")) {
    return true;
  }
  // macOS: AppleScript that downloads.
  if (Has(s, "osascript") && HasAny(s, {"curl", "http", "do shell script"})) {
    return true;
  }
  // Download-and-run from a bare IP address.
  if (HasBareIpUrl(s) && PipesIntoShell(s)) {
    return true;
  }
  return false;
}

std::optional<std::u16string> Replacement(content::BrowserContext* context, std::u16string_view text) {
  if (context) {
    PrefService* prefs = user_prefs::UserPrefs::Get(context);
    if (prefs && prefs->FindPreference(kEnabledPref) && !prefs->GetBoolean(kEnabledPref)) {
      return std::nullopt;
    }
  }
  if (!LooksLikeClickFixCommand(text)) {
    return std::nullopt;
  }
  return std::u16string(kWarning);
}

}  // namespace iris::clickfix
