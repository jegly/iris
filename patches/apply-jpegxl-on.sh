#!/usr/bin/env bash
# Iris — JPEG XL image support, explicitly ON (jegly 2026-10-09; verified against 156.0.8078.11).
# This checkout already has the decoder built (enable_jxl_decoder = true in third_party/blink/renderer/config.gni; the
# JXL decoder is the Rust jxl-rs crate, //third_party/rust/jxl/v0_7) and blink::features::kJXLImageFormat is
# FEATURE_ENABLED_BY_DEFAULT (third_party/blink/common/features.cc). It is also a chrome://flags entry
# ("Enable JXL image format", expires M158). Iris adds "JXLImageFormat" to its compiled-in --enable-features list (the
# same merged value apply-gpc-on.sh builds) so it stays on whatever upstream does with the default or the flag.
# Effect: image/jxl in the Accept header and .jxl images decode. No new code, no Blink rebuild beyond the switch.
# Needs apply-gpc-on.sh (anchors on its feature list). Guarded; idempotent; fails loudly on drift.
# STATUS 2026-10-09: copy-tested only, NOT compile-proven. Runtime check: open a .jxl file / chrome://flags shows Enabled.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/app/chrome_main_delegate.cc"
s = open(p).read()
old = '      iris_features += "GlobalPrivacyControlForce";\n'
new = ('      iris_features += "GlobalPrivacyControlForce";\n'
       '      // Iris: JPEG XL images (apply-jpegxl-on.sh).\n'
       '      iris_features += ",JXLImageFormat";\n')
if 'iris_features += ",JXLImageFormat";' in s:
    print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: die(p + ": GPC feature line not found exactly once (run apply-gpc-on.sh first / drift?)")
open(p, "w").write(s.replace(old, new, 1)); print("OK   " + p + " : JXLImageFormat enabled")
f = open("third_party/blink/common/features.cc").read()
if "BASE_FEATURE(kJXLImageFormat," not in f: die("kJXLImageFormat no longer defined (upstream drift)")
b = open("third_party/blink/renderer/config.gni").read()
if "enable_jxl_decoder = true" not in b: die("enable_jxl_decoder default changed (upstream drift)")
print("OK   guard: feature + decoder default present")
PY
echo "=== JPEG XL on complete ==="
