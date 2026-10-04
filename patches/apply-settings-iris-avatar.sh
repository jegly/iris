#!/usr/bin/env bash
# Iris — Settings "You and Iris": the default profile picture is the Iris orb (jegly 2026-10-04; verified against the
# 156.0.8073.0 and 156.0.8078.9 sources).
# Before: ProfileInfoHandler::GetAccountNameAndIcon() (chrome/browser/ui/webui/settings/profile_info_handler.cc) sends
# entry->GetAvatarIcon(), which for a profile that never picked a picture is Chromium's grey person placeholder.
# After: while the profile uses the default avatar (ProfileAttributesEntry::IsUsingDefaultAvatar()), the row shows
# IDR_PRODUCT_LOGO_32 = the orb (apply-rebrand-logos.sh replaces that image; 1x + 2x). A picture the user chooses
# still wins. Desktop only (Android settings have their own profile header; ChromeOS branch untouched).
# Build: //chrome/app/theme:theme_resources added to the settings source_set deps for chrome/grit/theme_resources.h.
# STATUS 2026-10-04: copy-tested only, NOT compile-proven (profile_info_handler.o).
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

p = "chrome/browser/ui/webui/settings/profile_info_handler.cc"
edit(p,
     '#include "chrome/browser/profiles/profile_statistics_factory.h"\n'
     '#include "third_party/skia/include/core/SkBitmap.h"\n',
     '#include "chrome/browser/profiles/profile_statistics_factory.h"\n'
     '#include "chrome/grit/theme_resources.h"  // Iris: orb as default avatar\n'
     '#include "third_party/skia/include/core/SkBitmap.h"\n'
     '#include "ui/base/resource/resource_bundle.h"  // Iris\n',
     "// Iris: orb as default avatar", "includes")
edit(p,
     "    gfx::Image icon = profiles::GetSizedAvatarIcon(\n"
     "        entry->GetAvatarIcon(), kAvatarIconSize, kAvatarIconSize);\n",
     "    // Iris: a profile without a chosen picture shows the Iris orb.\n"
     "    gfx::Image icon = profiles::GetSizedAvatarIcon(\n"
     "        entry->IsUsingDefaultAvatar()\n"
     "            ? ui::ResourceBundle::GetSharedInstance().GetImageNamed(\n"
     "                  IDR_PRODUCT_LOGO_32)\n"
     "            : entry->GetAvatarIcon(),\n"
     "        kAvatarIconSize, kAvatarIconSize);\n",
     "// Iris: a profile without a chosen picture shows the Iris orb.", "orb for the default avatar")
edit("chrome/browser/ui/webui/settings/BUILD.gn",
     '    "//chrome/app/vector_icons",\n',
     '    "//chrome/app/vector_icons",\n'
     '    "//chrome/app/theme:theme_resources",  # Iris: orb avatar (profile_info_handler.cc)\n',
     "# Iris: orb avatar", "theme_resources dep")
PY
echo "=== settings Iris avatar complete ==="
