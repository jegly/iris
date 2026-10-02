#!/usr/bin/env bash
# Iris — Android per-site settings (jegly 2026-10-02 "get that all done now"). Verified against this checkout.
# Desktop has these per site (Page Info / Settings > Site settings > a site). Android Page Info only lists a permission
# once the site already has its own value, so the controls live in the site's own settings page instead (Page Info ->
# Site settings -> the site; SingleWebsiteSettings), in an "Iris" section:
#   - WebGL (3D graphics)          switch  ContentSettingsType.IRIS_WEBGL (default BLOCK; global switch in Privacy)
#   - Google sign-in prompts       switch  ContentSettingsType.IRIS_GOOGLE_SIGNIN (default BLOCK)
#   - Browser identity             list    iris::Get/SetUserAgentPreset ("" Iris, firefox_linux, chrome_windows,
#                                          safari_mac) — same website setting as desktop
#   - Canvas and audio reading     list    iris::Get/SetFingerprintReadsPreset (protected, blank, real)
# The switches use the site-settings component's own per-site bridge. The lists need Chrome code, so they go through
# SiteSettingsDelegate (new default methods returning null = not supported, so WebView etc. are unchanged), which
# ChromeSiteSettingsDelegate implements via a small JNI bridge (IrisSiteSettings, chrome/browser/iris/
# iris_site_settings_android.cc, built in chrome/browser:core).
# "Forget this site" is not ported: on desktop it is "delete when Iris closes" (SESSION_ONLY), which has no clear
# moment on Android; Android Page Info already has "Delete data" for a site, and automatic deletion is in Privacy.
# English-only labels (desktop wording). Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
PSRC="$(cd "$(dirname "$0")" && pwd)/src"
cd "$SRC"
for f in chrome/android/java/src/org/chromium/chrome/browser/iris/IrisSiteSettings.java \
         chrome/browser/iris/iris_site_settings_android.cc; do
  [ -f "$PSRC/$f" ] || { echo "ERROR: missing $PSRC/$f" >&2; exit 1; }
  mkdir -p "$(dirname "$f")"
  if cmp -s "$PSRC/$f" "$f"; then echo "SKIP already applied: $f"; else cp "$PSRC/$f" "$f"; echo "OK   $f : copied"; fi
done
old="chrome/browser/android/iris/iris_site_settings_android.cc"  # first version's location
if [ -f "$old" ]; then
  [ "$(sha256sum "$old" | cut -d" " -f1)" = "451c037dd5c1ec8303c5aee52c637f13fb2f0f1578ec646027580280db5d388b" ] \
    || { echo "ERROR: $old is not the first Iris version; not removing" >&2; exit 1; }
  rm "$old"; rmdir --ignore-fail-on-non-empty "$(dirname "$old")"; echo "OK   $old : moved to chrome/browser/iris/iris_site_settings_android.cc"
fi
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
def add_at_end(p, block, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    t = s.rstrip()
    if not t.endswith("}"): die("%s: class end not found (drift?)" % p)
    i = t.rfind("}")
    open(p, "w").write(s[:i] + block + s[i:]); print("OK   %s : %s" % (p, label))

J = "java/src/org/chromium/chrome/browser/iris/IrisSiteSettings.java"
a = '  "java/src/org/chromium/chrome/browser/ChromeBaseAppCompatActivity.java",\n'
edit("chrome/android/chrome_java_sources.gni", a, a + '  "%s",  # Iris\n' % J, '"%s",  # Iris' % J, "java source")
edit("chrome/android/BUILD.gn", '  generate_jni("chrome_jni_headers") {\n    sources = [\n',
     '  generate_jni("chrome_jni_headers") {\n    sources = [\n      "%s",  # Iris\n' % J,
     '"%s",  # Iris' % J, "JNI header")
# Listed in chrome/browser:core (not chrome/browser/android, which core depends on: gn check would
# reject the iris/ includes). Undo the first version, which registered it in chrome/browser/android.
s = open("chrome/browser/android/BUILD.gn").read()
old = '      "iris/iris_site_settings_android.cc",  # Iris\n'
if old in s:
    open("chrome/browser/android/BUILD.gn", "w").write(s.replace(old, "", 1))
    print("OK   chrome/browser/android/BUILD.gn : old JNI source entry removed")
edit("chrome/browser/BUILD.gn", '      "after_startup_task_utils_android.cc",\n',
     '      "iris/iris_site_settings_android.cc",  # Iris\n      "after_startup_task_utils_android.cc",\n',
     '"iris/iris_site_settings_android.cc",  # Iris', "JNI source")

D = "components/browser_ui/site_settings/android/java/src/org/chromium/components/browser_ui/site_settings/"
add_at_end(D + "SiteSettingsDelegate.java",
    "\n    // Iris: per-site browser identity and canvas/audio reading (null = not supported here).\n"
    "    default @Nullable String getIrisUserAgentPreset(String origin) {\n        return null;\n    }\n\n"
    "    default void setIrisUserAgentPreset(String origin, String preset) {}\n\n"
    "    default @Nullable String getIrisFingerprintReadsPreset(String origin) {\n        return null;\n    }\n\n"
    "    default void setIrisFingerprintReadsPreset(String origin, String preset) {}\n",
    "getIrisUserAgentPreset(String origin)", "delegate methods")

add_at_end("chrome/android/java/src/org/chromium/chrome/browser/site_settings/ChromeSiteSettingsDelegate.java",
    "\n    // Iris: per-site browser identity and canvas/audio reading (IrisSiteSettings JNI).\n"
    "    @Override\n    public @Nullable String getIrisUserAgentPreset(String origin) {\n"
    "        return org.chromium.chrome.browser.iris.IrisSiteSettings.getUserAgentPreset(mProfile, origin);\n    }\n\n"
    "    @Override\n    public void setIrisUserAgentPreset(String origin, String preset) {\n"
    "        org.chromium.chrome.browser.iris.IrisSiteSettings.setUserAgentPreset(mProfile, origin, preset);\n    }\n\n"
    "    @Override\n    public @Nullable String getIrisFingerprintReadsPreset(String origin) {\n"
    "        return org.chromium.chrome.browser.iris.IrisSiteSettings.getFingerprintReadsPreset(\n"
    "                mProfile, origin);\n    }\n\n"
    "    @Override\n    public void setIrisFingerprintReadsPreset(String origin, String preset) {\n"
    "        org.chromium.chrome.browser.iris.IrisSiteSettings.setFingerprintReadsPreset(\n"
    "                mProfile, origin, preset);\n    }\n",
    "public @Nullable String getIrisUserAgentPreset(String origin)", "Chrome delegate")

p = D + "SingleWebsiteSettings.java"
edit(p, "        setUpRelatedSitesPreferences();\n",
     "        setUpRelatedSitesPreferences();\n        setUpIrisPreferences(); // Iris\n",
     "setUpIrisPreferences(); // Iris", "call")
add_at_end(p, r'''
    // Iris: per-site WebGL, Google sign-in prompts, browser identity and canvas/audio reading.
    private void setUpIrisPreferences() {
        String origin = mSite.getAddress().getOrigin();
        SiteSettingsDelegate delegate = getSiteSettingsDelegate();
        String identity = delegate.getIrisUserAgentPreset(origin);
        String reading = delegate.getIrisFingerprintReadsPreset(origin);
        if (identity == null || reading == null) return; // not Iris (e.g. WebView)
        android.content.Context context = getPreferenceManager().getContext();
        PreferenceCategory category = new PreferenceCategory(context);
        category.setKey("iris_site_section");
        category.setTitle("Iris");
        getPreferenceScreen().addPreference(category);
        org.chromium.url.GURL url = new org.chromium.url.GURL(origin);
        category.addPreference(
                irisSwitch(
                        context,
                        "iris_site_webgl",
                        "WebGL (3D graphics)",
                        ContentSettingsType.IRIS_WEBGL,
                        url));
        category.addPreference(
                irisSwitch(
                        context,
                        "iris_site_google_signin",
                        "Google sign-in prompts",
                        ContentSettingsType.IRIS_GOOGLE_SIGNIN,
                        url));
        category.addPreference(
                irisList(
                        context,
                        "iris_site_identity",
                        "Browser identity",
                        new String[] {
                            "Iris (default)", "Firefox on Linux", "Chrome on Windows", "Safari on macOS"
                        },
                        new String[] {"", "firefox_linux", "chrome_windows", "safari_mac"},
                        identity,
                        value -> delegate.setIrisUserAgentPreset(origin, value)));
        category.addPreference(
                irisList(
                        context,
                        "iris_site_reading",
                        "Canvas and audio reading",
                        new String[] {"Protected (default)", "Blank", "Real data"},
                        new String[] {"protected", "blank", "real"},
                        reading,
                        value -> delegate.setIrisFingerprintReadsPreset(origin, value)));
    }

    private ChromeSwitchPreference irisSwitch(
            android.content.Context context,
            String key,
            String title,
            @ContentSettingsType.EnumType int type,
            org.chromium.url.GURL url) {
        ChromeSwitchPreference preference = new ChromeSwitchPreference(context);
        preference.setKey(key);
        preference.setPersistent(false);
        preference.setTitle(title);
        preference.setChecked(
                WebsitePreferenceBridge.getContentSetting(
                                getSiteSettingsDelegate().getBrowserContextHandle(), type, url, url)
                        == ContentSetting.ALLOW);
        preference.setOnPreferenceChangeListener(
                (changed, newValue) -> {
                    WebsitePreferenceBridge.setContentSettingDefaultScope(
                            getSiteSettingsDelegate().getBrowserContextHandle(),
                            type,
                            url,
                            new org.chromium.url.GURL(""),
                            (Boolean) newValue ? ContentSetting.ALLOW : ContentSetting.BLOCK);
                    return true;
                });
        return preference;
    }

    private androidx.preference.ListPreference irisList(
            android.content.Context context,
            String key,
            String title,
            String[] entries,
            String[] values,
            String current,
            java.util.function.Consumer<String> onChange) {
        androidx.preference.ListPreference preference =
                new androidx.preference.ListPreference(context);
        preference.setKey(key);
        preference.setPersistent(false);
        preference.setTitle(title);
        preference.setDialogTitle(title);
        preference.setEntries(entries);
        preference.setEntryValues(values);
        preference.setValue(current);
        preference.setSummaryProvider(
                androidx.preference.ListPreference.SimpleSummaryProvider.getInstance());
        preference.setOnPreferenceChangeListener(
                (changed, newValue) -> {
                    onChange.accept((String) newValue);
                    return true;
                });
        return preference;
    }
''', "private void setUpIrisPreferences()", "Iris section")
PY
