#!/usr/bin/env bash
# Iris — no Gmail one-time-code fetching (2026-11-05, M157 upstream audit; jegly did not object to the safeguard).
# Verified against 157.0.8103.38: both are ON on desktop since 157 and both need a signed-in Google account today, so
# they cannot run in Iris; this keeps it that way if upstream ever drops the sign-in requirement.
#  - one_time_tokens::features::kGmailOtpRetrievalService (components/one_time_tokens/core/common/
#    one_time_token_features.cc): OneTimeTokenServiceFactory builds a GmailOtpBackend that reads login codes from
#    the user's Gmail through Google's servers (IdentityManager OAuth token).
#  - kOneTimeTokenBackendNotification (components/sharing_message/features.cc): the matching sync/sharing push
#    ("a new code arrived") registered by the sharing service.
# Off on every platform (were desktop-only upstream). SMS codes on Android (AndroidSmsOtpBackend) are separate, local.
# STATUS 2026-11-05: copy-tested on 157 file copies, NOT compile-proven.
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
COND = ("#if !BUILDFLAG(IS_ANDROID) && !BUILDFLAG(IS_IOS)\n"
        "             base::FEATURE_ENABLED_BY_DEFAULT\n"
        "#else\n"
        "             base::FEATURE_DISABLED_BY_DEFAULT\n"
        "#endif\n"
        ");\n")
for p, name in (("components/one_time_tokens/core/common/one_time_token_features.cc", "kGmailOtpRetrievalService"),
                ("components/sharing_message/features.cc", "kOneTimeTokenBackendNotification")):
    edit(p, "BASE_FEATURE(%s,\n" % name + COND,
         "// Iris (apply-gmail-otp-off): off on every platform.\n"
         "BASE_FEATURE(%s, base::FEATURE_DISABLED_BY_DEFAULT);\n" % name,
         "// Iris (apply-gmail-otp-off)", name + " off")
PY
echo "=== Gmail one-time codes off complete ==="
