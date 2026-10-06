#!/usr/bin/env bash
# Iris — Android manifest hardening, round 2 (jegly 2026-10-06, from an APK Auditor report on release -3;
# verified against the real 156.0.8078.11 chrome/android/java/AndroidManifest.xml). Needs apply-android-manifest-
# harden.sh first (same file, different anchors).
#  1. Gemini external trigger: the exported IntentDispatcher intent filter "...glic.EXTERNAL_TRIGGERING" (the template
#     ships it on the 'canary'/'default' channels, which includes Iris) is removed: Iris has no AI (jegly 2026-10-01).
#  2. Web NFC is off, so IntentDispatcher no longer listens for NFC "NDEF_DISCOVERED" tags with http(s) links.
#  3. WebAPK / Trusted Web Activity entry points that can't work without Google (Iris cannot mint WebAPKs, no Play):
#     ActivateWebApkActivity and ManageTrustedWebActivityDataActivity -> exported="false"; the 'default'-channel DEBUG
#     intent filter on InstalledWebappBroadcastReceiver is removed (a debug trigger that shipped in release builds).
#     Kept on purpose: WebappLauncherActivity (home-screen shortcuts for installed sites) and the Custom Tabs service.
#  4. ChromeBrowserProvider (the legacy browser bookmarks/history/search provider) -> exported="false": any app could
#     query it (no permission). Nothing in Iris uses it from outside (checked: only the provider, its Impl and tests
#     reference it). Kept exported: AutofillThirdPartyModeContentProvider (Android autofill apps ask it one yes/no).
#  5. Permissions nothing in Iris uses: com.chrome.permission.DEVICE_EXTRAS (only Google Chrome honours it; only the
#     manifest mentions it), POST_PROMOTED_NOTIFICATIONS (Gemini 'actor' live updates), USE_FINGERPRINT (deprecated;
#     USE_BIOMETRIC stays for the app lock), com.android.launcher.permission.INSTALL_SHORTCUT (legacy; minSdk is 29).
#     tools:node="remove" lines also drop them if a library manifest adds them back.
# NOT changed (on purpose; reasons in memory/00_STATE.md): the crash-upload services, Firebase classes and the dead
# feature components stay DECLARED (removing a declared service/activity that Java code still starts can crash at
# runtime; they are not exported); READ/WRITE_EXTERNAL_STORAGE and DOWNLOAD_WITHOUT_NOTIFICATION (unclear what breaks).
# STATUS 2026-10-06: copy-tested only, NOT compile-proven (merge_manifests / the merged manifest check below).
# Verify after the APK build: unzip -p the APK's AndroidManifest.xml (or gen/chrome/android/chrome_public_apk/
# AndroidManifest.merged.xml) has no glic action, no ChromeBrowserProvider exported="true".
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/android/java/AndroidManifest.xml"
s = open(p).read()
MARK = "<!-- Iris: leftover permissions removed (apply-android-manifest-harden2.sh) -->\n"
if MARK in s:
    print("SKIP already applied: %s" % p); sys.exit(0)

def cut(old, new, what):
    global s
    if s.count(old) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
    s = s.replace(old, new, 1)

# 1. Gemini external trigger
cut("            <!-- TODO(b/548888503): Remove after approval.-->\n"
    "            {% if channel in ['canary', 'default'] %}\n"
    "            <!-- This starts FGS and finishes, does not show anything to the\n"
    "                 user. Caller needs to be a trusted google app and need to use\n"
    "                 startActivityForResult. -->\n"
    "            <intent-filter>\n"
    "                <action android:name=\"org.chromium.chrome.browser.glic.EXTERNAL_TRIGGERING\" />\n"
    "                <category android:name=\"android.intent.category.DEFAULT\" />\n"
    "            </intent-filter>\n"
    "            {% endif %}\n",
    "            <!-- Iris: no Gemini external trigger (apply-android-manifest-harden2.sh) -->\n",
    "glic external-trigger intent filter")
# 2. NFC tags
cut("            <intent-filter>\n"
    "                <action android:name=\"android.nfc.action.NDEF_DISCOVERED\" />\n"
    "                <category android:name=\"android.intent.category.DEFAULT\" />\n"
    "                <data android:scheme=\"http\" />\n"
    "                <data android:scheme=\"https\" />\n"
    "            </intent-filter>\n",
    "            <!-- Iris: no NFC tag filter (Web NFC is off) -->\n",
    "NFC NDEF_DISCOVERED intent filter")
# 3. WebAPK / TWA
cut("        <activity android:name=\"org.chromium.chrome.browser.webapps.ActivateWebApkActivity\"\n"
    "            android:theme=\"@style/Theme.BrowserUI.NoDisplay\"\n"
    "            android:exported=\"true\">\n",
    "        <activity android:name=\"org.chromium.chrome.browser.webapps.ActivateWebApkActivity\"\n"
    "            android:theme=\"@style/Theme.BrowserUI.NoDisplay\"\n"
    "            android:exported=\"false\">  <!-- Iris: no WebAPKs -->\n",
    "ActivateWebApkActivity export")
cut("            android:name=\"org.chromium.chrome.browser.browserservices.ManageTrustedWebActivityDataActivity\"\n"
    "            android:theme=\"@style/Theme.Chromium.Activity.Fullscreen.Transparent\"\n"
    "            android:exported=\"true\">\n",
    "            android:name=\"org.chromium.chrome.browser.browserservices.ManageTrustedWebActivityDataActivity\"\n"
    "            android:theme=\"@style/Theme.Chromium.Activity.Fullscreen.Transparent\"\n"
    "            android:exported=\"false\">  <!-- Iris: no Trusted Web Activity apps -->\n",
    "ManageTrustedWebActivityDataActivity export")
cut("            {% if channel in ['default'] %}\n"
    "            <intent-filter>\n"
    "                <action android:name=\"org.chromium.chrome.browser.browserservices.InstalledWebappBroadcastReceiver.DEBUG\" />\n"
    "            </intent-filter>\n"
    "            {% endif %}\n",
    "            <!-- Iris: no DEBUG trigger in release builds -->\n",
    "InstalledWebappBroadcastReceiver DEBUG filter")
# 4. ChromeBrowserProvider
cut("          android:authorities=\"{{ manifest_package }}.ChromeBrowserProvider;{{ manifest_package }}.browser;{{ manifest_package }}\"\n"
    "          android:exported=\"true\">\n",
    "          android:authorities=\"{{ manifest_package }}.ChromeBrowserProvider;{{ manifest_package }}.browser;{{ manifest_package }}\"\n"
    "          android:exported=\"false\">  <!-- Iris: bookmarks/history are not shared with other apps -->\n",
    "ChromeBrowserProvider export")
# 5. permissions
PERMS = [
    ("    <!-- Permission to request promoted ongoing status (Live Updates) for Actor task notifications on Android 16+. -->\n"
     "    <uses-permission android:name=\"android.permission.POST_PROMOTED_NOTIFICATIONS\" />\n",
     "android.permission.POST_PROMOTED_NOTIFICATIONS", "POST_PROMOTED_NOTIFICATIONS"),
    ("    <uses-permission-sdk-23 android:name=\"android.permission.USE_FINGERPRINT\"/>\n",
     "android.permission.USE_FINGERPRINT", "USE_FINGERPRINT"),
    ("    <uses-permission android:name=\"com.chrome.permission.DEVICE_EXTRAS\" />\n",
     "com.chrome.permission.DEVICE_EXTRAS", "DEVICE_EXTRAS"),
    ("    <uses-permission android:name=\"com.android.launcher.permission.INSTALL_SHORTCUT\"/>\n",
     "com.android.launcher.permission.INSTALL_SHORTCUT", "INSTALL_SHORTCUT"),
]
removed = []
for old, name, what in PERMS:
    cut(old, "", what + " declaration")
    removed.append(name)
anchor = "    {% block extra_uses_permissions %}\n"
cut(anchor, MARK + "".join('    <uses-permission android:name="%s" tools:node="remove" />\n' % n for n in removed)
    + "\n" + anchor, "extra_uses_permissions block")
open(p, "w").write(s)
print("OK   %s : glic + NFC filters, WebAPK/TWA exports, DEBUG filter, ChromeBrowserProvider export, 4 permissions" % p)
PY
echo "=== Android manifest hardening round 2 complete ==="
