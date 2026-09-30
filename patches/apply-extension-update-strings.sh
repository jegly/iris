#!/usr/bin/env bash
# Iris — B12 follow-up: the "Update extensions automatically" toggle uses translatable strings
# (IDS_SETTINGS_IRIS_EXTENSION_AUTO_UPDATE{,_SUBLABEL}, added by apply-iris-permissions.sh) instead of the English
# literals apply-extension-update-toggle.sh had to use. Needs both of those scripts first.
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
g = open("chrome/app/settings_strings.grdp").read()
if "IDS_SETTINGS_IRIS_EXTENSION_AUTO_UPDATE_SUBLABEL" not in g: die("strings missing: run apply-iris-permissions.sh first")
edit("chrome/browser/resources/settings/system_page/system_page.html.ts",
     "  <!-- Iris: extension update toggle (apply-extension-update-toggle.sh; English-only label, TODO localize) -->\n",
     "  <!-- Iris: extension update toggle (apply-extension-update-toggle.sh + -strings.sh) -->\n",
     "apply-extension-update-toggle.sh + -strings.sh", "comment")
edit("chrome/browser/resources/settings/system_page/system_page.html.ts",
     "      label=\"Update extensions automatically\"\n"
     "      sub-label=\"Checks the Chrome Web Store for extension updates, including security fixes. Google then sees which extensions you have installed.\">\n",
     "      label=\"$i18n{irisExtensionAutoUpdate}\"\n"
     "      sub-label=\"$i18n{irisExtensionAutoUpdateSublabel}\">\n",
     "$i18n{irisExtensionAutoUpdate}", "translatable label")
edit("chrome/browser/ui/webui/settings/settings_localized_strings_provider.cc",
     "      {\"hardwareAccelerationLabel\",\n       IDS_SETTINGS_SYSTEM_HARDWARE_ACCELERATION_LABEL},\n",
     "      {\"hardwareAccelerationLabel\",\n       IDS_SETTINGS_SYSTEM_HARDWARE_ACCELERATION_LABEL},\n"
     "      {\"irisExtensionAutoUpdate\", IDS_SETTINGS_IRIS_EXTENSION_AUTO_UPDATE},  // Iris\n"
     "      {\"irisExtensionAutoUpdateSublabel\",\n"
     "       IDS_SETTINGS_IRIS_EXTENSION_AUTO_UPDATE_SUBLABEL},  // Iris\n",
     "\"irisExtensionAutoUpdate\"", "strings registered")
PY
echo "=== extension update strings complete ==="
