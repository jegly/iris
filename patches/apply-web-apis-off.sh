#!/usr/bin/env bash
# Iris — more web APIs removed from web content (jegly 2026-10-09: "yes i want them all removed, i want geolocation api
# removed as well"; reason: attack surface; verified against 156.0.8078.11). Needs apply-webrtc-off.sh (defines the Blink
# runtime feature IrisWebRTC, "test" = OFF in release builds, reused here as Iris's "removed API" switch).
# Gated behind IrisWebRTC (IDL RuntimeEnabled edits; no json5 change, so no Blink-wide rebuild):
#   MediaRecorder                      records a stream into a file in the page
#   HTMLCanvasElement/HTMLMediaElement.captureStream()   turns a canvas / video element into a live stream
#   WebCodecs entry points: VideoDecoder, VideoEncoder, AudioDecoder, AudioEncoder, ImageDecoder (the codec constructors;
#                                      VideoFrame / AudioData / EncodedChunk stay as inert data holders)
#   WebTransport                       two-way low-latency connections over HTTP/3
#   navigator.geolocation              the Geolocation API (permission default was already "Not allowed")
# Switched off with the compiled-in --disable-blink-features list (apply-default-switches.sh + the launcher; existing
# Blink features, so no rebuild beyond the switch):
#   FileSystem                         legacy webkitRequestFileSystem (window + shared workers)
#   GeolocationElement                 the <geolocation> permission element
# Effect: those names are undefined in pages (feature detection says "not supported"). Re-enable for testing only:
#   --enable-blink-features=IrisWebRTC
# STATUS 2026-10-09: copy-tested only, NOT compile-proven (IDL bindings are generated at build time).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
if 'name: "IrisWebRTC",' not in open("third_party/blink/renderer/platform/runtime_enabled_features.json5").read():
    die("IrisWebRTC runtime feature missing (run apply-webrtc-off.sh first)")
R = "third_party/blink/renderer/"
MARK = "RuntimeEnabled=IrisWebRTC"

def gate_interface(path, iface):
    s = open(path).read()
    if re.search(r"\]\s*interface %s\b" % iface, s) and MARK in s.split("interface %s" % iface)[0]:
        print("SKIP already applied: %s (%s)" % (path, iface)); return
    m = re.search(r"\n(\s*)([^\n]*?)(\n)\](\s*interface %s\b)" % iface, s)
    if not m: die("%s: '] interface %s' attribute block not found (drift?)" % (path, iface))
    last = m.group(2)
    if last.rstrip().endswith("//") or "//" in last: die("%s: last attribute line has a comment" % path)
    new = "\n%s%s,\n%s%s\n]%s" % (m.group(1), last, m.group(1), MARK, m.group(4))
    s = s[:m.start()] + new + s[m.end():]
    open(path, "w").write(s); print("OK   %s : %s gated" % (path, iface))

def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

for f, i in (("modules/mediarecorder/media_recorder.idl", "MediaRecorder"),
             ("modules/webcodecs/video_decoder.idl", "VideoDecoder"),
             ("modules/webcodecs/video_encoder.idl", "VideoEncoder"),
             ("modules/webcodecs/audio_decoder.idl", "AudioDecoder"),
             ("modules/webcodecs/audio_encoder.idl", "AudioEncoder"),
             ("modules/webcodecs/image_decoder.idl", "ImageDecoder"),
             ("modules/webtransport/web_transport.idl", "WebTransport")):
    gate_interface(R + f, i)

edit(R + "modules/mediacapturefromelement/html_canvas_element_capture.idl",
     "    [MeasureAs=CanvasCaptureStream, RaisesException, CallWith=ScriptState] MediaStream captureStream",
     "    [RuntimeEnabled=IrisWebRTC, MeasureAs=CanvasCaptureStream, RaisesException, CallWith=ScriptState] MediaStream captureStream",
     "RuntimeEnabled=IrisWebRTC, MeasureAs=CanvasCaptureStream", "canvas captureStream")
edit(R + "modules/mediacapturefromelement/html_media_element_capture.idl",
     "    [RaisesException, Measure, CallWith=ScriptState] MediaStream captureStream();",
     "    [RuntimeEnabled=IrisWebRTC, RaisesException, Measure, CallWith=ScriptState] MediaStream captureStream();",
     "RuntimeEnabled=IrisWebRTC, RaisesException, Measure", "media captureStream")
edit(R + "core/geolocation/navigator_geolocation.idl",
     "    readonly attribute Geolocation geolocation;\n",
     "    [RuntimeEnabled=IrisWebRTC] readonly attribute Geolocation geolocation;\n",
     "[RuntimeEnabled=IrisWebRTC] readonly attribute Geolocation", "navigator.geolocation")
PY
echo "=== more web APIs off complete ==="
