#!/usr/bin/env bash
# Iris — SharedArrayBuffer fully off for web content (jegly 2026-10-08: hardening round, on by default; verified against
# 156.0.8078.11). Upstream: kSharedArrayBuffer is disabled, so V8 runs with --enable-sharedarraybuffer-per-context and
# asks Blink per context (v8_initializer.cc SharedArrayBufferConstructorEnabledCallback ->
# ExecutionContext::SharedArrayBufferTransferAllowed()); that allowed it for cross-origin-isolated pages (COOP+COEP),
# some schemes, the reverse origin trial and an enterprise switch. Iris: that function now always returns false, so
# the SharedArrayBuffer constructor is absent and SABs cannot be posted between contexts, on every page.
# Why: SAB + a worker is a high-resolution timer (side-channel attacks); WebAssembly (its main user) is already off.
# Whole body replaced (no unreachable code -> -Wunreachable-code-aggressive safe).
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (blink core execution_context.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "third_party/blink/renderer/core/execution_context/execution_context.cc"
s = open(p).read()
MARK = "// Iris: SharedArrayBuffer is off for all web content"
if MARK in s: print("SKIP already applied: " + p); sys.exit(0)
i = s.find("bool ExecutionContext::SharedArrayBufferTransferAllowed() const {\n")
j = s.find("bool ExecutionContext::CheckSharedArrayBufferTransferAllowedAndReport() {\n")
if i < 0 or j < 0 or j < i or s.count("bool ExecutionContext::SharedArrayBufferTransferAllowed() const {\n") != 1:
    sys.stderr.write("ERROR: %s: SharedArrayBufferTransferAllowed() not found as expected (drift?)\n" % p); sys.exit(1)
body = s[i:j]
for must in ("CrossOriginIsolatedCapability()", "UnrestrictedSharedArrayBufferEnabled(this)"):
    if must not in body: sys.stderr.write("ERROR: %s: body changed upstream (%s missing) - re-check\n" % (p, must)); sys.exit(1)
new = ("bool ExecutionContext::SharedArrayBufferTransferAllowed() const {\n"
       "  " + MARK + " (apply-no-sharedarraybuffer.sh):\n"
       "  // no constructor, no transfer, even when cross-origin isolated. It is a\n"
       "  // high-resolution timer for side-channel attacks.\n"
       "  return false;\n"
       "}\n\n")
open(p, "w").write(s[:i] + new + s[j:])
print("OK   " + p)
PY
echo "=== SharedArrayBuffer off complete ==="
