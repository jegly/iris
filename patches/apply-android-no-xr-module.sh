#!/usr/bin/env bash
# Iris — Android: drop the "xr" feature module (Android XR headsets + ARCore) from the APK (jegly 2026-10-04;
# verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# Before: chrome/android/modules/chrome_feature_modules.gni lists xr_module_desc unconditionally (enable_vr /
# enable_arcore / enable_openxr = false do NOT cover it). In an APK build (chrome_public_apk_tmpl.gni) every module's
# java_deps + loadable_modules go into the base APK, so release -3 shipped ~20 MB that never runs on a phone:
#   libimpress_api_jni.so (18.6 MB, Google's Android-XR renderer), libandroidx.xr.arcore.openxr.so,
#   libandroidx.xr.runtime.openxr.so, libarcore_sdk_c.so, libarcore_sdk_jni.so, plus the androidx.xr / ARCore / impress
#   Java (thousands of classes in classes.dex) and the immersive-video activity.
# After: the module is not in the list -> none of that is built into the APK.
# Java that still names the module (base APK, chrome/android:xr_java) only runs on Android XR headsets
# (DeviceInfo.isXr()); XrModule.isInstalled() now returns false (ModuleEngine: impl class not found). Defensive guards
# so even an XR headset doesn't crash: ChromeTabbedActivity skips the XR session code unless the module is there, and
# XrModuleBridge (called from native for immersive video) does nothing without it.
# Manifest: apply-android-manifest-harden.sh's tools:node="remove" lines for the immersive activity / XR library
# become no-ops (allowed by the manifest merger).
# STATUS 2026-10-04: copy-tested only, NOT compile-proven. Prove: gn gen out/Android, chrome_java (javac), then check
#   the APK: `unzip -l ChromePublic.apk 'lib/*'` lists only libchrome.so + the 2 small Chromium helper libs.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label, count=1):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != count: die("%s: anchor for %s found %d times, expected %d (drift?)" % (p, label, s.count(old), count))
    open(p, "w").write(s.replace(old, new)); print("OK   %s : %s" % (p, label))

edit("chrome/android/modules/chrome_feature_modules.gni",
     "chrome_module_descs = [\n"
     "  on_demand_module_desc,\n"
     "  stack_unwinder_module_desc,\n"
     "  xr_module_desc,\n"
     "]\n",
     "# Iris: no xr_module_desc (Android XR + ARCore; ~20 MB of native libs a phone never uses).\n"
     "# xr_module.gni stays imported (an unused import is fine in gn, like buildflags.gni above).\n"
     "chrome_module_descs = [\n"
     "  on_demand_module_desc,\n"
     "  stack_unwinder_module_desc,\n"
     "]\n",
     "# Iris: no xr_module_desc", "xr module removed from chrome_module_descs")

p = "chrome/android/java/src/org/chromium/chrome/browser/ChromeTabbedActivity.java"
s = open(p).read()
GUARD = "DeviceInfo.isXr() && XrModule.isInstalled() /* Iris: no XR module */"
if GUARD in s:
    print("SKIP already applied: %s (XR guards)" % p)
else:
    a1 = ("        if (DeviceInfo.isXr()) {\n"
          "            assert XrModule.isInstalled() : \"XR module must be installed on XR devices. \";\n"
          "            mXrSceneCoreSessionInitializer =\n")
    a2 = ("            if (DeviceInfo.isXr()) {\n"
          "                assert XrModule.isInstalled() : \"XR module must be installed on XR devices. \";\n"
          "                xrSceneCoreSessionManager = XrModule.getImpl().getXrSceneCoreSessionManager(this);\n")
    for a, what in ((a1, "maybeInitializeXrSceneCoreSession"), (a2, "createXrSceneCoreSessionManager")):
        if s.count(a) != 1: die("%s: %s XR block not found exactly once (drift?)" % (p, what))
    if s.count("XrModule.getImpl()") != 2:
        die("%s: expected exactly 2 XrModule.getImpl() calls (found %d) - a new XR call site needs a guard"
            % (p, s.count("XrModule.getImpl()")))
    s = s.replace(a1, a1.replace("DeviceInfo.isXr()", GUARD, 1), 1)
    s = s.replace(a2, a2.replace("DeviceInfo.isXr()", GUARD, 1), 1)
    open(p, "w").write(s); print("OK   %s : XR session code only with the XR module present" % p)

edit("chrome/android/java/src/org/chromium/chrome/browser/xr/scenecore/XrModuleBridge.java",
     "            UnguessableToken nativeToken, Object initiatorTab) {\n"
     "        XrModule.getImpl().createImmersiveVideoPlaybackActivity(nativeToken, initiatorTab);\n",
     "            UnguessableToken nativeToken, Object initiatorTab) {\n"
     "        if (!XrModule.isInstalled()) return; // Iris: no XR module in the APK\n"
     "        XrModule.getImpl().createImmersiveVideoPlaybackActivity(nativeToken, initiatorTab);\n",
     "// Iris: no XR module in the APK", "immersive video: no-op without the XR module")
PY
echo "=== Android XR module removal complete ==="
