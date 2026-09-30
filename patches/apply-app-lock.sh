#!/usr/bin/env bash
# Iris — Phase B8 app lock + B10 passphrase encryption (2026-09-28; jegly: the lock is for when Iris opens, no
# idle re-lock).
# New code (patches/src):
#   chrome/browser/iris/iris_app_lock.*            passphrase check (scrypt) + passphrase-wrapped data key (Local State)
#   chrome/browser/iris/iris_key_provider.*         os_crypt_async provider with that key (B10; precedence 20)
#   chrome/browser/ui/views/iris/iris_unlock_dialog.* "Iris is locked" window before any browser window
#   chrome/browser/ui/webui/settings/iris_app_lock_handler.*  Settings messages (set / change / turn off)
#   chrome/browser/resources/settings/privacy_page/iris_app_lock{,.html}.ts  Settings row + dialog
# Wiring: Local State prefs, the unlock window in ChromeBrowserMainParts::PreMainMessageLoopRunImpl right after the
# Linux EULA dialog (same pattern; runs before BrowserProcessImpl::PreMainMessageLoopRun creates the os_crypt_async
# providers, so the key is ready), provider registration, handler registration, strings (all existing messages:
# IDS_SETTINGS_IRIS_APP_LOCK*, IDS_IRIS_UNLOCK_*, IDS_SYNC_PASSPHRASE_LABEL / _MISMATCH_ERROR -> no new IDs).
# Headless with the lock on: exits (nothing can unlock it).
# Guarded; idempotent; fails loudly on drift. Needs apply-shredder.sh + apply-iris-permissions.sh first.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
put() {
  local from="$DIR/src/$1" to="$1"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  mkdir -p "$(dirname "$to")"
  if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
}
put chrome/browser/iris/iris_app_lock.h
put chrome/browser/iris/iris_app_lock.cc
put chrome/browser/iris/iris_key_provider.h
put chrome/browser/iris/iris_key_provider.cc
put chrome/browser/ui/views/iris/iris_unlock_dialog.h
put chrome/browser/ui/views/iris/iris_unlock_dialog.cc
put chrome/browser/ui/webui/settings/iris_app_lock_handler.h
put chrome/browser/ui/webui/settings/iris_app_lock_handler.cc
put chrome/browser/resources/settings/privacy_page/iris_app_lock.ts
put chrome/browser/resources/settings/privacy_page/iris_app_lock.html.ts

python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
def include(p, own, inc):
    s = open(p).read()
    if inc in s: return
    if s.count(own) != 1: die(p + ": own include not found")
    open(p, "w").write(s.replace(own, own + inc, 1)); print("OK   %s : %s" % (p, inc.strip()))

# --- build files
edit("chrome/browser/BUILD.gn",
     '    "iris/iris_shredder.h",  # Iris\n',
     '    "iris/iris_shredder.h",  # Iris\n'
     '    "iris/iris_app_lock.cc",  # Iris (B8)\n    "iris/iris_app_lock.h",  # Iris (B8)\n'
     '    "iris/iris_key_provider.cc",  # Iris (B10)\n    "iris/iris_key_provider.h",  # Iris (B10)\n',
     "iris/iris_app_lock.cc", "core sources")
edit("chrome/browser/BUILD.gn",
     '    deps += [\n      ":fullscreen",\n      ":shell_integration_linux",\n',
     '    deps += [\n      ":fullscreen",\n      ":shell_integration_linux",\n'
     '      "//chrome/browser/ui/views:iris_unlock_dialog",  # Iris (B8)\n',
     "ui/views:iris_unlock_dialog", "core dep on the unlock window")
edit("chrome/browser/ui/views/BUILD.gn",
     '  source_set("eula_dialog_linux") {\n',
     '  # Iris (B8): the app-lock window shown before the first browser window.\n'
     '  source_set("iris_unlock_dialog") {\n'
     '    public = [ "iris/iris_unlock_dialog.h" ]\n'
     '    sources = [ "iris/iris_unlock_dialog.cc" ]\n'
     '    public_deps = [ "//ui/views" ]\n'
     '    deps = [\n'
     '      "//base",\n'
     '      "//chrome/app:generated_resources",\n'
     '      "//ui/base",\n'
     '      "//ui/color",\n'
     '      "//ui/gfx",\n'
     '    ]\n'
     '  }\n\n'
     '  source_set("eula_dialog_linux") {\n',
     'source_set("iris_unlock_dialog")', "unlock window target")
edit("chrome/browser/ui/webui/settings/BUILD.gn",
     '    "site_settings_handler.cc",\n    "site_settings_helper.cc",\n  ]\n',
     '    "site_settings_handler.cc",\n    "site_settings_helper.cc",\n'
     '    "iris_app_lock_handler.cc",  # Iris (B8)\n    "iris_app_lock_handler.h",  # Iris (B8)\n  ]\n',
     "iris_app_lock_handler.cc", "handler sources")
edit("chrome/browser/resources/settings/BUILD.gn",
     '    "privacy_page/do_not_track_toggle.ts",\n',
     '    "privacy_page/do_not_track_toggle.ts",\n'
     '    "privacy_page/iris_app_lock.html.ts",  # Iris (B8)\n'
     '    "privacy_page/iris_app_lock.ts",  # Iris (B8)\n',
     "privacy_page/iris_app_lock.ts", "settings ts files")

# --- Local State prefs
p = "chrome/browser/prefs/browser_prefs.cc"
edit(p, "void RegisterLocalState(PrefRegistrySimple* registry) {\n",
     "void RegisterLocalState(PrefRegistrySimple* registry) {\n"
     "  iris_app_lock::RegisterLocalStatePrefs(registry);  // Iris (B8)\n",
     "iris_app_lock::RegisterLocalStatePrefs", "Local State prefs")
include(p, '#include "chrome/browser/prefs/browser_prefs.h"\n', '#include "chrome/browser/iris/iris_app_lock.h"  // Iris (B8)\n')

# --- unlock before any window
p = "chrome/browser/chrome_browser_main.cc"
edit(p, "      !headless::IsHeadlessMode() && !first_run::ShowEulaDialog()) {\n"
        "    return CHROME_RESULT_CODE_EULA_REFUSED;\n  }\n#endif\n",
     "      !headless::IsHeadlessMode() && !first_run::ShowEulaDialog()) {\n"
     "    return CHROME_RESULT_CODE_EULA_REFUSED;\n  }\n\n"
     "  // Iris (B8): app lock. Ask for the passphrase before anything opens; the\n"
     "  // unlocked key is what the Iris os_crypt_async provider uses (B10).\n"
     "  if (iris_app_lock::IsEnabled(g_browser_process->local_state())) {\n"
     "    if (headless::IsHeadlessMode()) {\n"
     "      LOG(ERROR) << \"Iris is locked with a passphrase; headless mode cannot \"\n"
     "                    \"unlock it.\";\n"
     "      return CHROME_RESULT_CODE_NORMAL_EXIT_CANCEL;\n"
     "    }\n"
     "    if (!IrisUnlockDialog::Run(base::BindRepeating(\n"
     "            [](const std::u16string& passphrase) {\n"
     "              return iris_app_lock::Unlock(\n"
     "                  g_browser_process->local_state(), passphrase);\n"
     "            }))) {\n"
     "      return CHROME_RESULT_CODE_NORMAL_EXIT_CANCEL;\n"
     "    }\n"
     "  }\n#endif\n",
     "iris_app_lock::IsEnabled(g_browser_process->local_state())", "unlock before startup")
include(p, '#include "chrome/browser/chrome_browser_main.h"\n',
        '#include "chrome/browser/iris/iris_app_lock.h"  // Iris (B8)\n')
s = open(p).read()
inc = '#if BUILDFLAG(IS_LINUX)\n#include "chrome/browser/ui/views/iris/iris_unlock_dialog.h"  // Iris (B8)\n#endif\n'
if inc not in s:
    a = '#include "chrome/browser/iris/iris_app_lock.h"  // Iris (B8)\n'
    open(p, "w").write(s.replace(a, a + inc, 1)); print("OK   %s : include unlock window" % p)

# --- B10 provider
p = "chrome/browser/browser_process_impl.cc"
edit(p, "  os_crypt_async_ =\n      std::make_unique<os_crypt_async::OSCryptAsync>(std::move(providers));\n",
     "  // Iris (B10): the app-lock data key encrypts new data while the lock is on.\n"
     "  providers.emplace_back(IrisKeyProvider::kPrecedence,\n"
     "                         std::make_unique<IrisKeyProvider>(local_state()));\n\n"
     "  os_crypt_async_ =\n      std::make_unique<os_crypt_async::OSCryptAsync>(std::move(providers));\n",
     "IrisKeyProvider::kPrecedence", "register key provider")
include(p, '#include "chrome/browser/browser_process_impl.h"\n',
        '#include "chrome/browser/iris/iris_key_provider.h"  // Iris (B10)\n')

# --- Settings handler + strings + row
p = "chrome/browser/ui/webui/settings/settings_ui.cc"
edit(p, "  AddSettingsPageUIHandler(std::make_unique<SiteSettingsHandler>(profile));\n",
     "  AddSettingsPageUIHandler(std::make_unique<SiteSettingsHandler>(profile));\n"
     "  AddSettingsPageUIHandler(std::make_unique<IrisAppLockHandler>());  // Iris (B8)\n",
     "IrisAppLockHandler>()", "handler registered")
include(p, '#include "chrome/browser/ui/webui/settings/site_settings_handler.h"\n',
        '#include "chrome/browser/ui/webui/settings/iris_app_lock_handler.h"  // Iris (B8)\n')
edit("chrome/browser/ui/webui/settings/settings_localized_strings_provider.cc",
     '      {"irisShredding", IDS_SETTINGS_IRIS_SHREDDING},  // Iris (B7)\n',
     '      {"irisShredding", IDS_SETTINGS_IRIS_SHREDDING},  // Iris (B7)\n'
     '      // Iris (B8): app lock.\n'
     '      {"irisAppLock", IDS_SETTINGS_IRIS_APP_LOCK},\n'
     '      {"irisAppLockSublabel", IDS_SETTINGS_IRIS_APP_LOCK_SUBLABEL},\n'
     '      {"irisAppLockSet", IDS_SETTINGS_IRIS_APP_LOCK_SET},\n'
     '      {"irisAppLockChange", IDS_SETTINGS_IRIS_APP_LOCK_CHANGE},\n'
     '      {"irisAppLockRemove", IDS_SETTINGS_IRIS_APP_LOCK_REMOVE},\n'
     '      {"irisAppLockWarning", IDS_SETTINGS_IRIS_APP_LOCK_WARNING},\n'
     '      {"irisUnlockPrompt", IDS_IRIS_UNLOCK_PROMPT},\n'
     '      {"irisUnlockWrong", IDS_IRIS_UNLOCK_WRONG},\n'
     '      {"irisPassphraseLabel", IDS_SYNC_PASSPHRASE_LABEL},\n'
     '      {"irisPassphraseMismatch", IDS_SYNC_PASSPHRASE_MISMATCH_ERROR},\n',
     '"irisAppLockSublabel"', "strings registered")
edit("chrome/browser/resources/settings/privacy_page/privacy_page.html",
     "    <!-- Iris (B7): automatic data deletion, off by default (apply-shredder.sh) -->\n",
     "    <!-- Iris (B8): app lock (apply-app-lock.sh) -->\n"
     "    <settings-iris-app-lock></settings-iris-app-lock>\n"
     "    <!-- Iris (B7): automatic data deletion, off by default (apply-shredder.sh) -->\n",
     "settings-iris-app-lock", "Privacy row")
edit("chrome/browser/resources/settings/privacy_page/privacy_page.ts",
     "import '../controls/settings_toggle_button.js';\n",
     "import '../controls/settings_toggle_button.js';\nimport './iris_app_lock.js';  // Iris (B8)\n",
     "import './iris_app_lock.js';", "import the element")
PY
echo "=== app lock (B8) + passphrase encryption (B10) complete ==="
