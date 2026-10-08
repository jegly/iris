#!/usr/bin/env bash
# Iris — hardening toggles, part 1 (jegly 2026-10-08: "have all these in security & privacy in settings as toggles so
# Iris becomes more configurable"; all OFF by default; verified against 156.0.8078.11). Needs apply-adblock-extra.sh
# (anchors after its toggle / switch).
#   1. Turn JavaScript off       = the global JavaScript default (profile.default_content_setting_values.javascript:
#                                  1 allow / 2 block), the same setting as Site settings -> JavaScript; per-site allow
#                                  keeps working. Immediate.
#   2. Turn off service workers  = new profile pref iris.privacy.no_service_workers, checked in
#                                  ChromeContentBrowserClient::AllowServiceWorker() for http(s) scopes only
#                                  (extension service workers = MV3 backgrounds keep working). Immediate.
#   3. Turn WebGL off completely = Chromium's own profile pref disable_3d_apis (prefs::kDisable3DAPIs), which Iris's
#                                  per-site WebGL gate already checks first (apply-iris-permissions.sh), so it wins over
#                                  per-site allows. Immediate for new pages.
#   4. Ask before every download = Chromium's own download.prompt_for_download (desktop; same as Settings -> Downloads)
#                                  / download.prompt_for_download_android via DownloadDialogBridge (Android).
# Desktop: Settings -> Privacy and security (after "Block more ads and trackers"), English-only labels.
# Android: Settings -> Privacy and security -> Iris section.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (chrome_content_browser_client.o, prefs_util.o, settings
# WebUI, chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
import os
IRIS_HARDENING = "chrome/browser/resources/settings/privacy_page/iris_hardening_page.html"
def moved(toggle_id):  # moved to the Iris hardening page by apply-iris-hardening-page.sh
    return os.path.exists(IRIS_HARDENING) and toggle_id in open(IRIS_HARDENING).read()
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

SW = "iris.privacy.no_service_workers"
T = {
 "js":  ("Turn JavaScript off",
         "Websites can't run JavaScript unless you allow them from the lock icon. Many sites won't work."),
 "sw":  ("Turn off service workers",
         "Websites can't install background scripts that cache pages, intercept requests or run after you leave. "
         "Some web apps won't work offline."),
 "gl":  ("Turn WebGL off completely",
         "No 3D graphics on any website, even ones you allowed. Removes a large attack surface and a way to identify "
         "your graphics hardware."),
 "dl":  ("Ask before every download",
         "Iris asks where to save each file, so nothing is downloaded without you choosing it."),
}

# --- browser: service worker pref + check
c = "chrome/browser/chrome_content_browser_client.cc"
edit(c,
     "void ChromeContentBrowserClient::RegisterProfilePrefs(\n"
     "    user_prefs::PrefRegistrySyncable* registry) {\n"
     "  registry->RegisterBooleanPref(prefs::kDisable3DAPIs, false);\n",
     "namespace {\n"
     "// Iris: Settings -> Privacy and security -> \"Turn off service workers\"\n"
     "// (apply-privacy-toggles-1.sh).\n"
     "const char kIrisNoServiceWorkersPref[] = \"%s\";\n"
     "}  // namespace\n\n"
     "void ChromeContentBrowserClient::RegisterProfilePrefs(\n"
     "    user_prefs::PrefRegistrySyncable* registry) {\n"
     "  registry->RegisterBooleanPref(prefs::kDisable3DAPIs, false);\n"
     "  registry->RegisterBooleanPref(kIrisNoServiceWorkersPref, false);  // Iris\n" % SW,
     "kIrisNoServiceWorkersPref[]", "register service-worker pref")
edit(c,
     "  Profile* profile = Profile::FromBrowserContext(context);\n"
     "  scoped_refptr<content_settings::CookieSettings> cookie_settings =\n"
     "      CookieSettingsFactory::GetForProfile(profile);\n"
     "  return embedder_support::AllowServiceWorker(\n",
     "  Profile* profile = Profile::FromBrowserContext(context);\n"
     "  // Iris: website service workers off when the user chose so (extension\n"
     "  // service workers are not http(s) and keep working).\n"
     "  if (scope.SchemeIsHTTPOrHTTPS() &&\n"
     "      profile->GetPrefs()->GetBoolean(kIrisNoServiceWorkersPref)) {\n"
     "    return content::AllowServiceWorkerResult::No();\n"
     "  }\n"
     "  scoped_refptr<content_settings::CookieSettings> cookie_settings =\n"
     "      CookieSettingsFactory::GetForProfile(profile);\n"
     "  return embedder_support::AllowServiceWorker(\n",
     "GetBoolean(kIrisNoServiceWorkersPref)", "service-worker check")

# --- settings allowlist
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[\"iris.adblock.extra\"] = settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[\"iris.adblock.extra\"] = settings_api::PrefType::kBoolean;\n"
     "  // Iris: Settings -> Privacy and security toggles (apply-privacy-toggles-1.sh).\n"
     "  (*s_allowlist)[\"profile.default_content_setting_values.javascript\"] =\n"
     "      settings_api::PrefType::kNumber;\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n"
     "  (*s_allowlist)[::prefs::kDisable3DAPIs] = settings_api::PrefType::kBoolean;\n" % SW,
     '"%s"' % SW, "allowlist")

# --- desktop toggles
def tog(i, key, k, extra=""):
    return ("    <settings-toggle-button id=\"%s\" class=\"hr\"\n"
            "        pref-key=\"%s\"%s\n"
            "        label=\"%s\"\n"
            "        sub-label=\"%s\">\n"
            "    </settings-toggle-button>\n") % (i, key, extra, T[k][0], T[k][1])
A = ("    <settings-toggle-button id=\"irisAdblockExtraToggle\" class=\"hr\"\n")
p = "chrome/browser/resources/settings/privacy_page/privacy_page.html"
s = open(p).read()
if "irisJavascriptOffToggle" in s or moved("irisJavascriptOffToggle"):
    print("SKIP already applied: %s (toggles)" % p)
else:
    i = s.find(A)
    if i < 0 or s.count(A) != 1: die("%s: adblock-extra toggle not found (run apply-adblock-extra.sh first)" % p)
    j = s.find("    </settings-toggle-button>\n", i) + len("    </settings-toggle-button>\n")
    block = ("    <!-- Iris: hardening toggles, off by default (apply-privacy-toggles-1.sh; English-only, TODO localize) -->\n"
             + tog("irisJavascriptOffToggle", "profile.default_content_setting_values.javascript", "js",
                   "\n        numeric-checked-value=\"2\"\n        numeric-unchecked-values=\"[1, 0]\"")
             + tog("irisServiceWorkersOffToggle", SW, "sw")
             + tog("irisWebglOffToggle", "disable_3d_apis", "gl")
             + tog("irisDownloadAskToggle", "download.prompt_for_download", "dl"))
    open(p, "w").write(s[:j] + block + s[j:]); print("OK   %s : 4 toggles" % p)

# --- Android switches
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
CS = "org.chromium.components.content_settings.ContentSetting"
DB = "org.chromium.chrome.browser.download.DownloadDialogBridge"
DS = "org.chromium.chrome.browser.download.DownloadPromptStatus"
def sw(var, key, title, summary, checked, onchange):
    return ("        ChromeSwitchPreference %s =\n"
            "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
            "        %s.setKey(\"%s\");\n"
            "        %s.setPersistent(false);\n"
            "        %s.setTitle(\"%s\");\n"
            "        %s.setSummary(\n"
            "                \"%s\");\n"
            "        %s.setChecked(%s);\n"
            "        %s.setOnPreferenceChangeListener(\n"
            "                (preference, newValue) -> {\n"
            "                    %s\n"
            "                    return true;\n"
            "                });\n"
            "        irisCategory.addPreference(%s);\n") % (var, var, key, var, var, title, var, summary,
                                                        var, checked, var, onchange, var)
JBLOCK = ("        // Iris: hardening switches, off by default (apply-privacy-toggles-1.sh).\n"
  + sw("irisJsOff", "iris_js_off", T["js"][0],
       "Websites can't run JavaScript unless you allow them in Site settings. Many sites won't work.",
       "WebsitePreferenceBridge.getDefaultContentSetting(\n                        getProfile(), ContentSettingsType.JAVASCRIPT)\n                == %s.BLOCK" % CS,
       "WebsitePreferenceBridge.setDefaultContentSetting(\n                            getProfile(),\n"
       "                            ContentSettingsType.JAVASCRIPT,\n"
       "                            (Boolean) newValue ? %s.BLOCK : %s.ALLOW);" % (CS, CS))
  + sw("irisSwOff", "iris_sw_off", T["sw"][0], T["sw"][1],
       "UserPrefs.get(getProfile()).getBoolean(\"%s\")" % SW,
       "UserPrefs.get(getProfile()).setBoolean(\"%s\", (Boolean) newValue);" % SW)
  + sw("irisWebglOff", "iris_webgl_off", T["gl"][0], T["gl"][1],
       "UserPrefs.get(getProfile()).getBoolean(\"disable_3d_apis\")",
       "UserPrefs.get(getProfile()).setBoolean(\"disable_3d_apis\", (Boolean) newValue);")
  + sw("irisDownloadAsk", "iris_download_ask", T["dl"][0], T["dl"][1],
       "%s.getPromptForDownloadAndroid(getProfile())\n                == %s.SHOW_PREFERENCE" % (DB, DS),
       "%s.setPromptForDownloadAndroid(\n                            getProfile(),\n"
       "                            (Boolean) newValue ? %s.SHOW_PREFERENCE : %s.DONT_SHOW);" % (DB, DS, DS)))
edit(J, "        irisCategory.addPreference(irisAdblockExtra);\n",
     "        irisCategory.addPreference(irisAdblockExtra);\n" + JBLOCK,
     "apply-privacy-toggles-1.sh", "Android switches")
PY
echo "=== privacy toggles part 1 complete ==="
