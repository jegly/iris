#!/usr/bin/env bash
# Iris — Google Cloud Messaging (GCM/FCM) never starts (found 2026-09-27 in a startup log: "registration_request.cc
# ... DEPRECATED_ENDPOINT"; verified against this checkout).
# What a fresh profile did at startup (captured with --vmodule=*gcm*=2): a device CHECK-IN with Google (a persistent
# Google-issued Android ID + security token saved in <profile>/GCM Store), then registrations at
# https://android.clients.google.com/c2dm/register3 for com.google.android.gms and two
# com.google.chrome.fcm.invalidations-* channels, signed "AidLogin <android id>". A stable device identifier.
# Fix: GCMDriverDesktop::EnsureStarted() (components/gcm_driver/gcm_driver_desktop.cc) is the only place the GCM
# client is started (posts IOWorker::Start); every caller already handles a non-SUCCESS result by failing that request.
# It now always returns GCMClient::GCM_DISABLED (an existing result) -> no check-in, no registration, no connection.
# Consequences: nothing Iris uses (Push API is already off; sync/policy invalidations need sign-in/MDM, both absent);
# extensions using chrome.gcm / chrome.instanceID get a clean "disabled" error.
# Whole body replaced (not an early return: -Wunreachable-code-aggressive). Guarded; idempotent; fails on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "components/gcm_driver/gcm_driver_desktop.cc"
s = open(p).read()
start = "GCMClient::Result GCMDriverDesktop::EnsureStarted(\n    GCMClient::StartMode start_mode) {\n"
marker = "// Iris: GCM never starts"
if marker in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(start) != 1: sys.stderr.write("ERROR: %s: EnsureStarted signature changed (drift?)\n" % p); sys.exit(1)
i = s.index(start); j = s.index("\n}\n", i) + 3
body = s[i:j]
for must in ("if (app_handlers().empty())", "IOWorker::Start", "return GCMClient::SUCCESS;"):
    if must not in body: sys.stderr.write("ERROR: %s: EnsureStarted body changed (%s missing)\n" % (p, must)); sys.exit(1)
new = (start +
       "  DCHECK(ui_thread_->RunsTasksInCurrentSequence());\n"
       "  // Iris: GCM never starts — no device check-in with Google, no registration,\n"
       "  // no connection. Callers treat GCM_DISABLED as a failed request.\n"
       "  return GCMClient::GCM_DISABLED;\n"
       "}\n")
open(p, "w").write(s[:i] + new + s[j:]); print("OK   " + p + " : GCM never starts (EnsureStarted -> GCM_DISABLED)")
PY
echo "=== GCM off complete ==="
