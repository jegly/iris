#!/usr/bin/env bash
# Iris — Android lock screen shows just "Iris" in DotGothic16, big and bold (jegly 2026-11-05: "it says iris is locked
# etc, it should just say 'Iris' - in dotgothic16 font big and bold on the lock screen").
# The text itself is in patches/src/.../iris/IrisUnlockActivity.java (copied by apply-android-app-lock.sh); this script
# adds the font it uses as an Android font resource, R.font.iris_dotgothic16:
#   branding/fonts/dotgothic16/dotgothic16_latin.ttf -> chrome/android/java/res/font/iris_dotgothic16.ttf
#   (+ chrome_java_resources.gni, which lists every chrome_java resource by name).
# The TTF is google/fonts ofl/dotgothic16/DotGothic16-Regular.ttf subset to U+0020-007E with fontTools pyftsubset
# (2026-11-05; 2.0 MB -> 55 KB). SIL OFL 1.1 (branding/fonts/dotgothic16/OFL.txt). DotGothic16 has one weight; "bold"
# is Android's synthetic bold (Typeface.BOLD).
# STATUS 2026-11-05: copy-tested on the 157.0.8103.38 tree, NOT compile-proven (chrome_java + resources).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
from="$DIR/../branding/fonts/dotgothic16/dotgothic16_latin.ttf"
to=chrome/android/java/res/font/iris_dotgothic16.ttf
[ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
edit("chrome/android/chrome_java_resources.gni",
     '  "java/res/font/reader_mode_lexend.xml",\n',
     '  "java/res/font/iris_dotgothic16.ttf",  # Iris (apply-android-lock-wordmark.sh)\n'
     '  "java/res/font/reader_mode_lexend.xml",\n',
     '"java/res/font/iris_dotgothic16.ttf"', "font resource")
PY
echo "=== Android lock screen wordmark font complete ==="
