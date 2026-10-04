#!/usr/bin/env bash
# Iris — the "Iris is locked" window uses the user's theme (jegly 2026-10-04: the lock window "doesn't match whatever
# theme the user has set"; verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# Why it didn't: the unlock window opens before any profile is loaded (apply-app-lock.sh, chrome_browser_main.cc), and
# the palette (picked seed colour, profile pref kUserColor) and Light/Dark mode (kBrowserColorScheme) live in the
# profile. The window only had the system default.
# Now:
#  - ThemeService (chrome/browser/themes/theme_service.cc) copies the look into Local State on start (Init) and on
#    every theme change (NotifyThemeChanged): iris_app_lock::kLockPalettePref (palette index from the reserved seed,
#    -1 = none) and kLockColorSchemePref (0 system, 1 light, 2 dark). Registered in iris_app_lock.cc.
#  - chrome_browser_main.cc passes both to IrisUnlockDialog::Run (apply-app-lock.sh), which sets the widget's colour
#    mode + user colour overrides -> the Iris palette mixer (apply-catppuccin-default.sh) colours it like the browser.
# Needs apply-app-lock.sh (copies the updated patches/src files: iris_app_lock.*, iris_unlock_dialog.*) and
# apply-catppuccin-default.sh (ui/color/iris_palettes.h). Desktop (the lock window is Linux-only; Android uses its own
# Java lock screen with the Android theme).
# Note: a tree patched before 2026-10-04 keeps the old call (defaults: dark, no palette) until apply-app-lock.sh runs
# on a fresh checkout.
# STATUS 2026-10-04: copy-tested only, NOT compile-proven (theme_service.o, iris_unlock_dialog.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/themes/theme_service.cc"
s = open(p).read()
MARK = "IrisSaveLockScreenLook"
if MARK in s:
    print("SKIP already applied: %s" % p); sys.exit(0)
inc_anchor = '#include "chrome/browser/browser_process.h"\n'
init_anchor = ("void ThemeService::Init() {\n"
               "  theme_helper_->DCheckCalledOnValidSequence();\n"
               "\n"
               "  InitFromPrefs();\n")
notify_anchor = ("void ThemeService::NotifyThemeChanged() {\n"
                 "  if (!ready_ || should_suppress_theme_updates_) {\n"
                 "    return;\n"
                 "  }\n")
for a, what in ((inc_anchor, "browser_process.h include"), (init_anchor, "ThemeService::Init"),
                (notify_anchor, "ThemeService::NotifyThemeChanged")):
    if s.count(a) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
s = s.replace(inc_anchor, inc_anchor +
              '#include "chrome/browser/iris/iris_app_lock.h"  // Iris: lock-screen look\n'
              '#include "components/prefs/pref_service.h"  // Iris\n'
              '#include "ui/color/iris_palettes.h"  // Iris\n', 1)
helper = ("namespace {\n\n"
          "// Iris: copy the browser look (palette + Light/Dark) into Local State for the\n"
          "// \"Iris is locked\" window, which opens before any profile is loaded\n"
          "// (apply-lock-screen-theme.sh; read in chrome_browser_main.cc).\n"
          "void IrisSaveLockScreenLook(const ThemeService& theme_service) {\n"
          "  PrefService* local_state =\n"
          "      g_browser_process ? g_browser_process->local_state() : nullptr;\n"
          "  if (!local_state) {\n"
          "    return;\n"
          "  }\n"
          "  const std::optional<SkColor> seed = theme_service.GetUserColor();\n"
          "  int palette = -1;\n"
          "  if (ui::iris::PaletteForSeed(seed)) {\n"
          "    palette = static_cast<int>((SkColorGetG(*seed) << 8) | SkColorGetB(*seed));\n"
          "  }\n"
          "  local_state->SetInteger(iris_app_lock::kLockPalettePref, palette);\n"
          "  local_state->SetInteger(\n"
          "      iris_app_lock::kLockColorSchemePref,\n"
          "      static_cast<int>(theme_service.GetBrowserColorScheme()));\n"
          "}\n\n"
          "}  // namespace\n\n")
s = s.replace(init_anchor, helper + init_anchor + "  IrisSaveLockScreenLook(*this);  // Iris\n", 1)
s = s.replace(notify_anchor, notify_anchor + "\n  IrisSaveLockScreenLook(*this);  // Iris: lock-screen look\n", 1)
open(p, "w").write(s)
print("OK   %s : theme look saved to Local State (start + every change)" % p)
PY
echo "=== lock screen theme complete ==="
