#!/usr/bin/env bash
# Iris — slim the web platform further (jegly 2026-10-09: API-surface audit, "see about slimming it down"; verified
# against 156.0.8078.11). The audit (Iris 0.0.0.6 vs Brave 155 vs Firefox 157, same test page) found interface objects
# that stay visible to pages after Iris switched their feature off, plus a few APIs to drop entirely:
#   WebGPU            navigator.gpu + all GPU* / WGSL* interfaces (the WebGPU service was already off: no adapter,
#                     but the objects were still there)
#   Generic Sensors   Accelerometer, Gyroscope, GravitySensor, LinearAccelerationSensor, orientation sensors, Sensor
#   Device motion     DeviceMotionEvent, DeviceOrientationEvent and their window handlers
#   Web MIDI          navigator.requestMIDIAccess + MIDI* interfaces
#   Idle Detection, VirtualKeyboard (+ navigator.virtualKeyboard), ImageCapture, BatteryManager
#   WebXR leftovers   XRLayer, XRDOMOverlayState, XRWebGLBinding (WebXR itself is off via the blink list)
#   Capture leftovers MediaStreamTrack audio/video stats, CropTarget, RestrictionTarget, BrowserCaptureMediaStreamTrack,
#                     CanvasCaptureMediaStreamTrack, InputDeviceInfo (getUserMedia/getDisplayMedia are already gone),
#                     AudioSinkInfo (2026-10-10)
#   Ad tech / misc    ProtectedAudience, background sync (SyncManager + registration.sync), the JS self-profiler
#                     (Profiler), InputDeviceCapabilities, the AI CreateMonitor, managed-device data, NavigatorUAData
# Mechanism: like apply-web-apis-off.sh, IDL RuntimeEnabled=IrisWebRTC (Iris's "removed API" Blink feature, OFF in
# release builds) on each top-level interface / partial interface that has no runtime gate yet; interfaces that are
# already gated by another feature are left as they are. Mixins are not gated; navigator.gpu (a mixin attribute) is
# gated on the attribute. Instances returned by still-exposed APIs keep working; only the global names disappear.
# Features that already have their own Blink runtime switch are added to the compiled-in --disable-blink-features
# list instead (apply-default-switches.sh): CameraAndMicrophoneElements, UserMediaElement, FencedFrames,
# PeriodicBackgroundSync, CaptureController, CrashReportingStorageAPI, FileSystemObserver, WebSpeechRecognitionContext.
# Re-enable for testing only: --enable-blink-features=IrisWebRTC
# Needs apply-webrtc-off.sh (defines IrisWebRTC). STATUS 2026-10-09: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import glob, os, re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
R = "third_party/blink/renderer/"
if 'name: "IrisWebRTC",' not in open(R + "platform/runtime_enabled_features.json5").read():
    die("IrisWebRTC runtime feature missing (run apply-webrtc-off.sh first)")
GATE = "RuntimeEnabled=IrisWebRTC"
DEF = re.compile(r"(?:(?<=\n)|^)(?P<attrs>\[[^\[\]]*\]\s*)?(?P<partial>partial\s+)?interface\s+(?!mixin\b)(?P<name>\w+)")

def gate_file(path):
    """Gates every top-level (partial) interface in `path` that has no runtime gate. Returns (gated, already)."""
    s = open(path).read()
    out, pos, gated, already = [], 0, 0, 0
    for m in DEF.finditer(s):
        attrs = m.group("attrs")
        if attrs and "RuntimeEnabled" in attrs:
            already += 1 if GATE in attrs else 0
            continue
        out.append(s[pos:m.start()])
        if attrs:
            out.append("[" + GATE + ", " + attrs[1:])
            out.append(s[m.start() + len(attrs):m.end()])
        else:
            out.append("[" + GATE + "] " + s[m.start():m.end()])
        pos = m.end()
        gated += 1
    if gated:
        out.append(s[pos:])
        open(path, "w").write("".join(out))
    return gated, already

FILES = []
for d in ("webgpu", "sensor", "device_orientation", "webmidi", "idle", "virtualkeyboard", "imagecapture"):
    files = sorted(glob.glob(R + "modules/%s/*.idl" % d))
    if not files: die("no IDL files in modules/%s (drift?)" % d)
    FILES += files
FILES += [R + f for f in (
    "modules/battery/battery_manager.idl",
    "modules/xr/xr_layer.idl", "modules/xr/xr_dom_overlay_state.idl", "modules/xr/xr_webgl_binding.idl",
    "modules/mediastream/media_stream_track_audio_stats.idl", "modules/mediastream/media_stream_track_video_stats.idl",
    "modules/mediastream/crop_target.idl", "modules/mediastream/restriction_target.idl",
    "modules/mediastream/browser_capture_media_stream_track.idl", "modules/mediastream/input_device_info.idl",
    "modules/mediacapturefromelement/canvas_capture_media_stream_track.idl",
    "modules/webaudio/audio_sink_info.idl",
    "modules/ad_auction/protected_audience.idl",
    "modules/background_sync/sync_manager.idl", "modules/background_sync/service_worker_registration_sync.idl",
    "modules/ai/create_monitor.idl",
    "modules/managed_device/navigator_managed_data.idl", "modules/managed_device/navigator_managed.idl",
    "core/timing/profiler.idl", "core/input/input_device_capabilities.idl", "core/frame/navigator_ua_data.idl")]
total_g = total_a = 0
for f in FILES:
    if not os.path.exists(f): die(f + " missing (drift?)")
    g, a = gate_file(f)
    total_g += g; total_a += a
print("OK   IDL gates: %d added, %d already present (%d files)" % (total_g, total_a, len(FILES)))

# navigator.gpu lives in an interface mixin: gate the attribute itself.
p = R + "modules/webgpu/navigator_gpu.idl"
s = open(p).read()
old = "    [SameObject, SecureContext] readonly attribute GPU gpu;\n"
new = "    [SameObject, SecureContext, " + GATE + "] readonly attribute GPU gpu;\n"
if new in s: print("SKIP already applied: " + p + " (navigator.gpu)")
elif s.count(old) == 1: open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : navigator.gpu gated")
else: die(p + ": navigator.gpu attribute not found (drift?)")
PY
echo "=== more web APIs off (2) complete ==="
