#!/usr/bin/env bash
# Iris — app lock memory hardening (0.0.0.7 plan item 6, 2026-10-10; verified against 156.0.8078.11).
# The code lives in patches/src (copied by apply-app-lock.sh); this script only adds the build dependency.
#  - chrome/browser/iris/iris_app_lock.cc: the unlocked data key's memory is mlock()ed (never written to swap) and
#    marked MADV_DONTDUMP (left out of core dumps), Linux + Android. Local copies of the key are wiped with
#    OPENSSL_cleanse after use (Unlock, SetPassphrase); the passphrase-derived keys already were.
#  - chrome/browser/ui/views/iris/iris_unlock_dialog.cc (desktop): the window's copy of the passphrase is wiped after
#    each try, and the field and its undo history are cleared. Needs BoringSSL (OPENSSL_cleanse) -> dep added here.
# Limits (honest): best effort. mlock can fail under RLIMIT_MEMLOCK (then the key is just not pinned); copies returned
# by GetDataKey() to callers are not pinned; views' text renderer / the input method may keep passphrase copies until
# reused. Android: the passphrase comes from a Java String (immutable, cannot be wiped). Not hardened_malloc: Chromium
# uses PartitionAlloc everywhere (memory/02_DECISIONS.md).
# Needs apply-app-lock.sh. STATUS 2026-10-10: copy-tested only, NOT compile-proven (iris_app_lock.o,
# iris_unlock_dialog.o). Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/browser/ui/views/BUILD.gn"
s = open(p).read()
old = ('  source_set("iris_unlock_dialog") {\n'
       '    public = [ "iris/iris_unlock_dialog.h" ]\n'
       '    sources = [ "iris/iris_unlock_dialog.cc" ]\n'
       '    public_deps = [ "//ui/views" ]\n'
       '    deps = [\n'
       '      "//base",\n'
       '      "//chrome/app:generated_resources",\n'
       '      "//ui/base",\n'
       '      "//ui/color",\n'
       '      "//ui/gfx",\n'
       '    ]\n')
new = old.replace('      "//ui/gfx",\n',
                  '      "//third_party/boringssl",  # Iris: OPENSSL_cleanse (apply-app-lock-memory.sh)\n'
                  '      "//ui/gfx",\n')
if new in s: print("SKIP already applied: %s (unlock window: BoringSSL dep)" % p)
elif s.count(old) == 1: open(p, "w").write(s.replace(old, new)); print("OK   %s : unlock window: BoringSSL dep" % p)
else: sys.stderr.write("ERROR: %s: iris_unlock_dialog target not found (run apply-app-lock.sh first, or drift)\n" % p); sys.exit(1)
PY
echo "=== app lock memory hardening complete ==="
