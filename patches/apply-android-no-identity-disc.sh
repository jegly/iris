#!/usr/bin/env bash
# Iris — no account button (person in a circle) in the Android toolbar on the new tab page (jegly 2026-10-11: "on the
# homepage there is a human in a circle symbol when i click it it goes to settings, that should be removed because we
# alrdy have the 3 dots"; verified against 156.0.8078.11).
# The button is IdentityDiscController (chrome/android/.../identity_disc/IdentityDiscController.java), an adaptive
# toolbar button shown only on the NTP: signed out it opens Settings / the sign-in sheet, signed in it shows the account
# picture. Iris has no Google sign-in, so it only ever led to Settings, which the menu already has.
# How: calculateButtonData() (the only place that sets canShow(true): from get() on the NTP and from the profile /
# sign-in listeners) now always reports "can't show". The controller still exists, so nothing that refers to it
# changes. The space goes back to the address bar.
# Needs nothing else. STATUS 2026-10-11: copy-tested only, NOT compile-proven (chrome/android:chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/android/java/src/org/chromium/chrome/browser/identity_disc/IdentityDiscController.java"
s = open(p).read()
MARK = "IRIS_NO_IDENTITY_DISC"
if MARK in s:
    print("SKIP already applied: %s (account button hidden)" % p); sys.exit(0)
OLD = ("    private void calculateButtonData() {\n"
       "        if (mProfile == null) {\n")
NEW = ("    // Iris: no account button on the new tab page (apply-android-no-identity-disc.sh);\n"
       "    // Iris has no Google sign-in and Settings is in the menu.\n"
       "    private static final boolean IRIS_NO_IDENTITY_DISC = true;\n"
       "\n"
       "    private void calculateButtonData() {\n"
       "        if (IRIS_NO_IDENTITY_DISC) {\n"
       "            mButtonData.setCanShow(false);\n"
       "            return;\n"
       "        }\n"
       "        if (mProfile == null) {\n")
if s.count(OLD) != 1:
    sys.stderr.write("ERROR: %s: calculateButtonData() anchor found %d times (drift?)\n" % (p, s.count(OLD))); sys.exit(1)
open(p, "w").write(s.replace(OLD, NEW))
print("OK   %s : account button hidden" % p)
PY
echo "=== android no identity disc complete ==="
