#!/usr/bin/env bash
# Iris — Android: blocked pop-up message gets "Allow once" + "Always allow" (jegly 2026-10-08: "a pop up says it's
# blocked, only option is to allow; add allow once / always allow, blocked by default stays"; verified against
# 156.0.8078.11). Upstream's message (PopupBlockedMessageDelegate) has ONE button, "Show", which both opens the blocked
# pop-ups AND saves a permanent ALLOW exception for the site.
#  - Primary button: "Allow once" = open the blocked pop-ups now, change no setting (the site stays blocked).
#  - Secondary (gear) menu: "Always allow for this site" = the old behaviour (permanent ALLOW exception + open them).
# Pop-ups stay BLOCKED by default (the content-setting default is untouched). Policy-managed sites keep the plain "OK".
# English-only labels (no new grit strings = no rebuild of everything that includes the string headers).
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (components/blocked_content/android).
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
B = "components/blocked_content/android/"
edit(B + "popup_blocked_message_delegate.h", "  void HandleClick();\n",
     "  void HandleClick();\n  void HandleAlwaysAllowClick();  // Iris: apply-android-popup-allow-once.sh\n",
     "HandleAlwaysAllowClick", "header")
c = B + "popup_blocked_message_delegate.cc"
edit(c, "  message->SetPrimaryButtonText(l10n_util::GetStringUTF16(button_text_id));\n",
     "  message->SetPrimaryButtonText(l10n_util::GetStringUTF16(button_text_id));\n"
     "  // Iris: \"Allow once\" (primary) + \"Always allow for this site\" (gear menu);\n"
     "  // blocked stays the default (apply-android-popup-allow-once.sh).\n"
     "  if (allow_settings_changes_) {\n"
     "    message->SetPrimaryButtonText(u\"Allow once\");\n"
     "    message->SetSecondaryIconResourceId(\n"
     "        messages::MessageDispatcherBridge::Get()->MapToJavaDrawableId(\n"
     "            IDR_ANDROID_SETTINGS));\n"
     "    message->SetSecondaryButtonMenuText(\n"
     "        u\"Always allow for this site\");\n"
     "    message->SetSecondaryActionCallback(base::BindRepeating(\n"
     "        &PopupBlockedMessageDelegate::HandleAlwaysAllowClick,\n"
     "        base::Unretained(this)));\n"
     "  }\n",
     'u"Allow once"', "buttons")
edit(c, "  // Create exceptions.\n  map_->SetNarrowestContentSetting(url_, url_, ContentSettingsType::POPUPS,\n"
        "                                   CONTENT_SETTING_ALLOW);\n\n  // Launch popups.\n",
     "  // Iris: \"Allow once\" - open the blocked pop-ups, keep the site blocked.\n"
     "  // (\"Always allow\" is HandleAlwaysAllowClick().)\n\n  // Launch popups.\n",
     'Iris: "Allow once" - open the blocked pop-ups', "allow once")
edit(c, "WEB_CONTENTS_USER_DATA_KEY_IMPL(PopupBlockedMessageDelegate);\n",
     "// Iris: the old behaviour - permanent exception for this site, then show the pop-ups.\n"
     "void PopupBlockedMessageDelegate::HandleAlwaysAllowClick() {\n"
     "  if (!allow_settings_changes_ || !map_) {\n    return;\n  }\n"
     "  map_->SetNarrowestContentSetting(url_, url_, ContentSettingsType::POPUPS,\n"
     "                                   CONTENT_SETTING_ALLOW);\n"
     "  ShowBlockedPopups(&GetWebContents());\n"
     "  if (on_show_popups_callback_) {\n    std::move(on_show_popups_callback_).Run();\n  }\n}\n\n"
     "WEB_CONTENTS_USER_DATA_KEY_IMPL(PopupBlockedMessageDelegate);\n",
     "PopupBlockedMessageDelegate::HandleAlwaysAllowClick() {", "always allow")
PY
echo "=== Android pop-up allow once / always allow complete ==="
