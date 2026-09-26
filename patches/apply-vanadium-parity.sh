#!/usr/bin/env bash
# Iris — Vanadium parity + extras (verified against checkout 2026-09-26). Mirrors GrapheneOS Vanadium patches
# (our own code; Vanadium ref in brackets) plus one Iris-only find. jegly approved all.
#  1 [0100] ALWAYS LOCAL New Tab Page. NewTabURLDetails returned the default search engine's new_tab_url
#          (DuckDuckGo: https://duckduckgo.com/chrome_newtab) -> every new tab hit a remote server. Now the
#          final return uses local_url (chrome://new-tab-page-third-party). No dead code (-Wunreachable-code).
#  2 [0091] no remote search-provider logo fetch (only Android/iOS fetch non-Google DSE logos)
#  3 [0070] contextual search ("Touch to Search", Android) default "" -> kContextualSearchDisabledValue
#  4 [0074] no popular-sites fetch: ChromePopularSitesFactory -> nullptr (MostVisitedSites handles null, as on
#          desktop) + kPopularSitesBakedInContentFeature OFF
#  5 [Iris] NTP tiles no longer fetch "most likely" favicons from Google's favicon server
#          (kNtpMostLikelyFaviconsFromServerFeature was ON -> leaks visited domains)
#  6 [0087] Safe Browsing surveys + deep scanning (upload files to Google) default off
#          ([0086] scout-reporting opt-in is already false upstream)
#  7 [0088] MediaDrm preprovisioning off (Android contacts provisioning servers at startup)
#  8 [0063] Android first-run flow treated as complete (FirstRunStatus.getFirstRunFlowComplete -> true);
#          desktop equivalent = --no-first-run in apply-default-switches.sh
#  9 [0092] never hide trivial subdomains (www., m.) in the omnibox — both platforms
# 10 [Cromite] desktop "Always show full URLs" default ON (kPreventUrlElisionsInOmnibox)
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys, re
def die(m): sys.stderr.write("ERROR: "+m+"\n"); sys.exit(1)
def edit(path, old, new, marker, regex=False):
    s = open(path).read()
    if marker in s: print("SKIP already applied: "+path); return
    n = len(re.findall(old, s)) if regex else s.count(old)
    if n != 1: die(f"{path}: expected 1 match, found {n} (drift?): {old[:70]!r}")
    s = re.sub(old, new, s, count=1) if regex else s.replace(old, new)
    open(path, "w").write(s); print("OK   "+path)

edit("chrome/browser/search/search.cc",
     "    return NewTabURLDetails(search_provider_url, NEW_TAB_URL_VALID);",
     "    return NewTabURLDetails(local_url, NEW_TAB_URL_VALID);  // Iris: always local NTP",
     "// Iris: always local NTP")
edit("components/search_provider_logos/logo_service_impl.cc",
     "    logo_url = template_url->logo_url();",
     "    // Iris: never fetch a remote search-provider logo (was: template_url->logo_url()).",
     "// Iris: never fetch a remote search-provider logo")
edit("chrome/browser/profiles/profile.cc",
     r"(prefs::kContextualSearchEnabled,\s*)std::string\(\),",
     r"\1prefs::kContextualSearchDisabledValue,  // Iris",
     "prefs::kContextualSearchDisabledValue,  // Iris", regex=True)
edit("chrome/browser/ntp_tiles/chrome_most_visited_sites_factory.cc",
     "      ChromePopularSitesFactory::NewForProfile(profile),",
     "      nullptr,  // Iris: no popular-sites fetch (was ChromePopularSitesFactory::NewForProfile)",
     "nullptr,  // Iris: no popular-sites fetch")
edit("components/ntp_tiles/features.cc",
     r'("NTPPopularSitesBakedInContent",\s*)base::FEATURE_ENABLED_BY_DEFAULT',
     r'\1base::FEATURE_DISABLED_BY_DEFAULT', '"NTPPopularSitesBakedInContent",\n             base::FEATURE_DISABLED', regex=True)
edit("components/ntp_tiles/features.cc",
     r'("NTPMostLikelyFaviconsFromServer",\s*)base::FEATURE_ENABLED_BY_DEFAULT',
     r'\1base::FEATURE_DISABLED_BY_DEFAULT', '"NTPMostLikelyFaviconsFromServer",\n             base::FEATURE_DISABLED', regex=True)
SB = "components/safe_browsing/core/common/safe_browsing_prefs.cc"
edit(SB, "registry->RegisterBooleanPref(prefs::kSafeBrowsingSurveysEnabled, true);",
         "registry->RegisterBooleanPref(prefs::kSafeBrowsingSurveysEnabled, false);",
         "kSafeBrowsingSurveysEnabled, false);")
edit(SB, "registry->RegisterBooleanPref(prefs::kSafeBrowsingDeepScanningEnabled, true);",
         "registry->RegisterBooleanPref(prefs::kSafeBrowsingDeepScanningEnabled, false);",
         "kSafeBrowsingDeepScanningEnabled, false);")
edit("media/base/media_switches.cc",
     "BASE_FEATURE(kMediaDrmPreprovisioning, base::FEATURE_ENABLED_BY_DEFAULT);",
     "BASE_FEATURE(kMediaDrmPreprovisioning, base::FEATURE_DISABLED_BY_DEFAULT);",
     "BASE_FEATURE(kMediaDrmPreprovisioning, base::FEATURE_DISABLED_BY_DEFAULT);")
edit("chrome/browser/first_run/android/java/src/org/chromium/chrome/browser/firstrun/FirstRunStatus.java",
     "    public static boolean getFirstRunFlowComplete() {\n        return ChromeSharedPreferences.getInstance()\n                .readBoolean(ChromePreferenceKeys.FIRST_RUN_FLOW_COMPLETE, false);\n    }",
     "    public static boolean getFirstRunFlowComplete() {\n        // Iris (as Vanadium 0063): skip the first-run flow.\n        return true;\n    }",
     "// Iris (as Vanadium 0063)")
edit("components/omnibox/browser/location_bar_model_impl.cc",
     "  format_types |= url_formatter::kFormatUrlOmitTrivialSubdomains;\n",
     "  // Iris: never hide trivial subdomains (www., m.) — helps spot lookalike hosts.\n",
     "// Iris: never hide trivial subdomains")
edit("chrome/browser/ui/toolbar/chrome_location_bar_model_delegate.cc",
     "registry->RegisterBooleanPref(omnibox::kPreventUrlElisionsInOmnibox, false);",
     "registry->RegisterBooleanPref(omnibox::kPreventUrlElisionsInOmnibox, true);",
     "kPreventUrlElisionsInOmnibox, true);")
PY
echo "=== Vanadium parity complete ==="
