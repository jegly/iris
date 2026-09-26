#!/usr/bin/env bash
# Iris — Phase A default flips (approved by jegly 2026-09-26; verified against checkout 2026-09-26).
# Source of the list: research/phase-a-decisions.md "APPROVED ... item 1".
#
# NETWORK
# - HSTS applied to top-level navigations only (net kHstsTopLevelNavigationsOnly -> ENABLED). Safari model: kills
#   HSTS "supercookies" (per-subresource HSTS bits as a tracking vector). Subresources on https pages are still
#   protected by mixed-content blocking/autoupgrade; http top-level pages are covered by HTTPS-Only below.
#   Consumer: net/http/transport_security_state.cc GetSSLUpgradeDecision().
# - HTTPS-Only strict (prefs::kHttpsOnlyModeEnabled false -> true, chrome/browser/ui/browser_ui_prefs.cc): warns
#   before any http:// page. Registered for ALL platforms (browser_prefs.cc RegisterBrowserUserPrefs, no Android
#   guard); Android's settings read it via chrome/browser/ssl/android/https_first_mode_bridge.cc.
# BUILT-IN FEATURES
# - PDFs open externally (kPluginsAlwaysOpenPdfExternally false -> true): PDFium never parses web-served PDFs
#   (they download instead). Desktop pref; Android has no in-browser PDF plugin path here.
# - Spellcheck off (kSpellCheckEnable true -> false): enabling it downloads dictionaries from Google.
# - Autofill addresses + cards off (kAutofillProfileEnabled / kAutofillCreditCardEnabled true -> false).
# - Password manager "offer to save" off (kCredentialsEnableService true -> false). Saved passwords still fill.
# PERMISSIONS default ASK -> BLOCK (per-site Allow still works via site settings / page info; BLOCK is in each
#   type's valid_settings, checked below): camera, microphone, geolocation, notifications, clipboard read.
# ANDROID
# - Location via Android's own LocationManager, not Google Play Services: ChromeContentBrowserClient::
#   ShouldUseGmsCoreGeolocationProvider() true -> false. content/browser/device/device_service.cc passes it to
#   the device service; false => LocationProviderFactory.create() picks LocationProviderAndroid.
# - android:allowBackup: NO EDIT NEEDED. chrome/android/java/AndroidManifest.xml only sets "true" inside
#   {% if backup_key is defined %}, and backup_key is a Google-internal template variable that nothing in the
#   public tree defines -> Iris already gets the {% else %} branch = "false". Guarded below so drift is caught.
#
# Guarded; idempotent (re-run = SKIP); fails loudly on drift. Anchored replacements bind the value to the anchor
# with \s* only (see memory/01_GOTCHAS.md "Patch method").
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)

def anchored(path, anchor, old, new, label):
    """Replace `old` -> `new` where it directly follows `anchor` (only whitespace between)."""
    s = open(path).read()
    pat_old = re.compile(re.escape(anchor) + r'(\s*)' + re.escape(old))
    pat_new = re.compile(re.escape(anchor) + r'\s*' + re.escape(new))
    n_old, n_new = len(pat_old.findall(s)), len(pat_new.findall(s))
    if n_old == 0 and n_new == 1: print(f"SKIP already applied: {label}"); return
    if n_old != 1: die(f"{path}: {label}: anchor+old found {n_old}x, anchor+new {n_new}x (drift?)")
    s = pat_old.sub(lambda m: anchor + m.group(1) + new, s, count=1)
    open(path, "w").write(s); print(f"OK   {label} ({path})")

# --- network ---
anchored("net/base/features.cc", "BASE_FEATURE(kHstsTopLevelNavigationsOnly,",
         "base::FEATURE_DISABLED_BY_DEFAULT", "base::FEATURE_ENABLED_BY_DEFAULT", "HSTS top-level navigations only")
anchored("chrome/browser/ui/browser_ui_prefs.cc", "prefs::kHttpsOnlyModeEnabled,", "false", "true",
         "HTTPS-Only strict mode")

# --- built-in features ---
anchored("chrome/browser/plugins/plugin_prefs_factory.cc", "prefs::kPluginsAlwaysOpenPdfExternally,",
         "false", "true", "PDFs open externally")
anchored("chrome/browser/spellchecker/spellcheck_factory.cc", "spellcheck::prefs::kSpellCheckEnable,",
         "true", "false", "spellcheck off")
anchored("components/autofill/core/common/autofill_prefs.cc", "kAutofillProfileEnabled,", "true", "false",
         "autofill addresses off")
anchored("components/autofill/core/common/autofill_prefs.cc", "kAutofillCreditCardEnabled,", "true", "false",
         "autofill cards off")
anchored("components/password_manager/core/browser/password_manager.cc", "prefs::kCredentialsEnableService,",
         "true", "false", "password saving off")

# --- permissions ASK -> BLOCK ---
REG = "components/content_settings/core/browser/content_settings_registry.cc"
s = open(REG).read()
for typ, name in [("MEDIASTREAM_CAMERA", "media-stream-camera"), ("MEDIASTREAM_MIC", "media-stream-mic"),
                  ("GEOLOCATION", "geolocation"), ("NOTIFICATIONS", "notifications"),
                  ("CLIPBOARD_READ_WRITE", "clipboard")]:
    anchor = f'ContentSettingsType::{typ}, "{name}",'
    i = s.find(anchor)
    if i < 0 or s.count(anchor) != 1: die(f"{REG}: registration of {typ} not found exactly once (drift?)")
    blk = s[i:s.find(");", i)]
    if "CONTENT_SETTING_BLOCK" not in blk.split("valid_settings", 1)[-1]:
        die(f"{REG}: {typ}: CONTENT_SETTING_BLOCK not in valid_settings")
    anchored(REG, anchor, "CONTENT_SETTING_ASK,", "CONTENT_SETTING_BLOCK,", f"{typ} default BLOCK")
    s = open(REG).read()

# --- Android ---
anchored("chrome/browser/chrome_content_browser_client.cc",
         "bool ChromeContentBrowserClient::ShouldUseGmsCoreGeolocationProvider() {\n"
         "  // Indicate that Chrome uses the GMS core location provider.\n  return",
         "true;", "false;  // Iris: Android LocationManager, not Play Services",
         "Android location without Play Services")

m = "chrome/android/java/AndroidManifest.xml"; s = open(m).read()
guard = re.compile(r'\{% if backup_key is defined %\}\s*android:allowBackup="true".*?\{% else %\}\s*'
                   r'android:allowBackup="false"', re.S)
if not guard.search(s): die(f"{m}: allowBackup template changed — re-check that Iris still gets allowBackup=false")
if re.search(r'backup_key\s*=', open("chrome/android/BUILD.gn").read()):
    die("chrome/android/BUILD.gn now defines backup_key — allowBackup would become true")
print("OK   guard: Android allowBackup=false (backup_key undefined)")
PY
echo "=== Phase A flips complete ==="
