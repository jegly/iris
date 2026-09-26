#!/usr/bin/env bash
# Iris — feature defaults from jegly's Android chrome://flags review (verified against checkout 2026-09-26).
# Only the flags whose DEFAULT differs from what jegly wants are patched here; the rest were already
# default / already in Iris / moot (see memory/02_DECISIONS.md "2026-09-26 flags review").
#   ON : Rusty ICO + Rusty JPEG decoders (memory-safe Rust instead of C/C++; BMP is already Rust-only here)
#   ON : strict site isolation on ANDROID (kSitePerProcess; desktop already ON). Android's memory
#        threshold (components/site_isolation) still turns it off on very-low-RAM devices.
#   OFF: Collaboration Messaging (Google tab-group sharing service)
#   OFF: Cross-Device Sign-in (Google QR sign-in, Android/iOS)
#   OFF: AI-based checkout amount extraction (sends checkout pages to Google server-side AI)
# NOT patched: Local Network Access checks stay at upstream default (ON for requests/WebSockets/
# WebTransport); the LNA-WebRTC check is moot because WebRTC is being removed.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

flip() {
  local file="$1" old="$2" new="$3" n
  n=$(grep -Fc -- "$old" "$file" || true)
  if [ "$n" -eq 1 ]; then
    perl -0777 -pi -e 'BEGIN{$o=shift;$n=shift} s/\Q$o\E/$n/' "$old" "$new" "$file"
    echo "OK   $file : ${old:0:60}..."
  elif grep -Fq -- "$new" "$file"; then echo "SKIP already applied: $file"
  else echo "ERROR: string not found (drift?) in $file: $old" >&2; exit 1; fi
}
flip_anchor() {
  local file="$1" anchor="$2" from="$3" to="$4" nfrom nto
  nfrom=$(ANCHOR="$anchor" FROM="$from" perl -0777 -ne 'my($a,$f)=($ENV{ANCHOR},$ENV{FROM}); my $c=()=/\Q$a\E\s*\Q$f\E/g; print $c' "$file")
  nto=$(ANCHOR="$anchor" TO="$to" perl -0777 -ne 'my($a,$t)=($ENV{ANCHOR},$ENV{TO}); my $c=()=/\Q$a\E\s*\Q$t\E/g; print $c' "$file")
  if [ "$nfrom" -eq 1 ]; then
    ANCHOR="$anchor" FROM="$from" TO="$to" perl -0777 -pi -e 'my($a,$f,$t)=($ENV{ANCHOR},$ENV{FROM},$ENV{TO}); s/(\Q$a\E\s*)\Q$f\E/$1$t/;' "$file"
    echo "OK   $file : anchored ${anchor:0:50}..."
  elif [ "$nto" -ge 1 ]; then echo "SKIP already applied: $file"
  else echo "ERROR: anchor+value not found (drift?) in $file: $anchor" >&2; exit 1; fi
}

# Rust image decoders ON
flip third_party/blink/common/features.cc \
  'BASE_FEATURE(kRustyIcoFeature, base::FEATURE_DISABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kRustyIcoFeature, base::FEATURE_ENABLED_BY_DEFAULT);'
flip skia/rusty_jpeg_feature.cc \
  'BASE_FEATURE(kRustyJpegFeature, base::FEATURE_DISABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kRustyJpegFeature, base::FEATURE_ENABLED_BY_DEFAULT);'

# Strict site isolation on Android (the #if IS_ANDROID branch of kSitePerProcess)
flip_anchor chrome/common/chrome_features.cc \
  'BASE_FEATURE(kSitePerProcess,
#if BUILDFLAG(IS_ANDROID)' \
  'base::FEATURE_DISABLED_BY_DEFAULT' 'base::FEATURE_ENABLED_BY_DEFAULT'

# Google services OFF
flip components/collaboration/public/features.cc \
  'BASE_FEATURE(kCollaborationMessaging, base::FEATURE_ENABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kCollaborationMessaging, base::FEATURE_DISABLED_BY_DEFAULT);'
flip_anchor components/signin/public/base/signin_switches.cc \
  '#if BUILDFLAG(IS_ANDROID) || BUILDFLAG(IS_IOS)
BASE_FEATURE(kCrossDeviceSignin,' \
  'base::FEATURE_ENABLED_BY_DEFAULT' 'base::FEATURE_DISABLED_BY_DEFAULT'
flip_anchor components/autofill/core/common/autofill_payments_features.cc \
  'BASE_FEATURE(kAutofillEnableAiBasedAmountExtraction,
#if BUILDFLAG(IS_WIN) || BUILDFLAG(IS_MAC) || BUILDFLAG(IS_LINUX) || \
    BUILDFLAG(IS_CHROMEOS) || BUILDFLAG(IS_ANDROID)' \
  'base::FEATURE_ENABLED_BY_DEFAULT' 'base::FEATURE_DISABLED_BY_DEFAULT'

echo "=== flags group 5 complete ==="
