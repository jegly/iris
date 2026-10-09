#!/usr/bin/env bash
# Iris — desktop: blocked pop-up bubble gets "Allow once" (jegly 2026-10-09: "add allow once button for the desktop
# version"; verified against 156.0.8078.11). The address-bar pop-up bubble (ContentSettingPopupBubbleModel) already has
# the radio group (keep blocking / always allow) and a clickable list of blocked pop-ups. New: a link above the radio
# group, "Allow once: open the blocked pop-ups now", that opens ALL blocked pop-ups of this page through
# PopupBlockerTabHelper::ShowAllBlockedPopups() and closes the bubble. No setting changes: the site stays blocked.
# The link uses the bubble's existing custom_link slot (same slot as the mixed-content "Load unsafe scripts" link).
# English-only label (no new grit string). Android is apply-android-popup-allow-once.sh.
# STATUS 2026-10-09: copy-tested only, NOT compile-proven.
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
P = "chrome/browser/ui/content_settings/content_setting_bubble_model.cc"
edit(P, "  // ContentSettingBubbleModel:\n  void CommitChanges() override;\n\n"
        "  // PopupBlockerTabHelper::Observer:\n",
     "  // ContentSettingBubbleModel:\n  void CommitChanges() override;\n"
     "  void OnCustomLinkClicked() override;  // Iris: apply-popup-allow-once-desktop.sh\n\n"
     "  // PopupBlockerTabHelper::Observer:\n",
     "OnCustomLinkClicked() override;  // Iris: apply-popup-allow-once-desktop.sh", "declaration")
edit(P, "  set_title(l10n_util::GetStringUTF16(IDS_BLOCKED_POPUPS_TITLE));\n\n  // Build blocked popup list.\n",
     "  set_title(l10n_util::GetStringUTF16(IDS_BLOCKED_POPUPS_TITLE));\n\n"
     "  // Iris: \"Allow once\" opens the blocked pop-ups without changing the setting\n"
     "  // (apply-popup-allow-once-desktop.sh).\n"
     "  set_custom_link(u\"Allow once: open the blocked pop-ups now\");\n"
     "  set_custom_link_enabled(true);\n\n"
     "  // Build blocked popup list.\n",
     "Allow once: open the blocked pop-ups now", "link")
edit(P, "void ContentSettingPopupBubbleModel::CommitChanges() {\n",
     "// Iris: apply-popup-allow-once-desktop.sh\n"
     "void ContentSettingPopupBubbleModel::OnCustomLinkClicked() {\n"
     "  auto* helper =\n"
     "      blocked_content::PopupBlockerTabHelper::FromWebContents(web_contents());\n"
     "  if (helper) {\n"
     "    helper->ShowAllBlockedPopups();\n"
     "  }\n"
     "}\n\n"
     "void ContentSettingPopupBubbleModel::CommitChanges() {\n",
     "void ContentSettingPopupBubbleModel::OnCustomLinkClicked()", "handler")
PY
echo "=== desktop pop-up Allow once complete ==="
