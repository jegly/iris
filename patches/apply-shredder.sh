#!/usr/bin/env bash
# Iris — Phase B7: automatic data deletion, a toggle, OFF by default (jegly 2026-09-26; verified against this
# checkout 2026-09-27). New chrome/browser/iris/iris_shredder.* (KeyedService, created with each regular profile):
# hourly, if profile pref iris.shredding.enabled: cookies+site data > 24 h, cache > 12 h, downloads list > 7 days
# (Chromium's BrowsingDataRemover). Toggle: Settings -> Privacy and security, strings from apply-iris-permissions.sh.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
mkdir -p chrome/browser/iris
for f in iris_shredder.h iris_shredder.cc; do
  from="$DIR/src/chrome/browser/iris/$f"; to="chrome/browser/iris/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
if "IDS_SETTINGS_IRIS_SHREDDING_SUBLABEL" not in open("chrome/app/settings_strings.grdp").read():
    die("strings missing: run apply-iris-permissions.sh first")
edit("chrome/browser/BUILD.gn", "    \"iris/iris_google_signin_throttle.h\",  # Iris\n",
     "    \"iris/iris_google_signin_throttle.h\",  # Iris\n"
     "    \"iris/iris_shredder.cc\",  # Iris\n    \"iris/iris_shredder.h\",  # Iris\n",
     "iris/iris_shredder.cc", "BUILD: shredder sources")
p = "chrome/browser/prefs/browser_prefs.cc"
edit(p, "  ChromeContentBrowserClient::RegisterProfilePrefs(registry);\n",
     "  ChromeContentBrowserClient::RegisterProfilePrefs(registry);\n"
     "  IrisShredder::RegisterProfilePrefs(registry);  // Iris (B7)\n",
     "IrisShredder::RegisterProfilePrefs", "register pref")
s = open(p).read(); inc = '#include "chrome/browser/iris/iris_shredder.h"  // Iris\n'
if inc not in s:
    a = '#include "chrome/browser/prefs/browser_prefs.h"\n'
    if s.count(a) != 1: die(p + ": own include not found")
    open(p, "w").write(s.replace(a, a + inc, 1)); print("OK   %s : include" % p)
p = "chrome/browser/profiles/chrome_browser_main_extra_parts_profiles.cc"
edit(p, "  AccessibilityLabelsServiceFactory::GetInstance();\n",
     "  AccessibilityLabelsServiceFactory::GetInstance();\n"
     "  IrisShredderFactory::GetInstance();  // Iris (B7)\n",
     "IrisShredderFactory::GetInstance();", "factory built at startup")
s = open(p).read()
if inc not in s:
    a = '#include "chrome/browser/profiles/chrome_browser_main_extra_parts_profiles.h"\n'
    if s.count(a) != 1: die(p + ": own include not found")
    open(p, "w").write(s.replace(a, a + inc, 1)); print("OK   %s : include" % p)
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[\"iris.extensions.auto_update\"] = settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[\"iris.extensions.auto_update\"] = settings_api::PrefType::kBoolean;\n"
     "  // Iris (B7): Settings -> Privacy -> \"Delete browsing data automatically\".\n"
     "  (*s_allowlist)[\"iris.shredding.enabled\"] = settings_api::PrefType::kBoolean;\n",
     "iris.shredding.enabled", "settings may read/write the pref")
edit("chrome/browser/resources/settings/privacy_page/privacy_page.html",
     "    <settings-toggle-button id=\"irisSearchSuggestToggle\" class=\"hr\"\n",
     "    <!-- Iris (B7): automatic data deletion, off by default (apply-shredder.sh) -->\n"
     "    <settings-toggle-button id=\"irisShreddingToggle\" class=\"hr\"\n"
     "        pref-key=\"iris.shredding.enabled\"\n"
     "        label=\"$i18n{irisShredding}\"\n"
     "        sub-label=\"$i18n{irisShreddingSublabel}\">\n"
     "    </settings-toggle-button>\n"
     "    <settings-toggle-button id=\"irisSearchSuggestToggle\" class=\"hr\"\n",
     "irisShreddingToggle", "Privacy toggle")
edit("chrome/browser/ui/webui/settings/settings_localized_strings_provider.cc",
     "      {\"hardwareAccelerationLabel\",\n       IDS_SETTINGS_SYSTEM_HARDWARE_ACCELERATION_LABEL},\n",
     "      {\"hardwareAccelerationLabel\",\n       IDS_SETTINGS_SYSTEM_HARDWARE_ACCELERATION_LABEL},\n"
     "      {\"irisShredding\", IDS_SETTINGS_IRIS_SHREDDING},  // Iris (B7)\n"
     "      {\"irisShreddingSublabel\", IDS_SETTINGS_IRIS_SHREDDING_SUBLABEL},  // Iris\n",
     "\"irisShredding\"", "strings registered")
PY
echo "=== automatic data deletion complete ==="
