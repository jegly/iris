#!/usr/bin/env bash
# Iris — JIT OFF at RUNTIME via Chromium's native JAVASCRIPT_JIT content setting (verified 2026-09-26).
# Replaces the build-time `v8_jitless` approach, which CANNOT link in this V8 revision:
#   - v8_enable_webassembly=false + jitless -> Blink link fails (~27 unguarded WASM refs)   [night 1]
#   - webassembly + drumbrake + jitless     -> Liftoff refs compiler::SimdShuffle, which is only
#     built with turbofan -> link fails                                                    [night 2]
# So: build STANDARD V8 (links by construction), and disable JIT per-renderer at runtime.
#
# MECHANISM (verified):
#   components/content_settings/.../content_settings_registry.cc registers JAVASCRIPT_JIT default ALLOW.
#   ChromeContentBrowserClient::IsJitDisabledForSite() returns true when it's BLOCK (web-safe schemes),
#   and content/browser/renderer_host/render_process_host_impl.cc then launches the renderer with
#   --js-flags=--jitless; renderer_sandboxed_process_launcher_delegate.cc tightens the sandbox for it.
#   chrome:// WebUI keeps JIT (non-web-safe scheme) — trusted, fine. Per-site ALLOW exceptions possible.
#
# WASM consequence (verified, v8/src/wasm/wasm-js.cc:3432): expose_wasm = !jitless ||
#   correctness_fuzzer_suppressions || wasm_jitless. Without DrumBrake, wasm_jitless is READONLY false,
#   so under jitless V8 does NOT install the `WebAssembly` global at all -> WASM API absent for web
#   content. (V8's own comment: wasm still creates executable memory even interpreter-only, so it's
#   unexposed in jitless.) That's the original "WASM off" goal, via upstream-designed behavior.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

flip_anchor() {
  local file="$1" anchor="$2" from="$3" to="$4" nfrom nto
  nfrom=$(ANCHOR="$anchor" FROM="$from" perl -0777 -ne 'my($a,$f)=($ENV{ANCHOR},$ENV{FROM}); my $c=()=/\Q$a\E\s*\Q$f\E/g; print $c' "$file")
  nto=$(ANCHOR="$anchor" TO="$to" perl -0777 -ne 'my($a,$t)=($ENV{ANCHOR},$ENV{TO}); my $c=()=/\Q$a\E\s*\Q$t\E/g; print $c' "$file")
  if [ "$nfrom" -eq 1 ]; then
    ANCHOR="$anchor" FROM="$from" TO="$to" perl -0777 -pi -e 'my($a,$f,$t)=($ENV{ANCHOR},$ENV{FROM},$ENV{TO}); s/(\Q$a\E\s*)\Q$f\E/$1$t/;' "$file"
    echo "OK   $file : anchored ${anchor:0:50}..."
  elif [ "$nto" -ge 1 ]; then
    echo "SKIP already applied: $file"
  else
    echo "ERROR: anchor+value not found (drift?) in $file: $anchor" >&2; exit 1
  fi
}

# JAVASCRIPT_JIT default ALLOW -> BLOCK (JIT off for all web content; per-site exceptions allowed).
flip_anchor components/content_settings/core/browser/content_settings_registry.cc \
  'ContentSettingsType::JAVASCRIPT_JIT, "javascript-jit",' \
  'CONTENT_SETTING_ALLOW,' 'CONTENT_SETTING_BLOCK,'

echo "=== runtime jitless (JIT content setting BLOCK) complete ==="
