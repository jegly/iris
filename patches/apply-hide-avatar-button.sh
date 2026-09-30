#!/usr/bin/env bash
# Iris — no profile (avatar) button in the toolbar for a single normal profile (jegly 2026-09-30).
# Iris has no Google sign-in/sync, so with one profile the button only opens a near-empty menu. Profiles stay managed
# in Settings -> You and Iris. The button still shows in Incognito and Guest windows (visible "private window" cue)
# and whenever more than one profile exists (it is the profile switcher). Ctrl+Shift+M (IDC_SHOW_AVATAR_MENU) is
# disabled while the button is hidden, so nothing anchors a bubble to an invisible button.
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

p = "chrome/browser/ui/views/toolbar/avatar_toolbar_button_interface.cc"
edit(p, '#include "chrome/browser/profiles/profile.h"\n',
     '#include "chrome/browser/browser_process.h"\n'
     '#include "chrome/browser/profiles/profile.h"\n'
     '#include "chrome/browser/profiles/profile_manager.h"\n',
     '#include "chrome/browser/profiles/profile_manager.h"', "includes")
edit(p,
     '  // DevTools profiles are OffTheRecord, so hide it there.\n'
     '  return profile->IsIncognitoProfile() || profile->IsGuestSession() ||\n'
     '         profile->IsEnterpriseIsolatedModeProfile() ||\n'
     '         profile->IsRegularProfile();\n',
     '  // DevTools profiles are OffTheRecord, so hide it there.\n'
     '  // Iris: a single normal profile gets no toolbar button (apply-hide-avatar-button.sh).\n'
     '  if (profile->IsRegularProfile()) {\n'
     '    ProfileManager* profile_manager = g_browser_process->profile_manager();\n'
     '    return profile_manager && profile_manager->GetNumberOfProfiles() > 1;\n'
     '  }\n'
     '  return profile->IsIncognitoProfile() || profile->IsGuestSession() ||\n'
     '         profile->IsEnterpriseIsolatedModeProfile();\n',
     "apply-hide-avatar-button.sh", "single-profile rule")

p = "chrome/browser/ui/browser_command_controller.cc"
if '#include "chrome/browser/browser_process.h"' not in open(p).read(): die(p + ": browser_process.h include gone (drift?)")
edit(p, '#include "chrome/browser/browser_process.h"\n',
     '#include "chrome/browser/browser_process.h"\n'
     '#include "chrome/browser/profiles/profile_manager.h"  // Iris (hidden avatar button)\n',
     "Iris (hidden avatar button)", "include")
edit(p,
     '  command_updater_->UpdateCommandEnabled(IDC_SHOW_AVATAR_MENU,\n'
     '                                         /*state=*/normal_window);\n',
     '  // Iris: off while the toolbar profile button is hidden\n'
     '  // (single normal profile, apply-hide-avatar-button.sh).\n'
     '  command_updater_->UpdateCommandEnabled(\n'
     '      IDC_SHOW_AVATAR_MENU,\n'
     '      /*state=*/normal_window &&\n'
     '          (!profile()->IsRegularProfile() ||\n'
     '           (g_browser_process->profile_manager() &&\n'
     '            g_browser_process->profile_manager()->GetNumberOfProfiles() > 1)));\n',
     "single normal profile, apply-hide-avatar-button.sh", "shortcut disabled when hidden")
PY
echo "=== avatar button hidden for a single profile ==="
