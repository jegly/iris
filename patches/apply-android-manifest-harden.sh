#!/usr/bin/env bash
# Iris — Android manifest hardening (jegly 2026-10-01; strict requirement: no Google Play
# services in the Android app). Verified against this checkout.
# chrome/android/java/AndroidManifest.xml (the APK's main manifest template). Removed:
#   - location: ACCESS_FINE/COARSE_LOCATION + the GPS uses-feature (jegly: no location at all)
#   - QUERY_ALL_PACKAGES: without it (and with no <queries> entry for it) Android's package-visibility filter hides
#     Google Play services from Iris -> the OS itself enforces "no Play services", whatever code tries
#   - Google push (FCM): c2dm RECEIVE, own C2D_MESSAGE use, the 3 GCM services (also blocked in code by
#     apply-android-no-gms.sh); Google accounts: GET_ACCOUNTS, MANAGE_ACCOUNTS, USE_CREDENTIALS, Google Now access
#   - Phishing-protection receiver that only Play services may call (INTERNAL_BROADCAST); Cast options meta-data
#   - Privacy Sandbox ad measurement: ACCESS_ADSERVICES_ATTRIBUTION + AD_SERVICES_CONFIG
#   - BLUETOOTH/_ADMIN/_CONNECT/_ADVERTISE/_SCAN (Web Bluetooth off; phone-as-security-key off in the WebAuthn script), NFC (Web NFC
#     off), ACCESS_HID (WebHID off), READ_CONTACTS (Contacts picker off), REQUEST_INSTALL_PACKAGES (Iris never starts
#     APK installs), QUERY_ADVANCED_PROTECTION_MODE (no Advanced Protection Mode; jegly)
#   - local network (jegly): ACCESS_LOCAL_NETWORK (Android 17 local-network access) + USE_LOOPBACK_INTERFACE -> Iris
#     cannot reach devices on the Wi-Fi/LAN (router, NAS, printers) or localhost; OS-enforced on top of LNA blocking
#   A tools:node="remove" list also strips the same permissions if any library manifest adds them back.
# Part 2 — components that Google LIBRARY manifests merge in (found in AndroidManifest.merged.xml 2026-10-01):
#   Firebase (exported FirebaseInstanceIdReceiver, FirebaseMessagingService, ComponentDiscoveryService + registrars),
#   Google datatransport telemetry (backend discovery, job service, alarm receiver), Play services GoogleApiActivity,
#   Cast MediaIntentReceiver, Play Core dialog activity, ARCore InstallActivity + min_apk_version, MLKit discovery,
#   cloudmessaging meta-data, android.ext.adservices library, AICore BIND_SERVICE permission.
# Part 3 — library <queries> for AICore, Play services Cast and ARCore: the merger ignores tools:node on <queries>
#   (verified), so build/android/gyp/merge_manifest.py drops them from the library manifests before merging.
#   Kept on purpose: com.google.android.gms.version meta-data (inert number; Google
#   client code reads it and could crash without it; Play services is invisible to Iris anyway).
#   Verify with the MERGED manifest (gen/chrome/android/chrome_public_apk/AndroidManifest.merged.xml), never the template.
# WebAuthn: see apply-android-webauthn-credman.sh (Credential Manager, no Play services).
# Kept: Credential Manager (passkeys/security keys), internet/network state, camera + microphone (runtime prompts; blocked by default), notifications, biometric
#   (app lock), storage/downloads, media foreground services, home-screen shortcuts.
# Part 4 — leftovers (jegly 2026-10-01 'remove all the android leftovers'):
#   - Actor (Gemini agent) foreground service: drop the EXPORTED variant used in local 'default'-channel builds; keep
#     the private one (Glic/actor is off; nothing outside Iris can start it)
#   - PaymentDetailsUpdateService (exported; Payment Request is off in Iris)
#   - VR: Daydream/Cardboard intent filter; XR immersive-video activity + com.android.extensions.xr library
#   - permissions: RECEIVE_BOOT_COMPLETED (no boot receiver exists), FOREGROUND_SERVICE_MEDIA_PROJECTION (getDisplayMedia
#     is 'experimental' on Android = off for websites; MediaCaptureNotificationService type -> camera|microphone),
#     CAPTURE_KEYBOARD (Keyboard Lock API: WindowAndroid.setHasKeyboardCapture() returns false first, so the
#     permission-guarded Android call is never made; Chromium treats false as 'lock not available')
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)

p = "chrome/android/java/AndroidManifest.xml"
MARK = "    <!-- Iris: manifest hardened (patches/apply-android-manifest-harden.sh) -->\n"
DELETE = [
 '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n',
 '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n',
 '    <uses-permission-sdk-23 android:name="android.permission.ACCESS_ADSERVICES_ATTRIBUTION" />\n',
 '    <uses-permission-sdk-23 android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>\n',
 '    <uses-permission-sdk-23 android:name="android.permission.BLUETOOTH_CONNECT"/>\n',
 '    <!--\n'
 '      Bluetooth advertising is used by Phone as a Security Key to allow\n'
 '      a desktop device to prove proximity by receiving a BLE advert from the\n'
 '      phone.\n'
 '    -->\n'
 '    <uses-permission-sdk-23 android:name="android.permission.BLUETOOTH_ADVERTISE"/>\n',
 '    <!--\n'
 '      The BLUETOOTH permission is needed for\n'
 '      BluetoothAdapter.ACTION_REQUEST_ENABLE which at least Phone as a Security\n'
 '      Key uses.\n'
 '    -->\n'
 '    <uses-permission-sdk-23 android:name="android.permission.BLUETOOTH"/>\n',
 '    <!--\n'
 '      Bluetooth scanning is used to implement the Web Bluetooth API, which is\n'
 '      not intended to allow sites to derive location and so can accept a\n'
 '      filtered view of devices.\n'
 '    -->\n'
 '    <uses-permission-sdk-23 android:name="android.permission.BLUETOOTH_SCAN"\n'
 '                            android:usesPermissionFlags="neverForLocation"/>\n',
 '    <uses-permission-sdk-23 android:name="android.permission.READ_CONTACTS" android:maxSdkVersion="36"/>\n',
 '    <!--  Needed for allowing downloaded APKs to be installed. -->\n'
 '    <uses-permission-sdk-23 android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n',
 '    <uses-permission android:name="android.permission.GET_ACCOUNTS"/>\n',
 '    <uses-permission android:name="android.permission.MANAGE_ACCOUNTS"/>\n',
 '    <uses-permission android:name="android.permission.NFC"/>\n',
 '    <!-- Needed to determine whether an app installed on the device should handle a web navigation.  -->\n'
 '    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />\n',
 '    <uses-permission android:name="android.permission.USE_CREDENTIALS"/>\n',
 '    <!-- Permission for reading the Advanced Protection Mode status. -->\n'
 '    <uses-permission android:name="android.permission.QUERY_ADVANCED_PROTECTION_MODE"/>\n',
 '    <!-- Permission for using android.hardware.hid.HidManager on Android 17+ -->\n'
 '    <uses-permission android:name="android.permission.ACCESS_HID"/>\n',
 '    <uses-permission android:name="{{ manifest_package }}.permission.C2D_MESSAGE" />\n',
 '    <uses-permission android:name="com.google.android.c2dm.permission.RECEIVE" />\n',
 '    <uses-permission android:name="com.google.android.apps.now.CURRENT_ACCOUNT_ACCESS" />\n',
 '    <!-- android.permission.ACCESS_FINE_LOCATION -->\n'
 '    <uses-feature android:name="android.hardware.location.gps" android:required="false" />\n',
 '        <!-- Phishing Protection related -->\n'
 '        <receiver android:name="org.chromium.chrome.browser.safe_browsing.PasswordProtectionBroadcastReceiver"\n'
 '        android:exported="true"\n'
 '        android:permission="com.google.android.gms.permission.INTERNAL_BROADCAST">\n'
 '            <intent-filter>\n'
 '                <action android:name="com.android.chrome.safe_browsing.LOGIN" />\n'
 '            </intent-filter>\n'
 '        </receiver>\n',
 '        <!-- GcmListenerService for messages from GCM. -->\n'
 '        <service android:name="org.chromium.chrome.browser.services.gcm.ChromeGcmListenerService"\n'
 '            android:exported="false" >\n'
 '            <intent-filter>\n'
 '                <action android:name="com.google.firebase.MESSAGING_EVENT" />\n'
 '            </intent-filter>\n'
 '        </service>\n'
 '        <service android:name="org.chromium.chrome.browser.services.gcm.GCMBackgroundService"\n'
 '            android:exported="false"/>\n'
 '        <service android:name="org.chromium.chrome.browser.services.gcm.InvalidationGcmUpstreamSender"\n'
 '            android:exported="false"/>\n',
 '        <property android:name="android.adservices.AD_SERVICES_CONFIG"\n'
 '            android:resource="@xml/ad_services_config" />\n',
 '      <!-- Cast support -->\n'
 '      <meta-data\n'
 '          android:name=\n'
 '          "com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"\n'
 '          android:value="org.chromium.components.media_router.caf.CastOptionsProvider"/>\n',
]
REMOVED = ["android.permission.ACCESS_COARSE_LOCATION", "android.permission.ACCESS_FINE_LOCATION",
           "android.permission.ACCESS_ADSERVICES_ATTRIBUTION", "android.permission.BLUETOOTH",
           "android.permission.BLUETOOTH_ADMIN", "android.permission.BLUETOOTH_CONNECT",
           "android.permission.BLUETOOTH_ADVERTISE", "android.permission.BLUETOOTH_SCAN",
           "android.permission.READ_CONTACTS", "android.permission.REQUEST_INSTALL_PACKAGES",
           "android.permission.GET_ACCOUNTS", "android.permission.MANAGE_ACCOUNTS", "android.permission.NFC",
           "android.permission.QUERY_ALL_PACKAGES", "android.permission.USE_CREDENTIALS",
           "android.permission.QUERY_ADVANCED_PROTECTION_MODE",
           "android.permission.ACCESS_HID", "com.google.android.c2dm.permission.RECEIVE",
           "com.google.android.apps.now.CURRENT_ACCOUNT_ACCESS"]
s = open(p).read()
if MARK in s:
    print("SKIP already applied: %s (manifest hardening)" % p)
else:
    for d in DELETE:
        if s.count(d) != 1: die("%s: block not found exactly once (drift?):\n%s" % (p, d))
        s = s.replace(d, "")
    anchor = "    {% block extra_uses_permissions %}\n"
    if s.count(anchor) != 1: die("%s: extra_uses_permissions block not found (drift?)" % p)
    block = MARK + "".join('    <uses-permission android:name="%s" tools:node="remove" />\n' % n for n in REMOVED) + "\n"
    s = s.replace(anchor, block + anchor)
    open(p, "w").write(s); print("OK   %s : %d blocks removed, %d permissions also stripped from libraries"
                                 % (p, len(DELETE), len(REMOVED)))

# Part 1b: local network (jegly) + AICore bind permission
MARK1B = "    <!-- Iris: no local network / loopback / AICore (apply-android-manifest-harden.sh) -->\n"
s = open(p).read()
if MARK1B in s:
    print("SKIP already applied: %s (local network)" % p)
else:
    for d in ('    <!-- Needed for allowing cross-app and cross-profile communication over the loopback interface. -->\n'
              '    <uses-permission android:name="android.permission.USE_LOOPBACK_INTERFACE"/>\n',
              '    <!-- Needed for checking local network connections on Android 17+. -->\n'
              '    <uses-permission android:name="android.permission.ACCESS_LOCAL_NETWORK"/>\n'):
        if s.count(d) != 1: die("%s: block not found exactly once (drift?):\n%s" % (p, d))
        s = s.replace(d, "")
    anchor = "    {% block extra_uses_permissions %}\n"
    if s.count(anchor) != 1: die("%s: extra_uses_permissions block not found (drift?)" % p)
    s = s.replace(anchor, MARK1B + "".join('    <uses-permission android:name="%s" tools:node="remove" />\n' % n for n in
        ("android.permission.ACCESS_LOCAL_NETWORK", "android.permission.USE_LOOPBACK_INTERFACE",
         "com.google.android.apps.aicore.service.BIND_SERVICE")) + "\n" + anchor)
    open(p, "w").write(s); print("OK   %s : local network, loopback and AICore permissions removed" % p)

# Part 2: Google library components (tools:node="remove" markers; the merger drops what libraries add)
MARK2 = "        <!-- Iris: Google library components removed (apply-android-manifest-harden.sh) -->\n"
s = open(p).read()
if MARK2 in s:
    print("SKIP already applied: %s (library components)" % p)
else:
    APP = [("receiver", "com.google.firebase.iid.FirebaseInstanceIdReceiver"),
           ("service", "com.google.firebase.messaging.FirebaseMessagingService"),
           ("service", "com.google.firebase.components.ComponentDiscoveryService"),
           ("service", "com.google.mlkit.common.internal.MlKitComponentDiscoveryService"),
           ("service", "com.google.android.datatransport.runtime.backends.TransportBackendDiscovery"),
           ("service", "com.google.android.datatransport.runtime.scheduling.jobscheduling.JobInfoSchedulerService"),
           ("receiver", "com.google.android.datatransport.runtime.scheduling.jobscheduling.AlarmManagerSchedulerBroadcastReceiver"),
           ("activity", "com.google.android.gms.common.api.GoogleApiActivity"),
           ("receiver", "com.google.android.gms.cast.framework.media.MediaIntentReceiver"),
           ("activity", "com.google.android.play.core.common.PlayCoreDialogWrapperActivity"),
           ("activity", "com.google.ar.core.InstallActivity"),
           ("meta-data", "com.google.ar.core.min_apk_version"),
           ("meta-data", "com.google.android.gms.cloudmessaging.FINISHED_AFTER_HANDLED"),
           ("uses-library", "android.ext.adservices")]
    anchor = ('            android:name="com.google.android.gms.cast.framework.ReconnectionService"\n'
              '            tools:node="remove" />\n')
    if s.count(anchor) != 1: die("%s: ReconnectionService removal anchor not found (drift?)" % p)
    blk = MARK2 + "".join('        <%s android:name="%s" tools:node="remove" />\n' % (t, n) for t, n in APP)
    s = s.replace(anchor, anchor + blk)
    open(p, "w").write(s); print("OK   %s : %d library components removed" % (p, len(APP)))
# Part 3: library <queries> entries (merger ignores tools:node there) -> filtered in the merge step
p = "build/android/gyp/merge_manifest.py"
s = open(p).read()
MARK3 = "_IRIS_DENIED_QUERY_PACKAGES"
if MARK3 in s:
    print("SKIP already applied: %s (library <queries>)" % p)
else:
    a1 = "_MANIFEST_MERGER_MAIN_CLASS = 'com.android.manifmerger.Merger'\n"
    a2 = ("    package_count = seen_package_names[package_name]\n")
    a3 = ("    if package_count > 0 or changed_api:\n")
    for a in (a1, a2, a3):
        if s.count(a) != 1: die("%s: anchor not found exactly once (drift?): %r" % (p, a))
    s = s.replace(a1, a1 + "\n# Iris: library <queries> entries for Google services that Iris never uses (Play services Cast,\n"
                  "# AICore, ARCore). The merger ignores tools:node on <queries>, so they are dropped here.\n"
                  "_IRIS_DENIED_QUERY_PACKAGES = {\n"
                  "    'com.google.android.aicore',\n"
                  "    'com.google.android.gms.policy_cast_dynamite',\n"
                  "    'com.google.ar.core',\n"
                  "}\n")
    s = s.replace(a2, "    iris_dropped = False  # Iris\n"
                  "    for queries in manifest.findall('queries'):\n"
                  "        for pkg in list(queries.findall('package')):\n"
                  "            if manifest_utils.NamespacedGet(pkg, 'name') in _IRIS_DENIED_QUERY_PACKAGES:\n"
                  "                queries.remove(pkg)\n"
                  "                iris_dropped = True\n\n" + a2)
    s = s.replace(a3, "    if package_count > 0 or changed_api or iris_dropped:  # Iris: + iris_dropped\n")
    open(p, "w").write(s); print("OK   %s : library <queries> for Play services Cast / AICore / ARCore dropped" % p)
# Part 4: leftovers
p = "chrome/android/java/AndroidManifest.xml"
MARK4 = "    <!-- Iris: leftovers removed (apply-android-manifest-harden.sh part 4) -->\n"
s = open(p).read()
if MARK4 in s:
    print("SKIP already applied: %s (leftovers)" % p)
else:
    REPL = [
     ('    <uses-permission android:name="android.permission.CAPTURE_KEYBOARD" />\n', ''),
     ('    {% if enable_screen_capture == "true" %}\n'
      '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />\n'
      '    {% endif %}\n', ''),
     ('    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n', ''),
     ('            {% block supports_vr %}\n'
      '            <intent-filter>\n'
      '                <action android:name="org.chromium.chrome.browser.dummy.action" />\n'
      '                <category android:name="com.google.intent.category.DAYDREAM" />\n'
      '                <category android:name="com.google.intent.category.CARDBOARD" />\n'
      '            </intent-filter>\n'
      '            {% endblock %}\n',
      '            {% block supports_vr %}\n            {% endblock %}\n'),
     ("        {% if channel in ['default'] %}\n"
      '        <service android:name="org.chromium.chrome.browser.actor.ActorForegroundService"\n'
      '            android:foregroundServiceType="dataSync"\n'
      '            android:exported="true"\n'
      '            tools:ignore="ExportedService">\n'
      '            <intent-filter>\n'
      '                <action android:name="org.chromium.chrome.browser.actor.START_ACTOR_FOREGROUND_SERVICE" />\n'
      '            </intent-filter>\n'
      '        </service>\n'
      '        {% else %}\n'
      '        <service android:name="org.chromium.chrome.browser.actor.ActorForegroundService"\n'
      '            android:foregroundServiceType="dataSync"\n'
      '            android:exported="false">\n'
      '        </service>\n'
      '        {% endif %}\n',
      '        <service android:name="org.chromium.chrome.browser.actor.ActorForegroundService"\n'
      '            android:foregroundServiceType="dataSync"\n'
      '            android:exported="false">\n'
      '        </service>\n'),
     ('        <!-- Service used by payment apps to notify the browser about changes in user selected\n'
      '             payment method, shipping address, or shipping option. -->\n'
      '        <service\n'
      '            android:name="org.chromium.components.payments.PaymentDetailsUpdateService"\n'
      '            android:exported="true"\n'
      '            tools:ignore="ExportedService">\n'
      '            <intent-filter>\n'
      '              <action android:name="org.chromium.intent.action.UPDATE_PAYMENT_DETAILS" />\n'
      '            </intent-filter>\n'
      '        </service>\n', ''),
     ('            {% if enable_screen_capture == "true" %}\n'
      '            android:foregroundServiceType="camera|microphone|mediaProjection|mediaPlayback"\n'
      '            {% else %}\n'
      '            android:foregroundServiceType="camera|microphone"\n'
      '            {% endif %}\n',
      '            android:foregroundServiceType="camera|microphone"\n'),
    ]
    for old, new in REPL:
        if s.count(old) != 1: die("%s: leftover block not found exactly once (drift?):\n%s" % (p, old))
        s = s.replace(old, new)
    anchor = "    {% block extra_uses_permissions %}\n"
    if s.count(anchor) != 1: die("%s: extra_uses_permissions block not found (drift?)" % p)
    s = s.replace(anchor, MARK4 + "".join('    <uses-permission android:name="%s" tools:node="remove" />\n' % n for n in
        ("android.permission.CAPTURE_KEYBOARD", "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
         "android.permission.RECEIVE_BOOT_COMPLETED")) + "\n" + anchor)
    a2 = "        <!-- Iris: Google library components removed (apply-android-manifest-harden.sh) -->\n"
    if s.count(a2) != 1: die("%s: part 2 marker missing (run order?)" % p)
    s = s.replace(a2, a2 +
        '        <activity android:name="org.chromium.chrome.browser.media.immersive_playback.ImmersiveVideoPlaybackActivity" tools:node="remove" />\n'
        '        <uses-library android:name="com.android.extensions.xr" tools:node="remove" />\n')
    open(p, "w").write(s); print("OK   %s : leftovers removed (actor export, payments service, VR/XR, 3 permissions)" % p)

# Keyboard Lock: never make the CAPTURE_KEYBOARD-guarded Android call
p = "ui/android/java/src/org/chromium/ui/base/WindowAndroid.java"
s = open(p).read()
M = "        if (IRIS_NO_KEYBOARD_CAPTURE) return false; // Iris: no CAPTURE_KEYBOARD permission\n"
old = "    private boolean setHasKeyboardCapture(boolean hasCapture) {\n"
if M in s: print("SKIP already applied: %s (keyboard capture)" % p)
else:
    if s.count(old) != 1: die("%s: setHasKeyboardCapture not found exactly once (drift?)" % p)
    s = s.replace(old, old + M)
    i = s.rstrip().rfind("}")
    s = s[:i] + "\n    private static final boolean IRIS_NO_KEYBOARD_CAPTURE = true; // Iris\n" + s[i:]
    open(p, "w").write(s); print("OK   %s : keyboard capture off" % p)
PY
