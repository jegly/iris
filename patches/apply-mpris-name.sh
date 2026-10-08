#!/usr/bin/env bash
# Iris — MPRIS (media keys / sound menu) D-Bus name: org.mpris.MediaPlayer2.iris-browser.instance<pid> instead of
# ...chromium.instance<pid> (jegly 2026-10-09: the Snap Store reviewer asked that the snap's mpris slot name match the
# snap name instead of "chromium"; the browser registers the name hard-coded in
# components/system_media_controls/linux/system_media_controls_linux.cc, so the browser and the snap slot
# (packaging/snap/snapcraft.yaml: slots.mpris.name = iris-browser) must change together or AppArmor blocks the
# registration and media keys stop working). Desktop media controls look for any org.mpris.MediaPlayer2.* name.
# STATUS 2026-10-09: copy-tested only, NOT compile-proven (system_media_controls_linux.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "components/system_media_controls/linux/system_media_controls_linux.cc"
s = open(p).read()
old = '    "org.mpris.MediaPlayer2.chromium.instance%i";\n'
new = '    "org.mpris.MediaPlayer2.iris-browser.instance%i";  // Iris: matches the snap slot (apply-mpris-name.sh)\n'
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write("ERROR: %s: service name format string not found exactly once (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new, 1)); print("OK   " + p)
PY
echo "=== MPRIS name complete ==="
