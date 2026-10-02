#!/usr/bin/env bash
# Iris — Android Settings: no "You and Google" section (jegly 2026-10-02: "there is still a menu that says you and
# google and underneath it says google services"). Verified against this checkout.
# MainSettings.java (main_preferences.xml keys): the "account_and_google_services_section" header ("You and
# Google"), "sign_in" (Google account sign-in) and "google_services" (Google services settings). Iris has no
# Google account sign-in and no Google services (Play services is a strict no; apply-android-no-gms.sh).
#  1) shouldShowSignInPref() -> false: the existing code then removes the sign-in row and its search entry.
#  2) After the sign-in row is handled, also remove the Google services row and the section header (same helper
#     upstream uses for other rows; removePreferenceIfPresent is a no-op when already gone).
#  3) Settings search: drop the Google services + section entries (SettingsIndexData.removeEntry is a map remove).
# The preferences are still created/initialised first (upstream code untouched), so nothing can be null.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/android/java/src/org/chromium/chrome/browser/settings/MainSettings.java"
s = open(p).read()
def edit(old, new, marker, label):
    global s
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    s = s.replace(old, new, 1); print("OK   %s : %s" % (p, label))

M1 = "        if (IRIS_NO_GOOGLE_ACCOUNT) return false; // Iris: no Google sign-in\n"
edit("    private static boolean shouldShowSignInPref(Profile profile) {\n",
     "    private static boolean shouldShowSignInPref(Profile profile) {\n" + M1, M1, "no sign-in row")
M2 = ("        removePreferenceIfPresent(PREF_GOOGLE_SERVICES); // Iris: no 'You and Google'\n"
      "        removePreferenceIfPresent(PREF_ACCOUNT_AND_GOOGLE_SERVICES_SECTION); // Iris\n")
edit("            removePreferenceIfPresent(PREF_SIGN_IN);\n        }\n",
     "            removePreferenceIfPresent(PREF_SIGN_IN);\n        }\n" + M2, M2, "no Google services row + header")
M3 = ("                    indexData.removeEntry(getUniqueId(PREF_GOOGLE_SERVICES)); // Iris\n"
      "                    indexData.removeEntry(\n"
      "                            getUniqueId(PREF_ACCOUNT_AND_GOOGLE_SERVICES_SECTION)); // Iris\n")
edit("                    indexData.removeEntry(getUniqueId(PREF_SETTINGS_PROMO_CARD));\n",
     "                    indexData.removeEntry(getUniqueId(PREF_SETTINGS_PROMO_CARD));\n" + M3, M3, "settings search")
C = "    private static final boolean IRIS_NO_GOOGLE_ACCOUNT = true; // Iris\n"
if C in s: print("SKIP already applied: %s (constant)" % p)
else:
    i = s.rstrip().rfind("}")
    if not s.rstrip().endswith("}"): die("%s: class end not found (drift?)" % p)
    s = s[:i] + "\n" + C + s[i:]; print("OK   %s : constant" % p)
open(p, "w").write(s)
PY
