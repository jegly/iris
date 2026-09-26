#!/usr/bin/env bash
# Iris — WebGPU OFF by default, compiled in (verified against checkout 2026-09-26).
# WHY: WebGPU (browser-side feature kWebGPUService) defaults ON on Android, Win, Mac, ChromeOS AND on
# our Linux build (use_webgpu_on_vulkan_via_gl_interop=true -> WEBGPU_ENABLED). The launcher's old
# `--disable-features=WebGPU` matched NO feature (silent no-op). The launcher now uses
# `--disable-features=WebGPUService`, but Android has no launcher, so the default must change in source.
# navigator.gpu is gated only by [SecureContext] in Blink; kWebGPUService is the real control
# (content/browser/gpu/compositor_util.cc, gpu/command_buffer/service/service_utils.cc).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
F=gpu/config/gpu_finch_features.cc
OLD='BASE_FEATURE(kWebGPUService, WEBGPU_ENABLED);'
NEW='BASE_FEATURE(kWebGPUService, base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: WebGPU off'
n=$(grep -Fc -- "$OLD" "$F" || true)
if [ "$n" -eq 1 ]; then
  perl -0777 -pi -e 'BEGIN{$o=shift;$n=shift} s/\Q$o\E/$n/' "$OLD" "$NEW" "$F"; echo "OK   $F : kWebGPUService -> DISABLED"
elif grep -Fq -- "$NEW" "$F"; then echo "SKIP already applied: $F"
else echo "ERROR: string not found (drift?) in $F: $OLD" >&2; exit 1; fi
# kWebGPUBlobCache still uses WEBGPU_ENABLED, so the macro stays referenced (no unused-macro issue).
grep -Fq 'BASE_FEATURE(kWebGPUBlobCache, WEBGPU_ENABLED);' "$F" \
  || { echo "ERROR: kWebGPUBlobCache line changed upstream — re-check macro usage" >&2; exit 1; }
echo "=== WebGPU off (compiled-in) complete ==="
