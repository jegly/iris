#!/usr/bin/env bash
# Iris — actually remove navigator.wakeLock (found by the first self-test run, 2026-09-27; verified against this checkout).
# The compiled-in --disable-blink-features list (apply-default-switches.sh) has contained WakeLock + SystemWakeLock since
# 2026-09-25, but modules/wake_lock/navigator_wake_lock.idl carries NO RuntimeEnabled gate, so the property stayed on
# every page (third silent no-op after AdInterestGroupAPI/Fledge and FileSystemAccess; see memory/01_GOTCHAS.md).
# The WakeLock / WakeLockSentinel interface objects are already tied to the flag on Window via
# Exposed(... Window WakeLock), so only the navigator attribute needs the gate. The flag exists in json5 -> NO json5 edit,
# only the bindings regenerate (v8_navigator).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "third_party/blink/renderer/modules/wake_lock/navigator_wake_lock.idl"
s = open(p).read()
old = "[\n  ImplementedAs=WakeLock,\n  SecureContext\n] partial interface Navigator {"
new = "[\n  ImplementedAs=WakeLock,\n  SecureContext,\n  RuntimeEnabled=WakeLock\n] partial interface Navigator {"
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write(f"ERROR: {p}: Navigator partial header changed (drift?)\n"); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : navigator.wakeLock gated on WakeLock")
j = open("third_party/blink/renderer/platform/runtime_enabled_features.json5").read()
if 'name: "WakeLock",' not in j: sys.stderr.write("ERROR: json5 no longer defines WakeLock\n"); sys.exit(1)
PY
echo "=== wake lock gate complete ==="
