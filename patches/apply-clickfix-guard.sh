#!/usr/bin/env bash
# Iris — "Block copied commands from websites" (jegly 2026-10-22, after Chrome's ClickFix warnings, which need Enhanced
# Protection and send the copied text to Safe Browsing). Local only: every text a web page writes to the clipboard
# (Ctrl+C, copy buttons, navigator.clipboard, execCommand) goes through
# ChromeContentBrowserClient::IsClipboardCopyAllowedByPolicy; when it looks like a ClickFix command
# (iris::clickfix::LooksLikeClickFixCommand in patches/src/chrome/browser/iris/iris_clickfix_guard.cc) a warning is
# written to the clipboard instead, through the same replacement path enterprise copy rules use. Nothing is sent anywhere.
# Plain installer lines (rustup, Homebrew, Scoop, Bun, Chocolatey, NodeSource) are let through; caught: bait comments
# ("I am not a robot", reCAPTCHA/Cloudflare IDs, ✅), padding that hides the command, hidden/headless windows, encoded
# PowerShell, base64 piped into a shell, mshta/certutil/bitsadmin/regsvr32/rundll32/msiexec/wscript downloads,
# finger | cmd, AppleScript downloads, download-and-run from a bare IP. Detector tested 2026-10-22 on 29 cases (14
# lures, 15 legit), stand-alone with stub base/ headers: all correct.
# Profile pref iris.privacy.clickfix_guard, ON by default (registered in iris_shredder.cc).
# Desktop: Settings -> Privacy and security -> Iris hardening -> Data. Android: Iris switches -> Data.
# Needs apply-shredder, apply-iris-hardening-page, apply-privacy-toggles-3, apply-android-iris-privacy-settings,
# apply-block-third-party (anchors). STATUS 2026-10-22: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in chrome/browser/iris/iris_clickfix_guard.h chrome/browser/iris/iris_clickfix_guard.cc \
         chrome/browser/iris/iris_shredder.cc; do
  from="$DIR/src/$f"; [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  mkdir -p "$(dirname "$f")"
  if cmp -s "$from" "$f"; then echo "SKIP up to date: $f"; else cp "$from" "$f"; echo "OK   $f"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
edit("chrome/browser/BUILD.gn", "    \"iris/iris_shredder.h\",  # Iris\n",
     "    \"iris/iris_shredder.h\",  # Iris\n"
     "    \"iris/iris_clickfix_guard.cc\",  # Iris\n    \"iris/iris_clickfix_guard.h\",  # Iris\n",
     "iris/iris_clickfix_guard.cc", "BUILD: sources")
C = "chrome/browser/chrome_content_browser_client.cc"
edit(C, '#include "chrome/browser/iris/iris_web_recolor.h"  // Iris\n',
     '#include "chrome/browser/iris/iris_web_recolor.h"  // Iris\n'
     '#include "chrome/browser/iris/iris_clickfix_guard.h"  // Iris\n',
     "iris_clickfix_guard.h", "include")
edit(C, "    IsClipboardCopyAllowedCallback callback) {\n  glic::OnBeforeClipboardCopy(source);\n",
     "    IsClipboardCopyAllowedCallback callback) {\n  glic::OnBeforeClipboardCopy(source);\n"
     "  // Iris: ClickFix guard (apply-clickfix-guard.sh). A command that looks like a ClickFix lure is replaced\n"
     "  // by a warning; decided on the device.\n"
     "  if (metadata.format_type == ui::ClipboardFormatType::PlainTextType()) {\n"
     "    if (std::optional<std::u16string> warning =\n"
     "            iris::clickfix::Replacement(source.browser_context(), data.text)) {\n"
     "      std::move(callback).Run(metadata.format_type, data, std::move(warning));\n"
     "      return;\n"
     "    }\n"
     "  }\n",
     "iris::clickfix::Replacement", "hook")
KEY = "iris.privacy.clickfix_guard"
TITLE = "Block copied commands from websites"
SUB = ("If a website puts a hidden command on your clipboard, the way \\\"ClickFix\\\" scams do (\\\"press Win+R and "
       "paste to prove you are human\\\"), Iris puts a warning there instead. Normal install commands from "
       "documentation are not affected. Checked on your device; nothing is sent anywhere.")
SUB_HTML = SUB.replace('\\"', "&quot;")
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-privacy-toggles-3.sh\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % KEY,
     "\"%s\"" % KEY, "allowlist")
H = "chrome/browser/resources/settings/privacy_page/iris_hardening_page.html"
anchor = ("        label=\"Clear copied text after 30 seconds\"\n"
          "        sub-label=\"Text you copy in Iris is removed from the clipboard after 30 seconds, if it is still there.\">\n"
          "    </settings-toggle-button>\n")
edit(H, anchor,
     anchor +
     "    <settings-toggle-button id=\"irisClickFixGuardToggle\" class=\"hr\"\n"
     "        pref-key=\"%s\"\n"
     "        label=\"%s\"\n"
     "        sub-label=\"%s\">\n"
     "    </settings-toggle-button>\n" % (KEY, TITLE, SUB_HTML),
     "irisClickFixGuardToggle", "desktop toggle")
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
sw = ("        ChromeSwitchPreference irisClickFixGuard =\n"
      "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
      "        irisClickFixGuard.setKey(\"iris_clickfix_guard\");\n"
      "        irisClickFixGuard.setPersistent(false);\n"
      "        irisClickFixGuard.setTitle(\"%s\");\n"
      "        irisClickFixGuard.setSummary(\n"
      "                \"%s\");\n"
      "        irisClickFixGuard.setChecked(UserPrefs.get(getProfile()).getBoolean(\"%s\"));\n"
      "        irisClickFixGuard.setOnPreferenceChangeListener(\n"
      "                (preference, newValue) -> {\n"
      "                    UserPrefs.get(getProfile()).setBoolean(\"%s\", (Boolean) newValue);\n"
      "                    return true;\n"
      "                });\n"
      "        irisCategory.addPreference(irisClickFixGuard);\n") % (TITLE, SUB, KEY, KEY)
edit(J, "        irisCategory.addPreference(irisClearClipboard);\n",
     "        irisCategory.addPreference(irisClearClipboard);\n" + sw,
     "irisClickFixGuard =", "Android switch")
edit(J, '"iris_clear_clipboard", "iris_download_ask"',
     '"iris_clear_clipboard", "iris_clickfix_guard", "iris_download_ask"',
     '"iris_clear_clipboard", "iris_clickfix_guard"', "Android group")
PY
echo "=== ClickFix guard complete ==="
