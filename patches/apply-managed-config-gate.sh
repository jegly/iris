#!/usr/bin/env bash
# Iris — actually remove navigator.managed (found by the first self-test run, 2026-09-27; verified against this checkout).
# ManagedConfiguration has been in the compiled-in --disable-blink-features list since 2026-09-26, but
# modules/managed_device/navigator_managed.idl carries NO RuntimeEnabled gate: every page still had navigator.managed
# (an empty NavigatorManagedData object; its methods are gated on ManagedConfiguration / DeviceAttributes). Fourth
# silent no-op of this kind (see memory/01_GOTCHAS.md). Enterprise-managed-device APIs have no place in Iris (no MDM).
# Gate = ManagedConfiguration: hides the attribute whenever that feature is off, which also covers DeviceAttributes
# (its methods live on the same object; "experimental" = off outside ChromeOS). The flag exists in json5 -> NO json5
# edit, only the bindings regenerate (v8_navigator).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "third_party/blink/renderer/modules/managed_device/navigator_managed.idl"
s = open(p).read()
old = "[\n  ImplementedAs=NavigatorManagedData,\n  SecureContext\n] partial interface Navigator {"
new = "[\n  ImplementedAs=NavigatorManagedData,\n  SecureContext,\n  RuntimeEnabled=ManagedConfiguration\n] partial interface Navigator {"
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write(f"ERROR: {p}: Navigator partial header changed (drift?)\n"); sys.exit(1)
j = open("third_party/blink/renderer/platform/runtime_enabled_features.json5").read()
if 'name: "ManagedConfiguration",' not in j: sys.stderr.write("ERROR: json5 no longer defines ManagedConfiguration\n"); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : navigator.managed gated on ManagedConfiguration")
PY
echo "=== managed configuration gate complete ==="
