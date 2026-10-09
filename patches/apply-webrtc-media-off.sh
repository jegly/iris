#!/usr/bin/env bash
# Iris — WebRTC family removed completely: also navigator.mediaDevices, getUserMedia, webkitGetUserMedia
# (jegly 2026-10-09: "we dont want our browser to have the webrtc api, it has a huge attack surface"; a browserleaks.com
# WebRTC test still reported "Media Devices: API Support True"; verified against 156.0.8078.11).
# apply-webrtc-off.sh already removes RTCPeerConnection (+ webkit alias) behind the Blink runtime feature IrisWebRTC (test =
# off in release). What stayed was the other door into the same stack: navigator.mediaDevices (enumerateDevices,
# getUserMedia, getDisplayMedia, ...) and the legacy navigator.getUserMedia / webkitGetUserMedia. Capture feeds
# libwebrtc's audio processing and the MediaStream machinery. These three members now carry RuntimeEnabled=IrisWebRTC too,
# so they are undefined in pages. Only IDL attributes change (the json5 feature already exists: no big Blink rebuild).
# Effect: no camera / microphone / screen-capture API for websites at all (video calls, voice recording, QR scanners that
# open the camera stop working). Settings -> Site settings camera/microphone rows stay but have nothing to ask for.
# Not changed: the WebRTC code stays compiled in (there is no gn switch) but nothing from web content can reach it.
# Re-enable for testing only: --enable-blink-features=IrisWebRTC
# Needs apply-webrtc-off.sh (defines IrisWebRTC). STATUS 2026-10-09: copy-tested only, NOT compile-proven (IDL bindings
# are generated at build time).
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
if 'name: "IrisWebRTC",' not in open("third_party/blink/renderer/platform/runtime_enabled_features.json5").read():
    die("IrisWebRTC runtime feature missing (run apply-webrtc-off.sh first)")
M = "third_party/blink/renderer/modules/mediastream/"
edit(M + "navigator_user_media.idl",
     "    [SameObject, SecureContext] readonly attribute MediaDevices mediaDevices;\n",
     "    // Iris: apply-webrtc-media-off.sh\n"
     "    [SameObject, SecureContext, RuntimeEnabled=IrisWebRTC] readonly attribute MediaDevices mediaDevices;\n",
     "RuntimeEnabled=IrisWebRTC] readonly attribute MediaDevices", "mediaDevices")
edit(M + "navigator_media_stream.idl",
     "    [RaisesException,\n     SecureContext,\n     MeasureAs=GetUserMediaLegacy\n",
     "    [RaisesException,\n     SecureContext,\n     RuntimeEnabled=IrisWebRTC,  // Iris: apply-webrtc-media-off.sh\n     MeasureAs=GetUserMediaLegacy\n",
     "RuntimeEnabled=IrisWebRTC,  // Iris", "getUserMedia")
edit(M + "navigator_media_stream.idl",
     "    [RaisesException,\n     SecureContext,\n     ImplementedAs=getUserMedia,\n",
     "    [RaisesException,\n     SecureContext,\n     RuntimeEnabled=IrisWebRTC,  // Iris: apply-webrtc-media-off.sh\n     ImplementedAs=getUserMedia,\n",
     "RuntimeEnabled=IrisWebRTC,  // Iris: apply-webrtc-media-off.sh\n     ImplementedAs", "webkitGetUserMedia")
PY
echo "=== WebRTC media APIs off complete ==="
