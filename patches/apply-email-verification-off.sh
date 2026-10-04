#!/usr/bin/env bash
# Iris — no automatic email verification (jegly 2026-10-05: Android "Addresses and more" showed "Automatically verify
# your email" ON + a "Verified email" list; verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# The Email Verification Protocol lets the browser ask your email provider (e.g. gmail.com) to confirm your address to
# websites in the background, without you opening your inbox. Iris doesn't do that:
#  1. features::kEmailVerificationProtocol (content/public/common/content_features.cc) ENABLED -> DISABLED. This also
#     removes the Settings toggle and "Verified email" section (AutofillProfilesFragment adds them only when it's on).
#  2. Belt and braces: autofill pref kAutofillEmailVerificationEnabled default true -> false
#     (components/autofill/core/common/autofill_prefs.cc).
# Desktop + Android.
# STATUS 2026-10-05: copy-tested only, NOT compile-proven (content_features.o, autofill_prefs.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, label):
    s = open(p).read()
    if new in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

edit("content/public/common/content_features.cc",
     "BASE_FEATURE(kEmailVerificationProtocol, base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "BASE_FEATURE(kEmailVerificationProtocol,\n"
     "             base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no email verification\n",
     "Email Verification Protocol off")
edit("components/autofill/core/common/autofill_prefs.cc",
     "  registry->RegisterBooleanPref(kAutofillEmailVerificationEnabled, true);\n",
     "  registry->RegisterBooleanPref(kAutofillEmailVerificationEnabled,\n"
     "                                false);  // Iris\n",
     "email verification pref off")
PY
echo "=== email verification off complete ==="
