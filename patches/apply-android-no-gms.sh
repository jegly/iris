#!/usr/bin/env bash
# Iris — Android: never use Google Play services (decided 2026-10-01; jegly delegated the call).
# chrome://version showed "Google Play services: ... Access=3p": Play services is on the phone and Chromium may
# call it (sign-in, passkeys via the GMS FIDO API, Cast, Shape Detection, WebOTP, fused location).
# 1) org.chromium.gms.ChromiumPlayServicesAvailability is the single availability check behind ExternalAuthUtils
#    (every canUseGooglePlayServices() caller: sign-in, Fido2ApiCallHelper, version page...), LocationProviderGmsCore
#    and the Shape Detection providers -> always "missing" (Chromium then behaves as on a phone without Play
#    services). The test override still wins so upstream tests keep working.
# 2) ExternalAuthUtils.isUserRecoverableError() -> false, so no "install/update Google Play services" prompt
#    is ever shown for that "missing".
# 3) Cast (BrowserMediaRouter) asks GoogleApiAvailability directly -> no Cast providers.
# 4) WebOTP's SMS backend (SmsProviderGms) asks GoogleApiAvailability directly -> verification backend off
#    (WebOTP is also disabled as a Blink feature by apply-default-switches.sh).
# 6) Push/FCM: GCMDriver.register() and InstanceIDBridge.getToken() call Play services directly (no availability
#    check) -> both return the existing failure value ("") before contacting Google. (Desktop: apply-gcm-off.sh.)
# Cost: Cast and Play-services passkeys/security keys don't work in Iris.
# chrome://version (Android) also loses the device model/build number and the Play services row (local-only info,
# but people share screenshots of that page); the Android version + SDK level stay.
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

# 1) the central availability check
p = "third_party/android_deps/util/org/chromium/gms/ChromiumPlayServicesAvailability.java"
C = ("    /** Iris: Google Play services is never used (see Iris patches/apply-android-no-gms.sh). */\n"
     "    public static final boolean IRIS_GMS_OFF = true;\n\n")
edit(p, "    private static @Nullable Boolean sIsAvailableForTesting;\n",
     C + "    private static @Nullable Boolean sIsAvailableForTesting;\n", C, "IRIS_GMS_OFF constant")
edit(p, "            return sIsAvailableForTesting;\n        }\n",
     "            return sIsAvailableForTesting;\n        }\n"
     "        if (IRIS_GMS_OFF) return false; // Iris\n",
     "        if (IRIS_GMS_OFF) return false; // Iris\n", "isGooglePlayServicesAvailable -> false")
edit(p, "ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED;\n        }\n",
     "ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED;\n        }\n"
     "        if (IRIS_GMS_OFF) return ConnectionResult.SERVICE_MISSING; // Iris\n",
     "        if (IRIS_GMS_OFF) return ConnectionResult.SERVICE_MISSING; // Iris\n",
     "getGooglePlayServicesConnectionResult -> SERVICE_MISSING")

# 2) no install/update prompts
p = "components/externalauth/android/java/src/org/chromium/components/externalauth/ExternalAuthUtils.java"
M = "        if (ChromiumPlayServicesAvailability.IRIS_GMS_OFF) return false; // Iris: never prompt\n"
edit(p, "    protected boolean isUserRecoverableError(final int errorCode) {\n",
     "    protected boolean isUserRecoverableError(final int errorCode) {\n" + M, M, "no Play services prompts")

# 3) Cast
p = "components/media_router/browser/android/java/src/org/chromium/components/media_router/BrowserMediaRouter.java"
M = "                    if (IRIS_NO_CAST) return; // Iris: Cast needs Google Play services\n"
edit(p, "    private static final int MIN_GOOGLE_PLAY_SERVICES_APK_VERSION = 12600000;\n",
     "    private static final int MIN_GOOGLE_PLAY_SERVICES_APK_VERSION = 12600000;\n"
     "    private static final boolean IRIS_NO_CAST = true; // Iris\n",
     "IRIS_NO_CAST = true", "IRIS_NO_CAST constant")
edit(p, "                public void addProviders(MediaRouteManager manager) {\n",
     "                public void addProviders(MediaRouteManager manager) {\n" + M, M, "no Cast providers")

# 4) WebOTP SMS backend: Iris's switch is checked FIRST, so Play services is never even asked
p = "content/public/android/java/src/org/chromium/content/browser/sms/SmsProviderGms.java"
edit(p, "    @CalledByNative\n    private static SmsProviderGms create(",
     "    private static final boolean IRIS_GMS_OFF = true; // Iris\n\n"
     "    @CalledByNative\n    private static SmsProviderGms create(",
     "IRIS_GMS_OFF = true; // Iris\n", "IRIS_GMS_OFF constant")
s_ = open(p).read()
OLD_IRIS = ("                        == ConnectionResult.SUCCESS\n"
            "                && !IRIS_GMS_OFF; // Iris: no Google Play services\n")   # earlier Iris form
if OLD_IRIS in s_: s_ = s_.replace(OLD_IRIS, "                        == ConnectionResult.SUCCESS;\n")
FIRST = "                !IRIS_GMS_OFF // Iris: never ask Google Play services\n                        && "
UP = "        boolean isVerificationBackendAvailable =\n                GoogleApiAvailability"
if FIRST in s_: print("SKIP already applied: %s (verification backend off)" % p)
elif s_.count(UP) != 1: die("%s: SMS availability check not found exactly once (drift?)" % p)
else:
    s_ = s_.replace(UP, "        boolean isVerificationBackendAvailable =\n" + FIRST + "GoogleApiAvailability")
    open(p, "w").write(s_); print("OK   %s : verification backend off (checked before Play services)" % p)

# 5) chrome://version: no device model/build, no Play services row
p = "chrome/browser/ui/webui/version/version_ui.cc"
edit(p, "  std::string os_info = AndroidAboutAppInfo::GetOsInfo();\n",
     "  // Iris: Android version only (no device model / build number).\n"
     "  std::string os_info = base::SysInfo::OperatingSystemVersion();\n",
     "  // Iris: Android version only", "OS row without device model")
G = ("  html_source->AddString(version_ui::kGmsVersion,\n"
     "                         AndroidAboutAppInfo::GetGmsInfo());\n")
s = open(p).read()
if G not in s: print("SKIP already applied: %s (drop Play services value)" % p)
elif s.count(G) != 1: die("%s: Play services value not found exactly once (drift?)" % p)
else: open(p, "w").write(s.replace(G, "")); print("OK   %s : drop Play services value" % p)
s = open(p).read()
if "#include \"base/system/sys_info.h\"" not in s:
    edit(p, '#include "build/build_config.h"\n',
         '#include "base/system/sys_info.h"  // Iris\n#include "build/build_config.h"\n',
         '#include "base/system/sys_info.h"', "include sys_info")
p = "components/webui/version/resources/about_version.html"
old = ("        <tr>\n"
       "          <td class=\"label\">$i18n{gms_name}</td>\n"
       "          <td class=\"version\" id=\"gms_version\">\n"
       "            <span>$i18n{gms_version}</span>\n"
       "          </td>\n"
       "        </tr>\n")
s = open(p).read()
if "$i18n{gms_version}" not in s: print("SKIP already applied: %s (Play services row)" % p)
elif s.count(old) != 1: die("%s: Play services row not found exactly once (drift?)" % p)
else: open(p, "w").write(s.replace(old, "")); print("OK   %s : Play services row removed" % p)
# 6) Push / FCM (Android's GCM goes straight to Play services; apply-gcm-off.sh is desktop-only)
def add_const(p, line, label):
    s = open(p).read()
    if line in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    i = s.rstrip().rfind("}")
    if i < 0 or not s.rstrip().endswith("}"): die("%s: class end not found (drift?)" % p)
    open(p, "w").write(s[:i] + "\n" + line + s[i:]); print("OK   %s : %s" % (p, label))
C = "    private static final boolean IRIS_NO_FCM = true; // Iris: no Google push (FCM)\n"
p = "components/gcm_driver/android/java/src/org/chromium/components/gcm_driver/GCMDriver.java"
M = "                    if (IRIS_NO_FCM) return \"\"; // Iris: never subscribe with Google (FCM)\n"
edit(p, "                    String subtype = appId;\n"
        "                    String registrationId = mSubscriber.subscribe(senderId, subtype, null);\n",
     M + "                    String subtype = appId;\n"
         "                    String registrationId = mSubscriber.subscribe(senderId, subtype, null);\n",
     M, "no FCM registration")
add_const(p, C, "IRIS_NO_FCM constant")
p = "components/gcm_driver/instance_id/android/java/src/org/chromium/components/gcm_driver/instance_id/InstanceIDBridge.java"
M = "                    if (IRIS_NO_FCM) return \"\"; // Iris: never ask Google for a push token (FCM)\n"
edit(p, "                    return mInstanceID.getToken(authorizedEntity, scope);\n",
     M + "                    return mInstanceID.getToken(authorizedEntity, scope);\n", M, "no FCM token")
add_const(p, C, "IRIS_NO_FCM constant")
PY
