#!/usr/bin/env bash
# Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
# Iris — Android Settings > About Iris (jegly 2026-11-07):
# 1) Legal information line: "Copyright <year> jegly. All rights reserved." (same as desktop, apply-rebrand.sh);
#    upstream's Android string says "Google LLC" and was not covered by the rebrand.
# 2) Legal information page: only "Open source licenses"; the Google Terms of Service, Chrome additional terms and
#    Google Privacy Policy links are removed (they do not apply to Iris).
# 3) OS version: "Android <version>" only, without the phone model and build number (same as Iris's
#    chrome://version, apply-android-no-gms.sh; people share screenshots of this page).
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

# 1) copyright line
p = "chrome/android/java/src/org/chromium/chrome/browser/about_settings/AboutChromeSettings.java"
M = "        // Iris: same copyright line as desktop (apply-android-about-page.sh)\n"
edit(p, "        p.setSummary(getString(R.string.legal_information_summary, currentYear));\n",
     M + "        p.setSummary(\"Copyright \" + currentYear + \" jegly. All rights reserved.\");\n",
     M, "copyright jegly")

# 2) legal page: open source licenses only
p = "chrome/android/java/res/xml/legal_information_preferences.xml"
M = "    <!-- Iris: Google terms and privacy policy links removed (apply-android-about-page.sh) -->\n"
edit(p,
     "        app:url=\"@string/open_source_license_url\" />\n"
     "    <org.chromium.chrome.browser.about_settings.HyperlinkPreference\n"
     "        android:key=\"google_terms_of_service\"\n"
     "        android:title=\"@string/google_terms_of_service_title\"\n"
     "        app:url=\"@string/google_terms_of_service_url\" />\n"
     "    <org.chromium.chrome.browser.about_settings.HyperlinkPreference\n"
     "        android:key=\"chrome_additional_terms_of_service\"\n"
     "        android:title=\"@string/chrome_additional_terms_of_service_title\"\n"
     "        app:url=\"@string/chrome_additional_terms_of_service_url\" />\n"
     "    <org.chromium.chrome.browser.about_settings.HyperlinkPreference\n"
     "        android:key=\"privacy_policy\"\n"
     "        android:title=\"@string/privacy_policy_title\"\n"
     "        app:url=\"@string/google_privacy_policy_url\" />\n",
     "        app:url=\"@string/open_source_license_url\" />\n" + M,
     M, "legal page links")

# 3) OS version without model / build number
p = "chrome/browser/android/preferences/about_settings_bridge.cc"
M = "  // Iris: Android version only, no phone model / build number (apply-android-about-page.sh)\n"
edit(p, "#include \"base/strings/string_util.h\"\n",
     "#include \"base/strings/string_util.h\"\n#include \"base/system/sys_info.h\"\n",
     "#include \"base/system/sys_info.h\"\n", "sys_info include")
edit(p,
     "  return base::JoinString(\n"
     "      {version_info::GetOSType(), AndroidAboutAppInfo::GetOsInfo()},\n"
     "      kSeparator);\n",
     M + "  return base::JoinString(\n"
     "      {version_info::GetOSType(), base::SysInfo::OperatingSystemVersion()},\n"
     "      kSeparator);\n",
     M, "OS version")
PY
