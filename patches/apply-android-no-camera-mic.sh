#!/usr/bin/env bash
# Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
# Iris — Android: no camera and no microphone at all (jegly 2026-11-07), OS-enforced like location
# (apply-android-manifest-harden.sh). Removed from chrome/android/java/AndroidManifest.xml: CAMERA, RECORD_AUDIO,
# FOREGROUND_SERVICE_CAMERA, FOREGROUND_SERVICE_MICROPHONE and the camera/microphone uses-feature lines; the same four
# permissions are also stripped (tools:node="remove") if a library manifest adds them back.
# Android then never grants Iris the camera or microphone: websites can't use them even when allowed in site
# settings (Chromium asks Android, which denies at once, as for location). Cost: no video/voice calls, no voice
# input, no in-page camera on any site. MediaCaptureNotificationService (type camera|microphone) stays declared:
# it is only started while a page captures camera/mic, which can no longer happen.
# Kept: MODIFY_AUDIO_SETTINGS (audio output routing, grants no recording).
# Also: Site settings hides the Camera, Microphone and Location rows (ChromeSiteSettingsDelegate.isCategoryVisible).
# Guarded; idempotent; fails loudly on drift. Run after apply-android-manifest-harden.sh.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/android/java/AndroidManifest.xml"
MARK = "    <!-- Iris: no camera / microphone (apply-android-no-camera-mic.sh) -->\n"
DELETE = [
 '    <uses-permission android:name="android.permission.CAMERA" />\n',
 '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA" />\n',
 '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />\n',
 '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n',
 '    <!-- android.permission.CAMERA -->\n'
 '    <uses-feature android:name="android.hardware.camera" android:required="false" />\n'
 '    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />\n'
 '    <!-- android.permission.RECORD_AUDIO -->\n'
 '    <uses-feature android:name="android.hardware.microphone" android:required="false" />\n',
]
REMOVED = ["android.permission.CAMERA", "android.permission.RECORD_AUDIO",
           "android.permission.FOREGROUND_SERVICE_CAMERA", "android.permission.FOREGROUND_SERVICE_MICROPHONE"]
s = open(p).read()
if MARK in s:
    print("SKIP already applied: %s (no camera / microphone)" % p)
else:
    for d in DELETE:
        if s.count(d) != 1: die("%s: block not found exactly once (drift?):\n%s" % (p, d))
        s = s.replace(d, "")
    anchor = "    {% block extra_uses_permissions %}\n"
    if s.count(anchor) != 1: die("%s: extra_uses_permissions block not found (drift?)" % p)
    s = s.replace(anchor, MARK + "".join('    <uses-permission android:name="%s" tools:node="remove" />\n' % n
                                          for n in REMOVED) + "\n" + anchor)
    open(p, "w").write(s); print("OK   %s : camera + microphone removed (%d blocks, %d stripped from libraries)"
                                 % (p, len(DELETE), len(REMOVED)))
# Site settings: hide the Camera, Microphone and Location rows (jegly 2026-11-07: Iris has none of these Android
# permissions, so the rows offered a choice that does nothing). Chromium's own hook for unsupported categories.
p = "chrome/android/java/src/org/chromium/chrome/browser/site_settings/ChromeSiteSettingsDelegate.java"
M2 = ("            // Iris: no camera / microphone / location permission in the APK, so no rows\n"
      "            // (apply-android-no-camera-mic.sh)\n")
s = open(p).read()
old = ("    public boolean isCategoryVisible(@SiteSettingsCategory.Type int type) {\n"
       "        switch (type) {\n")
if M2 in s:
    print("SKIP already applied: %s (Site settings rows)" % p)
else:
    if s.count(old) != 1: die("%s: isCategoryVisible anchor not found exactly once (drift?)" % p)
    s = s.replace(old, old + M2 +
                  "            case SiteSettingsCategory.Type.CAMERA:\n"
                  "            case SiteSettingsCategory.Type.MICROPHONE:\n"
                  "            case SiteSettingsCategory.Type.DEVICE_LOCATION:\n"
                  "                return false;\n", 1)
    open(p, "w").write(s); print("OK   %s : Camera, Microphone, Location rows hidden" % p)

PY
