#!/usr/bin/env bash
# Iris — Android: hide "Google Password Manager" from Settings (jegly 2026-10-01).
# The Android password manager needs Google's GMS password backend, which exists only in closed-source Chrome:
# the open-source *UpstreamImpl classes (PasswordManagerBackendSupportHelperUpstreamImpl, ...) are empty stubs,
# so in Iris the entry can only ever show "Stopped working on this device". Password saving prompts are already
# off by default (kCredentialsEnableService = false, apply-phase-a-flips.sh). Users pick a password app instead in
# Settings > Autofill settings > Autofill services (Bitwarden, Proton Pass, ...).
# M158 (2026-11-20): the GPM row LEFT MainSettings (PREF_PASSWORDS, showPasswordSettings, the mAllPreferences
# workaround and its search entry are all gone there; main settings only has "Autofill and passwords" now) and moved
# into the new AutofillAndPasswordsFragment as PREF_PASSWORDS = "autofill_and_passwords_gpm". This version hides it
# there: setVisible(false) after its normal setup (keeps every method used: Chromium's Java checks reject unused
# code) + drop it from that page's settings search index. The <= 157 MainSettings edits are retired; the guard
# below fails if a GPM row comes back to MainSettings.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
m = "chrome/android/java/src/org/chromium/chrome/browser/settings/MainSettings.java"
ms = open(m).read()
if "PREF_PASSWORDS" in ms or "showPasswordSettings(" in ms:
    sys.stderr.write("ERROR: %s: a Google Password Manager row is back in MainSettings (drift: hide it there too)\n" % m)
    sys.exit(1)
print("GUARD ok: no GPM row in MainSettings (158 layout)")

p = "chrome/android/java/src/org/chromium/chrome/browser/autofill/settings/AutofillAndPasswordsFragment.java"
s = open(p).read()
def edit(old, new, marker, label):
    global s
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: sys.stderr.write("ERROR: %s: anchor for %s not found exactly once (drift?)\n" % (p, label)); sys.exit(1)
    s = s.replace(old, new, 1); print("OK   %s : %s" % (p, label))
M1 = "        passwordsPreference.setVisible(false); // Iris: GPM cannot work in Chromium builds\n"
edit("                            ManagePasswordsReferrer.CHROME_SETTINGS_AUTOFILL_AND_PASSWORDS,\n"
     "                            mModalDialogManagerSupplier.asNonNull().get(),\n"
     "                            /* managePasskeys= */ false);\n"
     "                    return true;\n"
     "                });\n"
     "\n"
     "        findPreference(PREF_AUTOFILL_PAYMENTS)\n",
     "                            ManagePasswordsReferrer.CHROME_SETTINGS_AUTOFILL_AND_PASSWORDS,\n"
     "                            mModalDialogManagerSupplier.asNonNull().get(),\n"
     "                            /* managePasskeys= */ false);\n"
     "                    return true;\n"
     "                });\n"
     + M1 +
     "\n"
     "        findPreference(PREF_AUTOFILL_PAYMENTS)\n",
     M1, "hide the Google Password Manager entry")
M2 = "                    indexData.removeEntry(getUniqueId(PREF_PASSWORDS)); // Iris\n"
edit("                    indexData.removeEntry(getUniqueId(PREF_SIGNIN_PROMO));\n",
     "                    indexData.removeEntry(getUniqueId(PREF_SIGNIN_PROMO));\n" + M2,
     M2, "drop it from settings search")
open(p, "w").write(s)
PY
