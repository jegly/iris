#!/usr/bin/env bash
# Iris — Phase B12: "Update extensions automatically" toggle, default OFF (jegly 2026-09-26; verified against this
# checkout 2026-09-27).
# Before: extension update checks (background AND the manual "Update" button on chrome://extensions) are gated by
# ExtensionsBrowserClient::IsBackgroundUpdateAllowed() (extensions/browser/updater/update_service.cc +
# extension_downloader.cc), which Chrome ties to --disable-background-networking. Iris always sets that switch
# (apply-default-switches.sh), so extensions could never update: no security fixes for extensions.
# After: the gate reads a browser-wide pref "iris.extensions.auto_update" (Local State, default false):
#  - registered next to GpuModeManager's local-state prefs (chrome/browser/prefs/browser_prefs.cc);
#  - allowlisted for chrome://settings (settings_private prefs_util.cc; FindServiceForPref falls back to Local State);
#  - toggle in Settings -> System, under "Use graphics acceleration". Takes effect at the next update check.
# The other background networking stays off. Update checks go to the Chrome Web Store, which then sees the IDs of
# the installed extensions — the toggle's sub-label says so.
# Label is English-only on purpose: a new grit string in generated_resources.grd would rebuild thousands of files.
# TODO (release): localize the label/sub-label.
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
PREF = "iris.extensions.auto_update"

edit("chrome/browser/prefs/browser_prefs.cc",
     "  GpuModeManager::RegisterPrefs(registry);\n",
     "  GpuModeManager::RegisterPrefs(registry);\n"
     "  // Iris: extension update checks, off unless the user turns them on\n"
     "  // (Settings -> System). Read by ChromeExtensionsBrowserClient.\n"
     "  registry->RegisterBooleanPref(\"%s\", false);\n" % PREF,
     PREF, "register %s (Local State, default false)" % PREF)

p = "chrome/browser/extensions/chrome_extensions_browser_client.cc"
s = open(p).read()
for inc in ('#include "chrome/browser/browser_process.h"', '#include "components/prefs/pref_service.h"'):
    if inc not in s: die(p + ": missing " + inc)
edit(p,
     "bool ChromeExtensionsBrowserClient::IsBackgroundUpdateAllowed() {\n"
     "  return !base::CommandLine::ForCurrentProcess()->HasSwitch(\n"
     "      ::switches::kDisableBackgroundNetworking);\n"
     "}\n",
     "bool ChromeExtensionsBrowserClient::IsBackgroundUpdateAllowed() {\n"
     "  // Iris: extension updates follow the user's \"Update extensions\n"
     "  // automatically\" setting (default off), not the always-set\n"
     "  // --disable-background-networking switch.\n"
     "  PrefService* local_state =\n"
     "      g_browser_process ? g_browser_process->local_state() : nullptr;\n"
     "  return local_state && local_state->GetBoolean(\"%s\");\n"
     "}\n" % PREF,
     PREF, "update gate reads %s" % PREF)

edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[::prefs::kHardwareAccelerationModeEnabled] =\n"
     "      settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[::prefs::kHardwareAccelerationModeEnabled] =\n"
     "      settings_api::PrefType::kBoolean;\n"
     "  // Iris: Settings -> System -> \"Update extensions automatically\".\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % PREF,
     PREF, "settings may read/write %s" % PREF)

edit("chrome/browser/resources/settings/system_page/system_page.html.ts",
     "      <cr-button @click=\"${this.onRestartClick_}\" slot=\"more-actions\">\n"
     "        $i18n{restart}\n"
     "      </cr-button>\n"
     "    ` : ''}\n"
     "  </settings-toggle-button>\n",
     "      <cr-button @click=\"${this.onRestartClick_}\" slot=\"more-actions\">\n"
     "        $i18n{restart}\n"
     "      </cr-button>\n"
     "    ` : ''}\n"
     "  </settings-toggle-button>\n"
     "  <!-- Iris: extension update toggle (apply-extension-update-toggle.sh; English-only label, TODO localize) -->\n"
     "  <div class=\"hr\"></div>\n"
     "  <settings-toggle-button id=\"irisExtensionAutoUpdate\"\n"
     "      pref-key=\"%s\"\n"
     "      label=\"Update extensions automatically\"\n"
     "      sub-label=\"Checks the Chrome Web Store for extension updates, including security fixes. Google then sees which extensions you have installed.\">\n"
     "  </settings-toggle-button>\n" % PREF,
     PREF, "System page toggle")
PY
echo "=== extension auto-update toggle complete ==="
