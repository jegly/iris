#!/usr/bin/env bash
# Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
# Iris — Android: target SDK 37 (Android 17) instead of Chromium 157's default 36 (jegly 2026-11-07: "has to be
# target sdk 37"). An app targeting 37 gets Android 17's newer security/privacy restrictions applied to it.
# The APK already compiles against SDK 37 (public_android_sdk_platform_version 37.2); only the target changes.
# Upstream Chromium 157 does not target 37 yet: everything Android 17 changes for target-37 apps is untested
# upstream -> test the APK on the phone (start-up, downloads, notifications, file picker, media, background tabs,
# picture-in-picture, app lock, Exit) before signing.
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

p = "build/config/android/config.gni"
M = "    # Iris: target SDK 37 (apply-android-target-sdk-37.sh)\n"
edit(p, "  if (!defined(default_target_sdk_version)) {\n    default_target_sdk_version = \"36\"\n  }\n",
     "  if (!defined(default_target_sdk_version)) {\n" + M + "    default_target_sdk_version = \"37\"\n  }\n",
     M, "default_target_sdk_version 37")
PY
