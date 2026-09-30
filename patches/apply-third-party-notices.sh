#!/usr/bin/env bash
# Iris — licence notices for what Iris adds on top of Chromium (2026-09-28). Chromium's own notices are unchanged
# (chrome://credits, LICENSE in the package). EasyList/EasyPrivacy: apply-adblock.sh (filter-lists-LICENSE).
#  - IBM Plex Sans + DotGothic16 (bundled WebUI fonts, apply-webui-font.sh): SIL OFL 1.1 requires the copyright
#    notice + licence to ship with the fonts.
#  - Catppuccin palette values (default theme, ui/color/iris_palettes.h): MIT.
#  - The other picker palettes: credit to the original colour-scheme authors.
# Assembled from the real licence files into chrome/installer/linux/common/iris-third-party-notices and installed
# as /usr/share/doc/<package>/third-party-notices (same mechanism as the filter-list licence; the snap is built
# from the .deb). Guarded; idempotent; fails loudly on drift. Must run after apply-adblock.sh.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
PLEX="$DIR/../branding/fonts/ibm-plex-sans/OFL.txt"
DG="$DIR/../website/fonts/OFL.txt"
for f in "$PLEX" "$DG"; do [ -s "$f" ] || { echo "ERROR: $f missing" >&2; exit 1; }; done
cd "$SRC"
OUT=chrome/installer/linux/common/iris-third-party-notices
TMP="$(mktemp "${TMPDIR:-/tmp}/iris-notices.XXXXXX")"
{
cat <<'EOF'
Iris — third-party notices
==========================

Iris is based on Chromium. Chromium's own licences are in chrome://credits and in the package's
copyright file. The ad-blocking filter lists are covered by filter-lists-LICENSE in this directory.
This file covers what Iris adds.


1. IBM Plex Sans (text font of Iris's built-in pages)
-----------------------------------------------------
EOF
cat "$PLEX"
cat <<'EOF'


2. DotGothic16 (header font of Iris's built-in pages)
-----------------------------------------------------
EOF
cat "$DG"
cat <<'EOF'


3. Catppuccin (default colour theme)
------------------------------------
The Catppuccin Mocha, Macchiato, Frappé and Latte palettes: https://catppuccin.com

MIT License

Copyright (c) 2021 Catppuccin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


4. Other colour palettes
------------------------
The other palettes in the colour picker are based on well-known terminal and editor
colour schemes. Each keeps its original name; the schemes belong to their authors.
EOF
} > "$TMP"
if cmp -s "$TMP" "$OUT"; then echo "SKIP up to date: $OUT"; rm -f "$TMP"; else mv "$TMP" "$OUT"; echo "OK   $OUT"; fi

python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift? run apply-adblock.sh first)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
edit("chrome/installer/linux/BUILD.gn",
     '    "common/iris-filter-lists-LICENSE",  # Iris: EasyList/EasyPrivacy attribution\n',
     '    "common/iris-filter-lists-LICENSE",  # Iris: EasyList/EasyPrivacy attribution\n'
     '    "common/iris-third-party-notices",  # Iris: fonts + palettes (apply-third-party-notices.sh)\n',
     "common/iris-third-party-notices", "packaging file list")
edit("chrome/installer/linux/debian/build.py",
     '            / f"usr/share/doc/{config.usr_bin_symlink_name}/filter-lists-LICENSE",\n        )\n',
     '            / f"usr/share/doc/{config.usr_bin_symlink_name}/filter-lists-LICENSE",\n        )\n'
     '        # Iris: fonts (SIL OFL 1.1) and colour palettes (Catppuccin: MIT).\n'
     '        shutil.copy(\n'
     '            output_dir / "installer/common/iris-third-party-notices",\n'
     '            staging_dir\n'
     '            / f"usr/share/doc/{config.usr_bin_symlink_name}/third-party-notices",\n'
     '        )\n',
     "iris-third-party-notices", "install into /usr/share/doc")
PY
echo "=== third-party notices complete ==="
