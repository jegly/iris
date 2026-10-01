#!/usr/bin/env bash
# Iris — compile the launcher's hardening switches INTO the binary (verified against checkout 2026-09-26).
# WHY: Android has no launcher wrapper, and release Android ignores command-line files
# (base/android/.../CommandLineInitUtil.java only reads them for debug apps / userdebug). Without this,
# the APK would ship WITHOUT --disable-background-networking and WITHOUT the 15 disabled web APIs.
# On desktop it also makes the protections hold when the binary is run directly (not via the launcher).
# (WebGPU is handled separately and compiled in by apply-webgpu-off.sh.)
# Also: --no-first-run on desktop (Vanadium 0063 equivalent; Android side in apply-vanadium-parity.sh).
#
# MECHANISM (verified):
# - chrome/app/chrome_main_delegate.cc ChromeMainDelegate::BasicStartupComplete() is "the earliest
#   callback" and already edits the command line (removes --disable-web-security). Android's
#   ChromeMainDelegateAndroid::BasicStartupComplete() calls it -> runs on BOTH platforms.
# - Injected in the BROWSER process only (no --type). Renderers get --disable-blink-features via
#   content/browser/renderer_host/render_process_host_impl.cc CopyFeatureSwitch().
# - content/common/content_switches_internal.cc FeaturesFromSwitch() merges EVERY
#   --disable-blink-features=... occurrence in argv, so a user/launcher value and ours combine.
# - Headers already included by chrome_main_delegate.cc: chrome/common/chrome_switches.h
#   (kDisableBackgroundNetworking) and content/public/common/content_switches.h
#   (kDisableBlinkFeatures, kProcessType).
# COMPILE-CHECK after applying (cheap once out/Linux is built — one object file):
#   autoninja -C out/Linux obj/chrome/app/chrome_main_delegate/chrome_main_delegate.o  (path: see ninja -t targets)
# Guarded insertion; idempotent (marker); fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
F=chrome/app/chrome_main_delegate.cc
MARKER='// Iris: compiled-in hardening switches'
# Keep IN SYNC with packaging/launcher/iris-launcher --disable-blink-features (checked below).
# 2026-09-26 Phase A: +26 APIs (Privacy Sandbox ads/topics/shared storage, built-in AI, WebNN, font access, ...).
#   Fledge is listed because AdInterestGroupAPI is `implied_by: Fledge` (stable) — disabling AdInterestGroupAPI alone
#   is a no-op. FileSystemAccess -> FileSystemAccessLocal: the pickers (window_file_system_access.idl) are gated on
#   FileSystemAccessLocal; "FileSystemAccess" is implied_by the stable FileSystemAccessOriginPrivate (OPFS), so the old
#   entry was a silent no-op. OPFS (navigator.storage.getDirectory) intentionally kept.
#   Limitation: origin-trial-controlled features (AdInterestGroupAPI, AIWriterAPI, AIRewriterAPI) can still be
#   re-enabled per-document by a valid origin-trial token (see runtime_enabled_features.cc.tmpl).
# 2026-09-27 (first dev-build self-test): +UnprefixedSpeechRecognition. window.SpeechRecognition (+ its event/grammar
#   interfaces) is gated on it; ScriptedSpeechRecognition only gates the webkit* aliases, so speech recognition stayed.
# 2026-10-01 (jegly: no screen capture): +GetDisplayMedia (screen sharing; 'stable' on desktop,
#   'experimental' = already off on Android).
BLINK_LIST='WebUSB,WebHID,Serial,WebBluetooth,WebNFC,WebXR,DirectSockets,FileSystemAccessLocal,Presentation,DevicePosture,ComputePressure,PushMessaging,WebShare,WakeLock,SystemWakeLock,Fledge,AdInterestGroupAPI,TopicsAPI,SharedStorageAPI,AIPromptAPI,AISummarizationAPI,TranslationAPI,LanguageDetectionAPI,AIWriterAPI,AIRewriterAPI,MachineLearningNeuralNetwork,FontAccess,InstalledApp,EyeDropperAPI,StorageBuckets,SubApps,WebAppLaunchQueue,BackgroundFetch,RemotePlayback,ScriptedSpeechRecognition,UnprefixedSpeechRecognition,WebIdentityDigitalCredentials,WebOTP,ContactsManager,ManagedConfiguration,NavigatorContentUtils,AnimationWorklet,GetDisplayMedia'
# Every name must be a RuntimeEnabledFeature (a wrong name is silently ignored) — checked below.

# --- guards: the mechanisms this relies on must still exist upstream ---
grep -q 'CopyFeatureSwitch(browser_cmd, renderer_cmd, switches::kDisableBlinkFeatures);' \
  content/browser/renderer_host/render_process_host_impl.cc || { echo "ERROR: renderer propagation of kDisableBlinkFeatures changed" >&2; exit 1; }
grep -q 'for (NativeStringView arg : command_line.argv())' content/common/content_switches_internal.cc \
  || { echo "ERROR: FeaturesFromSwitch no longer scans all argv occurrences" >&2; exit 1; }
for inc in '#include "chrome/common/chrome_switches.h"' '#include "content/public/common/content_switches.h"'; do
  grep -Fq "$inc" "$F" || { echo "ERROR: $F no longer includes $inc" >&2; exit 1; }
done
# launcher consistency (warn only — launcher is belt-and-braces on desktop)
L="$DIR/../packaging/launcher/iris-launcher"
if [ -f "$L" ]; then
  LL=$(grep -oE -- '--disable-blink-features=[^ \\]+' "$L" | head -1 | cut -d= -f2)
  [ "$LL" = "$BLINK_LIST" ] && echo "OK   launcher blink list matches" || echo "WARN launcher blink list differs from compiled-in list — sync them"
fi

J=third_party/blink/renderer/platform/runtime_enabled_features.json5
for f in ${BLINK_LIST//,/ }; do
  grep -qE "^\s*name: \"$f\"," "$J" || { echo "ERROR: $f is not a RuntimeEnabledFeature in $J (would be silently ignored)" >&2; exit 1; }
done

if grep -Fq -- "$MARKER" "$F"; then
  # Already inserted: upgrade the list literal in place if an older list is present (idempotent).
  python3 - "$F" "$BLINK_LIST" "$MARKER" <<'EOF'
import re, sys
f, lst, marker = sys.argv[1:4]
s = open(f).read()
i = s.find(marker)
m = re.compile(r'switches::kDisableBlinkFeatures,\s*"([^"]*)"').search(s, i)
if not m or m.start() - i > 2000: sys.stderr.write("ERROR: Iris kDisableBlinkFeatures literal not found\n"); sys.exit(1)
if m.group(1) == lst: print("SKIP already applied (list current): " + f); sys.exit(0)
open(f, "w").write(s[:m.start(1)] + lst + s[m.end(1):])
print("OK   %s : blink list upgraded (%d -> %d features)" % (f, len(m.group(1).split(",")), len(lst.split(","))))
EOF
  exit 0
fi

ANCHOR='#if !defined(BUILDING_CHROME_RENDERER)
  // The DevTools remote debugging pipe file descriptors need to be checked'
n=$(ANCHOR="$ANCHOR" perl -0777 -ne 'my $a=$ENV{ANCHOR}; my $c=()=/\Q$a\E/g; print $c' "$F")
[ "$n" -eq 1 ] || { echo "ERROR: insertion anchor found $n times (drift?)" >&2; exit 1; }

BLOCK="#if !defined(BUILDING_CHROME_RENDERER)
  $MARKER (mirror of packaging/launcher/iris-launcher).
  // Applies on Android (no launcher; release builds ignore command-line files) and when the binary
  // is run directly. Browser process only: renderers receive kDisableBlinkFeatures through
  // CopyFeatureSwitch(), and FeaturesFromSwitch() merges every occurrence, so any user-supplied
  // value is kept alongside these.
  if (!command_line.HasSwitch(switches::kProcessType)) {
    base::CommandLine* iris_command_line =
        base::CommandLine::ForCurrentProcess();
    iris_command_line->AppendSwitch(switches::kDisableBackgroundNetworking);
#if !BUILDFLAG(IS_ANDROID)
    // Desktop first-run (welcome/import prompts) off; Android handled in FirstRunStatus.java.
    iris_command_line->AppendSwitch(switches::kNoFirstRun);
#endif
    iris_command_line->AppendSwitchASCII(
        switches::kDisableBlinkFeatures,
        \"${BLINK_LIST}\");
  }
#endif  // !defined(BUILDING_CHROME_RENDERER)

"
ANCHOR="$ANCHOR" BLOCK="$BLOCK" perl -0777 -pi -e 'my($a,$b)=($ENV{ANCHOR},$ENV{BLOCK}); s/(\Q$a\E)/$b$1/;' "$F"
grep -Fq -- "$MARKER" "$F" && echo "OK   $F : compiled-in switches inserted" || { echo "ERROR: insert failed" >&2; exit 1; }
echo "=== default switches (compiled-in) complete ==="
