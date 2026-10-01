#!/usr/bin/env bash
# Iris — Android: hide "Google Password Manager" from Settings (jegly 2026-10-01).
# The Android password manager needs Google's GMS password backend, which exists only in closed-source Chrome:
# the open-source *UpstreamImpl classes (PasswordManagerBackendSupportHelperUpstreamImpl, ...) are empty stubs,
# so in Iris the entry can only ever show "Stopped working on this device". Password saving prompts are already
# off by default (kCredentialsEnableService = false, apply-phase-a-flips.sh). Users pick a password app instead in
# Settings > Autofill settings > Autofill services (Bitwarden, Proton Pass, ...).
# MainSettings.java: remove the entry after its normal setup (keeps every method used: Chromium's Java checks
# reject unused code) and drop it from the settings search index too.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/android/java/src/org/chromium/chrome/browser/settings/MainSettings.java"
s = open(p).read()
def edit(old, new, marker, label):
    global s
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: sys.stderr.write("ERROR: %s: anchor for %s not found exactly once (drift?)\n" % (p, label)); sys.exit(1)
    s = s.replace(old, new, 1); print("OK   %s : %s" % (p, label))
M1 = "        removePreferenceIfPresent(PREF_PASSWORDS); // Iris: GPM cannot work in Chromium builds\n"
edit("                    showPasswordSettings(\n"
     "                            getActivity(),\n"
     "                            getProfile(),\n"
     "                            mModalDialogManagerSupplier.asNonNull().get());\n"
     "                    return true;\n"
     "                });\n"
     "    }\n"
     "\n"
     "    private static void openAutofillOptions(",
     "                    showPasswordSettings(\n"
     "                            getActivity(),\n"
     "                            getProfile(),\n"
     "                            mModalDialogManagerSupplier.asNonNull().get());\n"
     "                    return true;\n"
     "                });\n"
     + M1 +
     "    }\n"
     "\n"
     "    private static void openAutofillOptions(",
     M1, "hide the Google Password Manager entry")
# updateAutofillPreferences() runs up to 3 times (create, resume, prefs change): after the first run the entry is
# off the screen, so take it from the cached map (mAllPreferences, filled once by cachePreferences()) instead of
# findPreference(), which would return null and crash on setProfile().
M3 = ("        PasswordsPreference passwordsPreference =\n"
      "                (PasswordsPreference) mAllPreferences.get(PREF_PASSWORDS); // Iris: may be off-screen\n"
      "        assumeNonNull(passwordsPreference);\n")
edit("        PasswordsPreference passwordsPreference = findPreference(PREF_PASSWORDS);\n"
     "        passwordsPreference.setProfile(getProfile());\n",
     M3 + "        passwordsPreference.setProfile(getProfile());\n",
     M3, "set up the entry from the cache (no null on re-run)")
M2 = "                        indexData.removeEntry(getUniqueId(PREF_PASSWORDS)); // Iris\n"
edit("                    } else {\n"
     "                        indexData.removeEntry(getUniqueId(PREF_AUTOFILL_AND_PASSWORDS));\n",
     "                    } else {\n"
     "                        indexData.removeEntry(getUniqueId(PREF_AUTOFILL_AND_PASSWORDS));\n"
     + M2,
     M2, "drop it from settings search")
open(p, "w").write(s)
PY
