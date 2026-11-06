#!/usr/bin/env bash
# Iris — the APK carries the same third-party notices as the .deb (2026-11-05, before the 157 release).
# The APK bundles IBM Plex Sans + DotGothic16 (SIL OFL 1.1: the licence must ship with the fonts), Tabler Icons,
# Catppuccin, three.js (MIT) and the converted filter lists (GPL-3.0 / CC BY-SA / MIT notices). The .deb has had them in
# /usr/share/doc since 2026-09-28 (apply-third-party-notices.sh, apply-adblock.sh); the APK had none.
# Now both files go into the APK as assets (assets/iris-third-party-notices, assets/iris-filter-lists-LICENSE),
# through chrome/android:chrome_public_non_pak_assets, the asset group chrome_public_apk already uses.
# Needs apply-third-party-notices + apply-adblock-extra (they write the two files).
# STATUS 2026-11-05: copy-tested on 157 copies, NOT built.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
for f in chrome/installer/linux/common/iris-third-party-notices chrome/installer/linux/common/iris-filter-lists-LICENSE; do
  [ -s "$f" ] || { echo "ERROR: $f missing (run apply-third-party-notices.sh / apply-adblock-extra.sh first)" >&2; exit 1; }
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
edit("chrome/android/BUILD.gn",
     '  java_group("chrome_public_non_pak_assets") {\n'
     '    deps = [\n',
     '  # Iris: third-party notices inside the APK (apply-android-notices.sh).\n'
     '  android_assets("iris_notices_assets") {\n'
     '    sources = [\n'
     '      "//chrome/installer/linux/common/iris-filter-lists-LICENSE",\n'
     '      "//chrome/installer/linux/common/iris-third-party-notices",\n'
     '    ]\n'
     '    disable_compression = false\n'
     '  }\n\n'
     '  java_group("chrome_public_non_pak_assets") {\n'
     '    deps = [\n'
     '      ":iris_notices_assets",  # Iris\n',
     'android_assets("iris_notices_assets")', "notices as APK assets")
PY
echo "=== Android third-party notices complete ==="
