#!/usr/bin/env bash
# Iris — Android app lock (jegly 2026-10-02: real encryption like desktop; lock on start AND after 5 min in the
# background; passphrase + optional fingerprint). Verified against this checkout.
# Same native app lock as desktop (apply-app-lock.sh: chrome/browser/iris/iris_app_lock.* + iris_key_provider.*,
# registered for every platform in browser_process_impl.cc). Android-specific, in those shared files (patches/src):
#   - iris_app_lock::RunWhenUnlocked(): IrisKeyProvider::GetKey() waits for the unlock instead of answering
#     "unavailable" (the Android browser starts before the user unlocks), and UseForEncryption() is true whenever
#     the lock is ON — so nothing is written unencrypted while waiting. Desktop unlocks first: unchanged there.
#     (Cookies on Android go through the same os_crypt_async path: profile_network_context_service.cc has no
#     Android guard; without the lock Android only has PosixKeyProvider's fixed key.)
# New here (patches/src):
#   chrome/android/java/.../iris/IrisAppLock.java          state, 5-min re-lock, Keystore fingerprint, JNI
#   chrome/android/java/.../iris/IrisUnlockActivity.java   "Iris is locked" screen (FLAG_SECURE, Back = background)
#   chrome/android/java/.../iris/IrisAppLockSettings.java  set / change / fingerprint / turn off dialogs
#   chrome/browser/iris/iris_app_lock_android.cc         JNI -> iris_app_lock (built in chrome/browser:core)
# Wiring: chrome_java_sources.gni, chrome_jni_headers (chrome/android/BUILD.gn), chrome/browser/BUILD.gn (core),
# the activity in AndroidManifest.xml, ChromeBaseAppCompatActivity.onResume() -> IrisAppLock.maybeShowLock(), and a
# "Lock Iris" row in Settings > Privacy and security > Iris (needs apply-android-iris-privacy-settings.sh).
# English-only labels. Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
PSRC="$(cd "$(dirname "$0")" && pwd)/src"
cd "$SRC"
for f in chrome/android/java/src/org/chromium/chrome/browser/iris/IrisAppLock.java \
         chrome/android/java/src/org/chromium/chrome/browser/iris/IrisUnlockActivity.java \
         chrome/android/java/src/org/chromium/chrome/browser/iris/IrisAppLockSettings.java \
         chrome/browser/iris/iris_app_lock_android.cc; do
  [ -f "$PSRC/$f" ] || { echo "ERROR: missing $PSRC/$f" >&2; exit 1; }
  mkdir -p "$(dirname "$f")"
  if cmp -s "$PSRC/$f" "$f"; then echo "SKIP already applied: $f"; else cp "$PSRC/$f" "$f"; echo "OK   $f : copied"; fi
done
old="chrome/browser/android/iris/iris_app_lock_android.cc"  # first version's location
if [ -f "$old" ]; then
  [ "$(sha256sum "$old" | cut -d" " -f1)" = "4325c2e85c973f8debc8bec96094995ca845eebd81d4c33732e0513d74425c03" ] \
    || { echo "ERROR: $old is not the first Iris version; not removing" >&2; exit 1; }
  rm "$old"; rmdir --ignore-fail-on-non-empty "$(dirname "$old")"; echo "OK   $old : moved to chrome/browser/iris/iris_app_lock_android.cc"
fi
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

J = "java/src/org/chromium/chrome/browser/iris/"
a = '  "java/src/org/chromium/chrome/browser/ChromeBaseAppCompatActivity.java",\n'
edit("chrome/android/chrome_java_sources.gni", a,
     a + "".join('  "%s%s",  # Iris\n' % (J, n) for n in
                 ("IrisAppLock.java", "IrisAppLockSettings.java", "IrisUnlockActivity.java")),
     '"%sIrisAppLock.java",  # Iris' % J, "java sources")
edit("chrome/android/BUILD.gn", '  generate_jni("chrome_jni_headers") {\n    sources = [\n',
     '  generate_jni("chrome_jni_headers") {\n    sources = [\n      "%sIrisAppLock.java",  # Iris\n' % J,
     '"%sIrisAppLock.java",  # Iris' % J, "JNI header")
# Listed in chrome/browser:core (not chrome/browser/android, which core depends on: gn check would
# reject the iris/ includes). Undo the first version, which registered it in chrome/browser/android.
s = open("chrome/browser/android/BUILD.gn").read()
old = '      "iris/iris_app_lock_android.cc",  # Iris\n'
if old in s:
    open("chrome/browser/android/BUILD.gn", "w").write(s.replace(old, "", 1))
    print("OK   chrome/browser/android/BUILD.gn : old JNI source entry removed")
edit("chrome/browser/BUILD.gn", '      "after_startup_task_utils_android.cc",\n',
     '      "iris/iris_app_lock_android.cc",  # Iris\n      "after_startup_task_utils_android.cc",\n',
     '"iris/iris_app_lock_android.cc",  # Iris', "JNI source")

p = "chrome/android/java/AndroidManifest.xml"
a = ('            android:name="com.google.android.gms.cast.framework.ReconnectionService"\n'
     '            tools:node="remove" />\n')
edit(p, a, a + ('        <!-- Iris: app lock screen (apply-android-app-lock.sh) -->\n'
                '        <activity android:name="org.chromium.chrome.browser.iris.IrisUnlockActivity"\n'
                '            android:theme="@android:style/Theme.DeviceDefault.NoActionBar"\n'
                '            android:excludeFromRecents="true"\n'
                '            android:exported="false" />\n'),
     'org.chromium.chrome.browser.iris.IrisUnlockActivity', "unlock activity")

p = "chrome/android/java/src/org/chromium/chrome/browser/ChromeBaseAppCompatActivity.java"
a = "    protected void applyThemeOverlays() {\n"
edit(p, a, ("    @Override\n"
            "    protected void onResume() {\n"
            "        super.onResume();\n"
            "        org.chromium.chrome.browser.iris.IrisAppLock.maybeShowLock(this); // Iris: app lock\n"
            "    }\n\n") + a,
     "IrisAppLock.maybeShowLock(this); // Iris: app lock", "lock on resume")

p = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
a = "        getPreferenceScreen().addPreference(irisCategory);\n"
s = open(p).read()
if a not in s: die("%s: Iris section missing (run apply-android-iris-privacy-settings.sh first)" % p)
edit(p, a, a + ('        // Iris: "Lock Iris" (app lock: passphrase, optional fingerprint).\n'
                '        androidx.preference.Preference irisLock =\n'
                '                new androidx.preference.Preference(getPreferenceManager().getContext());\n'
                '        irisLock.setKey("iris_app_lock");\n'
                '        irisLock.setPersistent(false);\n'
                '        irisLock.setTitle("Lock Iris");\n'
                '        irisLock.setSummary(org.chromium.chrome.browser.iris.IrisAppLockSettings.summary());\n'
                '        irisLock.setOnPreferenceClickListener(\n'
                '                preference -> {\n'
                '                    android.app.Activity activity = getActivity();\n'
                '                    if (activity != null) {\n'
                '                        org.chromium.chrome.browser.iris.IrisAppLockSettings.show(\n'
                '                                activity,\n'
                '                                () ->\n'
                '                                        preference.setSummary(\n'
                '                                                org.chromium.chrome.browser.iris\n'
                '                                                        .IrisAppLockSettings.summary()));\n'
                '                    }\n'
                '                    return true;\n'
                '                });\n'
                '        irisCategory.addPreference(irisLock);\n'),
     '// Iris: "Lock Iris"', "Lock Iris row")
PY
