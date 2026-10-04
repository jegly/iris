#!/usr/bin/env bash
# Iris — no Safe Browsing "Enhanced protection" (jegly 2026-10-04: "enhanced protection just needs to be removed";
# verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# Enhanced protection = real-time URL checks, download and page content sent to Google, account-level protection.
# Iris has no Google API keys and doesn't send browsing data to Google, so the option goes:
#  1. Core: safe_browsing::IsEnhancedProtectionEnabled() (components/safe_browsing/core/common/safe_browsing_prefs.cc)
#     always returns false. GetSafeBrowsingState() and every Enhanced-only path (real-time lookups, deep scanning,
#     extended reporting, promos, Privacy Guide) then treat the profile as Standard/No protection, even if the
#     kSafeBrowsingEnhanced pref were set by an old profile or a sync/promo. Desktop + Android.
#  2. Desktop Settings -> Security: the Enhanced radio is hidden on both page versions (security_page.html:
#     #safeBrowsingEnhanced; security_page_v2.html: the "Enhanced" security bundle card and #enhancedProtectionButton).
#  3. Android Settings -> Privacy and security -> Safe Browsing: the Enhanced radio is GONE instead of VISIBLE
#     (RadioButtonGroupSafeBrowsingPreference.onBindViewHolder).
# Standard / No protection stay as they are.
# STATUS 2026-10-04: copy-tested only, NOT compile-proven (safe_browsing_prefs.o, settings WebUI, chrome_java).
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

edit("components/safe_browsing/core/common/safe_browsing_prefs.cc",
     "bool IsEnhancedProtectionEnabled(const PrefService& prefs) {\n"
     "  // SafeBrowsingEnabled is checked too due to devices being out\n"
     "  // of sync or not on a version that includes SafeBrowsingEnhanced pref.\n"
     "  return prefs.GetBoolean(prefs::kSafeBrowsingEnhanced) &&\n"
     "         IsSafeBrowsingEnabled(prefs);\n"
     "}\n",
     "bool IsEnhancedProtectionEnabled(const PrefService& prefs) {\n"
     "  // Iris: Enhanced protection (sends browsing data to Google) is never on.\n"
     "  return false;\n"
     "}\n",
     "// Iris: Enhanced protection (sends browsing data to Google) is never on.", "Enhanced protection always off")

SEC = "chrome/browser/resources/settings/privacy_page/security/"
edit(SEC + "security_page.html",
     '        <settings-collapse-radio-button id="safeBrowsingEnhanced"\n',
     '        <!-- Iris: Enhanced protection removed (apply-no-enhanced-protection.sh) -->\n'
     '        <settings-collapse-radio-button id="safeBrowsingEnhanced" hidden\n',
     "<!-- Iris: Enhanced protection removed", "Security page: Enhanced radio hidden")
p = SEC + "security_page_v2.html"
s = open(p).read()
MARK = "<!-- Iris: Enhanced protection removed"
if MARK in s:
    print("SKIP already applied: %s" % p)
else:
    a1 = ('      <div class="box card card-end">\n'
          '        <controlled-radio-button id="securitySettingsBundleEnhanced"\n')
    a2 = '          <controlled-radio-button id="enhancedProtectionButton"\n'
    for a, what in ((a1, "Enhanced security bundle card"), (a2, "#enhancedProtectionButton")):
        if s.count(a) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
    s = s.replace(a1, '      <!-- Iris: Enhanced protection removed (apply-no-enhanced-protection.sh) -->\n'
                      '      <div class="box card card-end" hidden>\n'
                      '        <controlled-radio-button id="securitySettingsBundleEnhanced"\n', 1)
    s = s.replace(a2, '          <controlled-radio-button id="enhancedProtectionButton" hidden\n', 1)
    open(p, "w").write(s); print("OK   %s : Security page v2: Enhanced bundle + radio hidden" % p)

edit("chrome/browser/safe_browsing/android/java/src/org/chromium/chrome/browser/safe_browsing/settings/"
     "RadioButtonGroupSafeBrowsingPreference.java",
     "        mEnhancedProtection.setVisibility(View.VISIBLE);\n",
     "        mEnhancedProtection.setVisibility(View.GONE); // Iris: no Enhanced protection\n",
     "// Iris: no Enhanced protection", "Android: Enhanced radio gone")
PY
echo "=== Enhanced protection removal complete ==="
