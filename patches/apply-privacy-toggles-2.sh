#!/usr/bin/env bash
# Iris — hardening toggles, part 2 (jegly 2026-10-08; all OFF by default; verified against 156.0.8078.11).
# Needs apply-shredder.sh (prefs + logic live in patches/src/chrome/browser/iris/iris_shredder.*) and
# apply-privacy-toggles-1.sh (anchors after its toggles / switches).
#   5. Coarser timers        profile pref iris.privacy.coarse_timers -> renderers started for that profile get
#                            --iris-coarse-timers (chrome_content_browser_client.cc) -> Blink's TimeClamper rounds
#                            performance.now(), event and animation timestamps to 100 ms (upstream 100 us, 5 us when
#                            cross-origin isolated) - Tor Browser's value. New pages; restart Iris for all.
#   6. UTC + US English      iris.privacy.standard_locale -> --iris-utc: Blink's TimeZoneController sets ICU/V8 to UTC
#                            and stops following the system time zone; IrisShredder swaps the website language list to
#                            "en-US" (saved + restored when turned off). Restart Iris for all pages.
#   7. Memory-only cache     iris.privacy.memory_cache -> ProfileNetworkContextService gives the network context no
#                            cache directory ("If null and the cache is enabled, an in-memory database is used",
#                            network_context.mojom) and deletes the old disk cache. After a restart.
#   8. Clear on exit         iris.privacy.clear_on_exit -> IrisShredder fills Chromium's ClearBrowsingDataOnExitList
#                            (history, downloads list, cookies + site data, cache) and marks it pending, so it is cleared
#                            when the last window closes (desktop) and at every start (crash; Android).
#   9. Turn off extensions   Chromium's own profile pref extensions.disabled (prefs::kDisableExtensions, read by
#                            extensions::util::AreExtensionsDisabled at start). Desktop only. After a restart.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (time_clamper.o, timezone_controller.o,
# chrome_content_browser_client.o, profile_network_context_service.o, iris_shredder.o, prefs_util.o, settings WebUI,
# chrome_java).
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

CT, SL, MC, CE = ("iris.privacy.coarse_timers", "iris.privacy.standard_locale", "iris.privacy.memory_cache",
                  "iris.privacy.clear_on_exit")
T = {
 "ct": ("Coarser timers",
        "Websites get time measurements rounded to 100 milliseconds, as in Tor Browser. Makes timing attacks much "
        "harder; animations and games may stutter. Applies to pages opened after you change it; restart Iris to apply "
        "it everywhere."),
 "sl": ("Use UTC and US English for websites",
        "Websites see the UTC time zone and English (United States) instead of yours, so you look like many other "
        "users. Sites may show the wrong local time. Your language list comes back when you turn this off. Restart Iris "
        "to apply it everywhere."),
 "mc": ("Keep the cache in memory only",
        "Pages and images are cached in memory instead of on disk, and the old disk cache is deleted. Takes effect "
        "after you restart Iris."),
 "ce": ("Clear browsing data when Iris closes",
        "History, the downloads list, cookies, site data and cached files are deleted when you close Iris, and again "
        "at the next start in case Iris did not close normally. Passwords and site settings are kept."),
 "ex": ("Turn off extensions",
        "No extensions run. They stay installed and come back when you turn this off. Takes effect after you restart "
        "Iris."),
}
CE_ANDROID = ("History, the downloads list, cookies, site data and cached files are deleted every time Iris starts. "
              "Passwords and site settings are kept.")

# --- renderer switches
edit("chrome/browser/chrome_content_browser_client.cc",
     "      Profile* profile =\n"
     "          Profile::FromBrowserContext(process->GetBrowserContext());\n"
     "      PrefService* prefs = profile->GetPrefs();\n"
     "      PrefService* local_state = g_browser_process->local_state();\n",
     "      Profile* profile =\n"
     "          Profile::FromBrowserContext(process->GetBrowserContext());\n"
     "      PrefService* prefs = profile->GetPrefs();\n"
     "      // Iris: privacy toggles a renderer needs at start\n"
     "      // (apply-privacy-toggles-2.sh; prefs registered by IrisShredder).\n"
     "      if (prefs->GetBoolean(\"%s\")) {\n"
     "        command_line->AppendSwitch(\"iris-coarse-timers\");\n"
     "      }\n"
     "      if (prefs->GetBoolean(\"%s\")) {\n"
     "        command_line->AppendSwitch(\"iris-utc\");\n"
     "      }\n"
     "      PrefService* local_state = g_browser_process->local_state();\n" % (CT, SL),
     "AppendSwitch(\"iris-coarse-timers\")", "renderer switches")

# --- Blink: timers
p = "third_party/blink/renderer/core/timing/time_clamper.cc"
edit(p, '#include "base/bit_cast.h"\n',
     '#include "base/bit_cast.h"\n#include "base/command_line.h"  // Iris\n',
     '#include "base/command_line.h"  // Iris', "include")
edit(p,
     "  int resolution = cross_origin_isolated_capability\n"
     "                       ? kFineResolutionMicroseconds\n"
     "                       : kCoarseResolutionMicroseconds;\n",
     "  int resolution = cross_origin_isolated_capability\n"
     "                       ? kFineResolutionMicroseconds\n"
     "                       : kCoarseResolutionMicroseconds;\n"
     "  // Iris: Settings -> \"Coarser timers\": 100 ms, Tor Browser's value\n"
     "  // (--iris-coarse-timers from the browser; apply-privacy-toggles-2.sh).\n"
     "  static const bool iris_coarse_timers =\n"
     "      base::CommandLine::ForCurrentProcess()->HasSwitch(\"iris-coarse-timers\");\n"
     "  if (iris_coarse_timers) {\n"
     "    resolution = 100000;\n"
     "  }\n",
     "iris_coarse_timers", "100 ms resolution")
edit("third_party/blink/renderer/core/DEPS",
     "    \"timezone_controller.cc\" : [\n        \"+base/command_line.h\",\n    ],\n",
     "    \"timezone_controller.cc\" : [\n        \"+base/command_line.h\",\n    ],\n"
     "    \"time_clamper.cc\" : [  # Iris: --iris-coarse-timers\n        \"+base/command_line.h\",\n    ],\n",
     "\"time_clamper.cc\" : [", "DEPS")

# --- Blink: UTC
edit("third_party/blink/renderer/core/timezone/timezone_controller.cc",
     "void TimeZoneController::Init() {\n",
     "void TimeZoneController::Init() {\n"
     "  // Iris: Settings -> \"Use UTC and US English for websites\" (--iris-utc;\n"
     "  // apply-privacy-toggles-2.sh): this renderer reports UTC and does not\n"
     "  // follow the system time zone.\n"
     "  if (base::CommandLine::ForCurrentProcess()->HasSwitch(\"iris-utc\")) {\n"
     "    {\n"
     "      base::AutoLock locker(instance().lock_);\n"
     "      instance().host_timezone_id_ = \"UTC\";\n"
     "    }\n"
     "    SetIcuTimeZoneAndNotifyV8(\"UTC\");\n"
     "    return;\n"
     "  }\n",
     "HasSwitch(\"iris-utc\")", "UTC")

# --- memory-only cache
edit("chrome/browser/net/profile_network_context_service.cc",
     "    network_context_params->file_paths->http_cache_directory =\n"
     "        base_cache_path.Append(chrome::kCacheDirname);\n",
     "    network_context_params->file_paths->http_cache_directory =\n"
     "        base_cache_path.Append(chrome::kCacheDirname);\n"
     "    // Iris: Settings -> \"Keep the cache in memory only\"\n"
     "    // (apply-privacy-toggles-2.sh): no directory = an in-memory cache (as in\n"
     "    // Incognito); the old disk cache is deleted.\n"
     "    if (profile_->GetPrefs()->GetBoolean(\"%s\")) {\n"
     "      base::ThreadPool::PostTask(\n"
     "          FROM_HERE, {base::MayBlock(), base::TaskPriority::BEST_EFFORT},\n"
     "          base::GetDeletePathRecursivelyCallback(\n"
     "              base_cache_path.Append(chrome::kCacheDirname)));\n"
     "      network_context_params->file_paths->http_cache_directory = std::nullopt;\n"
     "    }\n" % MC,
     "\"%s\"" % MC, "memory-only cache")

# --- settings allowlist + desktop toggles
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[::prefs::kDisable3DAPIs] = settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[::prefs::kDisable3DAPIs] = settings_api::PrefType::kBoolean;\n"
     "  // Iris: apply-privacy-toggles-2.sh\n"
     + "".join("  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % k for k in (CT, SL, MC, CE))
     + "  (*s_allowlist)[::prefs::kDisableExtensions] =\n      settings_api::PrefType::kBoolean;\n",
     "\"%s\"" % CT, "allowlist")
def tog(i, key, k):
    return ("    <settings-toggle-button id=\"%s\" class=\"hr\"\n"
            "        pref-key=\"%s\"\n"
            "        label=\"%s\"\n"
            "        sub-label=\"%s\">\n"
            "    </settings-toggle-button>\n") % (i, key, T[k][0], T[k][1])
p = "chrome/browser/resources/settings/privacy_page/privacy_page.html"
s = open(p).read()
if "irisCoarseTimersToggle" in s:
    print("SKIP already applied: %s (toggles)" % p)
else:
    A = "    <settings-toggle-button id=\"irisDownloadAskToggle\" class=\"hr\"\n"
    i = s.find(A)
    if i < 0 or s.count(A) != 1: die("%s: download toggle not found (run apply-privacy-toggles-1.sh first)" % p)
    j = s.find("    </settings-toggle-button>\n", i) + len("    </settings-toggle-button>\n")
    block = ("    <!-- Iris: apply-privacy-toggles-2.sh -->\n"
             + tog("irisCoarseTimersToggle", CT, "ct") + tog("irisStandardLocaleToggle", SL, "sl")
             + tog("irisMemoryCacheToggle", MC, "mc") + tog("irisClearOnExitToggle", CE, "ce")
             + tog("irisExtensionsOffToggle", "extensions.disabled", "ex"))
    open(p, "w").write(s[:j] + block + s[j:]); print("OK   %s : 5 toggles" % p)

# --- Android switches (no extensions on Android)
def sw(var, key, pref, title, summary):
    return ("        ChromeSwitchPreference %s =\n"
            "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
            "        %s.setKey(\"%s\");\n"
            "        %s.setPersistent(false);\n"
            "        %s.setTitle(\"%s\");\n"
            "        %s.setSummary(\n"
            "                \"%s\");\n"
            "        %s.setChecked(UserPrefs.get(getProfile()).getBoolean(\"%s\"));\n"
            "        %s.setOnPreferenceChangeListener(\n"
            "                (preference, newValue) -> {\n"
            "                    UserPrefs.get(getProfile()).setBoolean(\"%s\", (Boolean) newValue);\n"
            "                    return true;\n"
            "                });\n"
            "        irisCategory.addPreference(%s);\n") % (var, var, key, var, var, title, var, summary,
                                                        var, pref, var, pref, var)
edit("chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java",
     "        irisCategory.addPreference(irisDownloadAsk);\n",
     "        irisCategory.addPreference(irisDownloadAsk);\n"
     "        // Iris: apply-privacy-toggles-2.sh\n"
     + sw("irisCoarseTimers", "iris_coarse_timers", CT, T["ct"][0], T["ct"][1])
     + sw("irisStandardLocale", "iris_standard_locale", SL, T["sl"][0], T["sl"][1])
     + sw("irisMemoryCache", "iris_memory_cache", MC, T["mc"][0], T["mc"][1])
     + sw("irisClearOnExit", "iris_clear_on_exit", CE, "Clear browsing data when Iris starts", CE_ANDROID),
     "apply-privacy-toggles-2.sh", "Android switches")
PY
echo "=== privacy toggles part 2 complete ==="
