#!/usr/bin/env bash
# Iris — Android: shadow call stack for the arm64 TARGET only (2026-09-30).
# build/args-android.gn sets enable_shadow_call_stack = true (Vanadium 0015). A gn arg applies to every toolchain,
# including the host (x64 Linux) toolchain that builds tools, where //build/config/compiler asserts is_android.
# Restrict the SCS block to Android arm64; Linux toolchains are unaffected (the flag is false for them anyway).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "build/config/compiler/BUILD.gn"
s = open(p).read()
old = "    if (enable_shadow_call_stack) {\n"
new = "    if (enable_shadow_call_stack && is_android && current_cpu == \"arm64\") {  # Iris: target only\n"
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write("ERROR: %s: SCS block not found exactly once (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   %s : shadow call stack only for the Android arm64 target" % p)
PY
