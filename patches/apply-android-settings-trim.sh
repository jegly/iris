#!/usr/bin/env bash
# Iris — Android Settings: remove Google services items, Safety check and Developer options (jegly 2026-10-05, from
# testing the -3 APK; verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# 1. Google services page (GoogleServicesSettings.java; its row in Settings is already gone, apply-android-no-google-
#    settings.sh, but the page is still reachable): hide "Allow Iris sign-in", "Help improve Iris's features and
#    performance" (usage + crash reports to Google), "Make searches and browsing better" (URLs to Google),
#    "Touch to Search" and usage-stats reporting, and drop them from Settings search. "Improve search suggestions"
#    stays (it talks to the user's own search engine and is off by default in Iris).
# 2. Safety check (Settings -> Safety check / Safety Hub): removed from Settings and Settings search via upstream's
#    own MainSettings.shouldShowSafetyHubPref() switch (jegly: "Iris doesn't use it"; its cards were about Google
#    account passwords, Google's Safe Browsing and links to Google pages).
# 3. Developer options (tracing etc.): Chromium shows it on every build whose channel is <= DEV, which includes
#    Iris's APK (no release channel = "local"). DeveloperSettings.shouldShowDeveloperSettings() now returns false, so
#    the row is gone and tapping the version in About does not bring it back.
# Uses `if (IRIS_...) return false;` with a constant so the upstream code after it stays reachable (javac rejects
# unreachable statements) and its imports stay used.
# Needs apply-android-no-google-settings.sh first (same MainSettings.java; different anchors).
# STATUS 2026-10-05: copy-tested only, NOT compile-proven (chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def add_constant(s, p, line):
    if line in s: return s
    t = s.rstrip()
    if not t.endswith("}"): die("%s: class end not found (drift?)" % p)
    i = t.rfind("}")
    return s[:i] + "\n" + line + s[i:]

# --- 1. Google services page
p = "chrome/android/java/src/org/chromium/chrome/browser/sync/settings/GoogleServicesSettings.java"
s = open(p).read()
if "IRIS_HIDDEN_PREFS" in s:
    print("SKIP already applied: %s" % p)
else:
    a1 = "        mUsageStatsReporting.setVisible(true);\n\n        updatePreferences();\n    }\n"
    a2 = ("                    if (!shouldShowUsageStatsReporting(UserPrefs.get(profile))) {\n"
          "                        indexData.removeEntry(getUniqueId(PREF_USAGE_STATS_REPORTING));\n"
          "                    }\n")
    for a, what in ((a1, "end of onCreatePreferences"), (a2, "search index usage-stats removal")):
        if s.count(a) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
    s = s.replace(a1, "        mUsageStatsReporting.setVisible(true);\n\n        updatePreferences();\n"
                  "        // Iris: no Google sign-in, Google reporting, URL collection or Touch to Search.\n"
                  "        for (String key : IRIS_HIDDEN_PREFS) {\n"
                  "            Preference pref = findPreference(key);\n"
                  "            if (pref != null) pref.setVisible(false);\n"
                  "        }\n    }\n", 1)
    s = s.replace(a2, a2 +
                  "                    for (String key : IRIS_HIDDEN_PREFS) {\n"
                  "                        indexData.removeEntry(getUniqueId(key)); // Iris\n"
                  "                    }\n", 1)
    s = add_constant(s, p,
        "    // Iris: Google-only items hidden on this page (apply-android-settings-trim.sh).\n"
        "    private static final String[] IRIS_HIDDEN_PREFS = {\n"
        "        PREF_ALLOW_SIGNIN,\n"
        "        PREF_USAGE_AND_CRASH_REPORTING,\n"
        "        PREF_URL_KEYED_ANONYMIZED_DATA,\n"
        "        PREF_CONTEXTUAL_SEARCH,\n"
        "        PREF_USAGE_STATS_REPORTING,\n"
        "    };\n")
    open(p, "w").write(s); print("OK   %s : Google items hidden (page + search)" % p)

# --- 2. Safety check row
p = "chrome/android/java/src/org/chromium/chrome/browser/settings/MainSettings.java"
s = open(p).read()
M = "        if (IRIS_NO_SAFETY_CHECK) return false; // Iris: no Safety check\n"
if M in s:
    print("SKIP already applied: %s" % p)
else:
    a = "    private static boolean shouldShowSafetyHubPref() {\n"
    if s.count(a) != 1: die("%s: shouldShowSafetyHubPref() not found exactly once (drift?)" % p)
    s = s.replace(a, a + M, 1)
    s = add_constant(s, p, "    private static final boolean IRIS_NO_SAFETY_CHECK = true; // Iris\n")
    open(p, "w").write(s); print("OK   %s : Safety check row + search entry removed" % p)

# --- 3. Developer options
p = "chrome/android/java/src/org/chromium/chrome/browser/tracing/settings/DeveloperSettings.java"
s = open(p).read()
M = "        if (IRIS_NO_DEVELOPER_SETTINGS) return false; // Iris: never shown\n"
if M in s:
    print("SKIP already applied: %s" % p)
else:
    a = ("    public static boolean shouldShowDeveloperSettings() {\n"
         "        // Always enabled on canary, dev and local builds, otherwise can be enabled by tapping the\n"
         "        // Chrome version in Settings>About multiple times.\n")
    if s.count(a) != 1: die("%s: shouldShowDeveloperSettings() not found exactly once (drift?)" % p)
    s = s.replace(a, a + M, 1)
    s = add_constant(s, p, "    private static final boolean IRIS_NO_DEVELOPER_SETTINGS = true; // Iris\n")
    open(p, "w").write(s); print("OK   %s : Developer options never shown" % p)
PY
echo "=== Android settings trim complete ==="
