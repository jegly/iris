#!/usr/bin/env bash
# Iris — Phase A: NEW Blink gates for web APIs that had NO runtime feature (approved by jegly 2026-09-26;
# verified against checkout 2026-09-26). Same mechanism as apply-fingerprint-apis.sh / apply-webrtc-off.sh:
# a json5 runtime feature with status "test" (= OFF in release builds) + RuntimeEnabled=<it> on the IDL.
# Each gate covers the entry point AND the interface objects, so feature detection ('Keyboard' in window) agrees.
#   IrisScreenDetails        window.getScreenDetails(), ScreenDetails, ScreenDetailed, screen.isExtended
#                            (Window Management: multi-monitor layout = strong fingerprint; isExtended lives in
#                            core/frame/screen.idl — same spec, same bit of information)
#   IrisKeyboard             navigator.keyboard, Keyboard, KeyboardLayoutMap (layout map = locale/hardware fingerprint)
#   IrisBadging              navigator.setAppBadge/clearAppBadge (Window mixin + ServiceWorker partial)
#   IrisVibration            navigator.vibrate()
#   IrisWindowControlsOverlay navigator.windowControlsOverlay, WindowControlsOverlay, ...GeometryChangeEvent
#   IrisInk                  navigator.ink, Ink, DelegatedInkTrailPresenter
#   IrisBreakoutBox          MediaStreamTrackProcessor, MediaStreamTrackGenerator (VideoTrackGenerator is already
#                            status "test" upstream)
#   IrisNetInfo              navigator.connection (Window + Worker, via the mixin), NetworkInformation
#                            (Firefox/Safari don't ship it; downlink/rtt/effectiveType = fingerprint + tracking)
# RuntimeEnabled on an `interface mixin` is supported (upstream: GlobalPrivacyControl, StorageBuckets).
# Re-enable one for testing: --enable-blink-features=<Name>. Bindings are generated at build time ->
# prove with generate_bindings_all + the modules objects (build/proof-objects.txt method).
# JSON5 EDIT => large Blink rebuild; batched with the other json5 patches into the one dev build.
# Guarded; idempotent (markers); fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(path, old, new, marker):
    s = open(path).read()
    if marker in s: print("SKIP already applied: " + path + " (" + marker[:40] + ")"); return
    if s.count(old) != 1: die(f"{path}: expected 1 match, found {s.count(old)} (drift?): {old[:70]!r}")
    open(path, "w").write(s.replace(old, new)); print("OK   " + path)

GATES = ["IrisBadging", "IrisBreakoutBox", "IrisInk", "IrisKeyboard", "IrisNetInfo", "IrisScreenDetails",
         "IrisVibration", "IrisWindowControlsOverlay"]

# 1) json5: new features after IrisUAData (from apply-fingerprint-apis.sh, which runs earlier in apply-all.sh).
J = "third_party/blink/renderer/platform/runtime_enabled_features.json5"
anchor = '      name: "IrisUAData",\n      status: "test",\n      base_feature: "none",\n    },\n'
entries = "".join(f'    {{\n      // Iris (jegly): Phase A API gate. "test" = OFF in release builds.\n'
                  f'      name: "{n}",\n      status: "test",\n      base_feature: "none",\n    }},\n' for n in GATES)
edit(J, anchor, anchor + entries, 'name: "IrisBadging",')

B = "third_party/blink/renderer"
M = B + "/modules"
def gate_decl(path, old_head, new_head, name):
    edit(path, old_head, new_head, "RuntimeEnabled=" + name)

# 2) Window Management / screen details
gate_decl(f"{M}/screen_details/window_screen_details.idl",
          "[\n    SecureContext,\n    ImplementedAs=WindowScreenDetails\n] partial interface Window {",
          "[\n    SecureContext,\n    ImplementedAs=WindowScreenDetails,\n    RuntimeEnabled=IrisScreenDetails\n] partial interface Window {",
          "IrisScreenDetails")
gate_decl(f"{M}/screen_details/screen_details.idl",
          "[\n  Exposed=Window,\n  SecureContext\n] interface ScreenDetails : EventTarget {",
          "[\n  Exposed=Window,\n  SecureContext,\n  RuntimeEnabled=IrisScreenDetails\n] interface ScreenDetails : EventTarget {",
          "IrisScreenDetails")
gate_decl(f"{M}/screen_details/screen_detailed.idl",
          "[\n  Exposed=Window,\n  SecureContext\n] interface ScreenDetailed : Screen {",
          "[\n  Exposed=Window,\n  SecureContext,\n  RuntimeEnabled=IrisScreenDetails\n] interface ScreenDetailed : Screen {",
          "IrisScreenDetails")
gate_decl(f"{B}/core/frame/screen.idl",
          "[SecureContext, MeasureAs=WindowScreenIsExtended] readonly attribute boolean isExtended;",
          "[SecureContext, MeasureAs=WindowScreenIsExtended, RuntimeEnabled=IrisScreenDetails] readonly attribute boolean isExtended;",
          "IrisScreenDetails")

# 3) Keyboard (lock + layout map)
gate_decl(f"{M}/keyboard/navigator_keyboard.idl",
          "[\n    ImplementedAs=NavigatorKeyboard\n] partial interface Navigator {",
          "[\n    ImplementedAs=NavigatorKeyboard,\n    RuntimeEnabled=IrisKeyboard\n] partial interface Navigator {",
          "IrisKeyboard")
gate_decl(f"{M}/keyboard/keyboard.idl",
          "[\n    Exposed=Window,\n    SecureContext\n] interface Keyboard {",
          "[\n    Exposed=Window,\n    SecureContext,\n    RuntimeEnabled=IrisKeyboard\n] interface Keyboard {",
          "IrisKeyboard")
gate_decl(f"{M}/keyboard/keyboard_layout_map.idl",
          "[\n    Exposed=Window,\n    SecureContext\n] interface KeyboardLayoutMap {",
          "[\n    Exposed=Window,\n    SecureContext,\n    RuntimeEnabled=IrisKeyboard\n] interface KeyboardLayoutMap {",
          "IrisKeyboard")

# 4) Badging (Window mixin + ServiceWorker partial)
gate_decl(f"{M}/badging/navigator_badge.idl",
          "[\n    SecureContext\n] interface mixin NavigatorBadge {",
          "[\n    SecureContext,\n    RuntimeEnabled=IrisBadging\n] interface mixin NavigatorBadge {",
          "IrisBadging")
gate_decl(f"{M}/badging/worker_navigator_badge.idl",
          "[\n    SecureContext,\n    ImplementedAs=NavigatorBadge\n] partial interface WorkerNavigator {",
          "[\n    SecureContext,\n    ImplementedAs=NavigatorBadge,\n    RuntimeEnabled=IrisBadging\n] partial interface WorkerNavigator {",
          "IrisBadging")

# 5) Vibration
gate_decl(f"{M}/vibration/navigator_vibration.idl",
          "[\n    ImplementedAs=VibrationController\n] partial interface Navigator {",
          "[\n    ImplementedAs=VibrationController,\n    RuntimeEnabled=IrisVibration\n] partial interface Navigator {",
          "IrisVibration")

# 6) Window Controls Overlay
W = f"{M}/window_controls_overlay"
gate_decl(f"{W}/navigator_window_controls_overlay.idl",
          "[\n    ImplementedAs=WindowControlsOverlay\n] partial interface Navigator {",
          "[\n    ImplementedAs=WindowControlsOverlay,\n    RuntimeEnabled=IrisWindowControlsOverlay\n] partial interface Navigator {",
          "IrisWindowControlsOverlay")
gate_decl(f"{W}/window_controls_overlay.idl",
          "[\n    Exposed=Window\n] interface WindowControlsOverlay : EventTarget {",
          "[\n    Exposed=Window,\n    RuntimeEnabled=IrisWindowControlsOverlay\n] interface WindowControlsOverlay : EventTarget {",
          "IrisWindowControlsOverlay")
gate_decl(f"{W}/window_controls_overlay_geometry_change_event.idl",
          "[\n    Exposed=Window\n] interface WindowControlsOverlayGeometryChangeEvent : Event {",
          "[\n    Exposed=Window,\n    RuntimeEnabled=IrisWindowControlsOverlay\n] interface WindowControlsOverlayGeometryChangeEvent : Event {",
          "IrisWindowControlsOverlay")

# 7) Delegated ink
gate_decl(f"{M}/delegated_ink/navigator_ink.idl",
          "[\n    ImplementedAs=Ink,\n    Exposed=Window\n] partial interface Navigator {",
          "[\n    ImplementedAs=Ink,\n    Exposed=Window,\n    RuntimeEnabled=IrisInk\n] partial interface Navigator {",
          "IrisInk")
gate_decl(f"{M}/delegated_ink/ink.idl",
          "[\n    Exposed=Window\n] interface Ink {",
          "[\n    Exposed=Window,\n    RuntimeEnabled=IrisInk\n] interface Ink {",
          "IrisInk")
gate_decl(f"{M}/delegated_ink/delegated_ink_trail_presenter.idl",
          "[\n    Exposed=Window\n] interface DelegatedInkTrailPresenter {",
          "[\n    Exposed=Window,\n    RuntimeEnabled=IrisInk\n] interface DelegatedInkTrailPresenter {",
          "IrisInk")

# 8) Breakout box (insertable streams for raw media)
gate_decl(f"{M}/breakout_box/media_stream_track_processor.idl",
          "[\n    Exposed=Window\n]\ninterface MediaStreamTrackProcessor {",
          "[\n    Exposed=Window,\n    RuntimeEnabled=IrisBreakoutBox\n]\ninterface MediaStreamTrackProcessor {",
          "IrisBreakoutBox")
gate_decl(f"{M}/breakout_box/media_stream_track_generator.idl",
          "[\n    Exposed=Window\n]\ninterface MediaStreamTrackGenerator : MediaStreamTrack {",
          "[\n    Exposed=Window,\n    RuntimeEnabled=IrisBreakoutBox\n]\ninterface MediaStreamTrackGenerator : MediaStreamTrack {",
          "IrisBreakoutBox")

# 9) Network Information
gate_decl(f"{M}/netinfo/navigator_network_information.idl",
          "[\n    ImplementedAs=NetworkInformation\n] interface mixin NavigatorNetworkInformation {",
          "[\n    ImplementedAs=NetworkInformation,\n    RuntimeEnabled=IrisNetInfo\n] interface mixin NavigatorNetworkInformation {",
          "IrisNetInfo")
PY
# NetworkInformation interface header varies in shape -> separate guarded edit with a check.
N=third_party/blink/renderer/modules/netinfo/network_information.idl
if grep -q 'RuntimeEnabled=IrisNetInfo' "$N"; then echo "SKIP already applied: $N"
else
  python3 - "$N" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
m = re.findall(r'\[([^\[\]]*)\]\s*interface NetworkInformation\s*:\s*EventTarget', s)
if len(m) != 1: sys.stderr.write("ERROR: NetworkInformation interface header not found exactly once\n"); sys.exit(1)
old = m[0]; new = old.rstrip() + ",\n    RuntimeEnabled=IrisNetInfo\n"
s = s.replace("[" + old + "]", "[" + new + "]", 1); open(p, "w").write(s); print("OK   " + p)
PY
fi
echo "=== Phase A new API gates complete ==="
