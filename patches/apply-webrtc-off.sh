#!/usr/bin/env bash
# Iris — remove WebRTC from web content (verified against checkout 2026-09-26). jegly: "I will never use it".
# There is no gn arg for WebRTC and RTCPeerConnection is exposed unconditionally (Exposed=Window +
# LegacyWindowAlias=webkitRTCPeerConnection). This adds a Blink runtime feature `IrisWebRTC` with
# status "test" (OFF in release builds) and gates RTCPeerConnection AND its webkit alias on it —
# the same pattern Chromium uses for SpeechRecognition (RuntimeEnabled + LegacyWindowAlias_RuntimeEnabled,
# third_party/blink/renderer/modules/speech/speech_recognition.idl).
# Effect: `RTCPeerConnection` / `webkitRTCPeerConnection` are undefined -> no peer connections, no ICE
# gathering -> no WebRTC local-IP leak and no WebRTC network stack reachable from pages. Every other RTC*
# object is only obtainable through a peer connection. (Camera/mic capture = getUserMedia is separate;
# it's governed by the camera/mic content settings.)
# Re-enable for testing only: --enable-blink-features=IrisWebRTC
# COMPILE-CHECK after applying: bindings are generated at build time — prove in out/Default first.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
J=third_party/blink/renderer/platform/runtime_enabled_features.json5
IDL=third_party/blink/renderer/modules/peerconnection/rtc_peer_connection.idl

# 1) runtime feature (inserted alphabetically, before JavaScriptCompileHintsPerFunctionMagicRuntime)
if grep -q 'name: "IrisWebRTC",' "$J"; then echo "SKIP already applied: $J"
else
  ANCHOR='    {
      name: "JavaScriptCompileHintsPerFunctionMagicRuntime",'
  n=$(ANCHOR="$ANCHOR" perl -0777 -ne 'my $a=$ENV{ANCHOR}; my $c=()=/\Q$a\E/g; print $c' "$J")
  [ "$n" -eq 1 ] || { echo "ERROR: json5 anchor found $n times (drift?)" >&2; exit 1; }
  ENTRY='    {
      // Iris (jegly): gates RTCPeerConnection. "test" = OFF in release builds.
      name: "IrisWebRTC",
      status: "test",
      base_feature: "none",
    },
'
  ANCHOR="$ANCHOR" ENTRY="$ENTRY" perl -0777 -pi -e 'my($a,$e)=($ENV{ANCHOR},$ENV{ENTRY}); s/(\Q$a\E)/$e$1/;' "$J"
  echo "OK   $J : IrisWebRTC runtime feature added (status test)"
fi

# 2) gate the interface + legacy alias
OLD='[
    ActiveScriptWrappable,
    Exposed=Window,
    LegacyWindowAlias=webkitRTCPeerConnection,
    LegacyWindowAlias_Measure
] interface RTCPeerConnection : EventTarget {'
NEW='[
    ActiveScriptWrappable,
    Exposed=Window,
    RuntimeEnabled=IrisWebRTC,
    LegacyWindowAlias=webkitRTCPeerConnection,
    LegacyWindowAlias_Measure,
    LegacyWindowAlias_RuntimeEnabled=IrisWebRTC
] interface RTCPeerConnection : EventTarget {'
if grep -q 'RuntimeEnabled=IrisWebRTC,' "$IDL"; then echo "SKIP already applied: $IDL"
else
  n=$(OLD="$OLD" perl -0777 -ne 'my $o=$ENV{OLD}; my $c=()=/\Q$o\E/g; print $c' "$IDL")
  [ "$n" -eq 1 ] || { echo "ERROR: RTCPeerConnection attribute block found $n times (drift?)" >&2; exit 1; }
  OLD="$OLD" NEW="$NEW" perl -0777 -pi -e 'my($o,$w)=($ENV{OLD},$ENV{NEW}); s/\Q$o\E/$w/;' "$IDL"
  echo "OK   $IDL : RTCPeerConnection + webkit alias gated on IrisWebRTC"
fi
echo "=== WebRTC off complete ==="
