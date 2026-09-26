#!/usr/bin/env bash
# Iris — remove fingerprinting-prone web APIs (verified against checkout 2026-09-26). Ideas from Cromite;
# our own code. Mechanism = Blink runtime features set to status "test" (OFF in release builds):
#   existing features flipped stable -> test:
#     ScriptedSpeechSynthesis  -> window.speechSynthesis gone (voice list = strong fingerprint)
#     FetchLaterAPI            -> fetchLater() gone (deferred tracking beacons)
#   new gates (json5 feature + RuntimeEnabled= on the IDL, same pattern as apply-webrtc-off.sh):
#     IrisBatteryStatus -> navigator.getBattery() gone
#     IrisGamepad       -> navigator.getGamepads() gone
#     IrisBeacon        -> navigator.sendBeacon() gone (analytics/tracking pings)
#     IrisUAData        -> navigator.userAgentData gone ENTIRELY (incl. getHighEntropyValues()).
#                          Hiding the whole object makes Iris look like Firefox/Safari, which never had it —
#                          every site (Google login included) already handles its absence. Removing only the
#                          method could break sites that assume Chromium => userAgentData.getHighEntropyValues.
#   NOT covered here: the Sec-CH-UA request headers (network side) — tracked separately.
# Re-enable any one for testing: --enable-blink-features=<Name>
# Bindings are generated at build time -> prove in out/Default or an incremental out/Linux build.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

python3 - <<'PY'
import sys, re
def die(m): sys.stderr.write("ERROR: "+m+"\n"); sys.exit(1)
def edit(path, old, new, marker):
    s = open(path).read()
    if marker in s: print("SKIP already applied: "+path+" ("+marker[:40]+")"); return
    if s.count(old) != 1: die(f"{path}: expected 1 match, found {s.count(old)} (drift?): {old[:60]!r}")
    open(path,"w").write(s.replace(old,new)); print("OK   "+path)

J = "third_party/blink/renderer/platform/runtime_enabled_features.json5"
# 1) new runtime features (status test), inserted before JavaScriptCompileHintsPerFunctionMagicRuntime
anchor = '    {\n      name: "JavaScriptCompileHintsPerFunctionMagicRuntime",'
entries = "".join(f'    {{\n      // Iris (jegly): fingerprinting API gate. "test" = OFF in release builds.\n      name: "{n}",\n      status: "test",\n      base_feature: "none",\n    }},\n'
                  for n in ["IrisBatteryStatus","IrisBeacon","IrisGamepad","IrisUAData"])
edit(J, anchor, entries + anchor, 'name: "IrisBatteryStatus",')
# 2) existing features stable -> test
edit(J, 'name: "ScriptedSpeechSynthesis",\n      public: true,\n      status: "stable",',
        'name: "ScriptedSpeechSynthesis",\n      public: true,\n      status: "test",',
        'name: "ScriptedSpeechSynthesis",\n      public: true,\n      status: "test",')
edit(J, 'name: "FetchLaterAPI",\n      status: "stable",',
        'name: "FetchLaterAPI",\n      status: "test",',
        'name: "FetchLaterAPI",\n      status: "test",')

M = "third_party/blink/renderer/modules"
# 3) IDL gates
edit(f"{M}/battery/navigator_battery.idl",
     "[SecureContext, ImplementedAs=BatteryManager]\npartial interface Navigator {",
     "[SecureContext, ImplementedAs=BatteryManager, RuntimeEnabled=IrisBatteryStatus]\npartial interface Navigator {",
     "RuntimeEnabled=IrisBatteryStatus")
edit(f"{M}/gamepad/navigator_gamepad.idl",
     "[\n    ImplementedAs=NavigatorGamepad\n] partial interface Navigator {",
     "[\n    ImplementedAs=NavigatorGamepad,\n    RuntimeEnabled=IrisGamepad\n] partial interface Navigator {",
     "RuntimeEnabled=IrisGamepad")
edit(f"{M}/beacon/navigator_beacon.idl",
     "[\n    ImplementedAs=NavigatorBeacon\n] partial interface Navigator {",
     "[\n    ImplementedAs=NavigatorBeacon,\n    RuntimeEnabled=IrisBeacon\n] partial interface Navigator {",
     "RuntimeEnabled=IrisBeacon")
edit("third_party/blink/renderer/core/frame/navigator_ua.idl",
     "[SecureContext] readonly attribute NavigatorUAData userAgentData;",
     "[SecureContext, RuntimeEnabled=IrisUAData] readonly attribute NavigatorUAData userAgentData;",
     "RuntimeEnabled=IrisUAData")
PY
echo "=== fingerprinting APIs off complete ==="
