#!/usr/bin/env bash
# Iris — rebrand: name (Chromium->Iris), author (->jegly), icons.
# Verified against checkout 2026-09-25. Idempotent; safe to re-run.
# Run from Chromium src root.  Requires icons pre-generated in
#   ~/Documents/iris/branding/icon/generated/
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
ICONS="${2:-$HOME/Documents/iris/branding/icon/generated}"
cd "$SRC"

# --- 1. BRANDING file (product name + author + ids) ---
B=chrome/app/theme/chromium/BRANDING
flipf() { # literal unique replace, idempotent
  local f="$1" o="$2" n="$3"
  if grep -Fq -- "$o" "$f"; then
    perl -0777 -pi -e 'BEGIN{$o=shift;$n=shift} s/\Q$o\E/$n/g' "$o" "$n" "$f"
    echo "OK  BRANDING: $o -> $n"
  elif grep -Fq -- "$n" "$f"; then echo "SKIP BRANDING already: $n"
  else echo "WARN BRANDING string missing: $o" >&2; fi
}
flipf "$B" "PRODUCT_FULLNAME=Chromium"                 "PRODUCT_FULLNAME=Iris"
flipf "$B" "PRODUCT_SHORTNAME=Chromium"                "PRODUCT_SHORTNAME=Iris"
flipf "$B" "PRODUCT_INSTALLER_FULLNAME=Chromium Installer"  "PRODUCT_INSTALLER_FULLNAME=Iris Installer"
flipf "$B" "PRODUCT_INSTALLER_SHORTNAME=Chromium Installer" "PRODUCT_INSTALLER_SHORTNAME=Iris Installer"
flipf "$B" "COMPANY_FULLNAME=The Chromium Authors"     "COMPANY_FULLNAME=jegly"
flipf "$B" "COMPANY_SHORTNAME=The Chromium Authors"    "COMPANY_SHORTNAME=jegly"
flipf "$B" "COPYRIGHT=Copyright @LASTCHANGE_YEAR@ The Chromium Authors. All rights reserved." \
           "COPYRIGHT=Copyright @LASTCHANGE_YEAR@ jegly. All rights reserved."
flipf "$B" "MAC_BUNDLE_ID=org.chromium.Chromium"       "MAC_BUNDLE_ID=io.jegly.iris"

# --- 2. Branded-string sweep across ALL *_chromium_strings files ---
#     Chromium->Iris in message bodies, but PRESERVE: ChromiumOS / "Chromium OS",
#     "Chromium (open source) project(s)", chromium.org ; and "The Chromium Authors"->jegly.
#     NUL sentinels protect exceptions (source has no NULs). Idempotent.
GRDS=(
  chrome/app/chromium_strings.grd
  chrome/app/settings_chromium_strings.grdp
  components/components_chromium_strings.grd
)
for G in "${GRDS[@]}"; do
  if [ ! -f "$G" ]; then echo "WARN missing $G" >&2; continue; fi
  TMPG="$G.iris-tmp"; cp -p "$G" "$TMPG"   # sweep a copy; replace only if changed (keeps mtime -> no rebuild)
  perl -0777 -pi -e '
    s/The Chromium Authors/jegly/g;
    s/Chromium OS/\x00A\x00/g;
    s/ChromiumOS/\x00B\x00/g;
    s/Chromium open source project/\x00C\x00/g;
    s/Chromium projects/\x00D\x00/g;
    s/Chromium project/\x00E\x00/g;
    s/chromium\.org/\x00F\x00/g;
    s/Chromium/Iris/g;
    s/\x00A\x00/Chromium OS/g;
    s/\x00B\x00/ChromiumOS/g;
    s/\x00C\x00/Chromium open source project/g;
    s/\x00D\x00/Chromium projects/g;
    s/\x00E\x00/Chromium project/g;
    s/\x00F\x00/chromium.org/g;
    # the linked project name in "made possible by the <a>Chromium</a> open source project" (About box): the
    # link tags sit between "Chromium" and "open source project", so the exception above cannot see it.
    s/(<ph name="BEGIN_LINK_CHROMIUM">.*?<\/ph>)Iris(<ph name="END_LINK_CHROMIUM">)/$1Chromium$2/g;
  ' "$TMPG"
  if cmp -s "$G" "$TMPG"; then rm -f "$TMPG"; echo "SKIP already swept: $G"; else mv "$TMPG" "$G"; echo "OK  swept $G"; fi
done

# --- 3. icons (overwrite the chromium theme logos with Iris orb) ---
copyi() { # src -> dst, only if src exists
  local s="$ICONS/$1" d="$2"
  if [ ! -f "$s" ]; then echo "WARN missing $s" >&2
  elif cmp -s "$s" "$d"; then echo "SKIP icon up to date: $d"
  else cp "$s" "$d"; echo "OK  icon $d"; fi
}
for sz in 16 24 48 64 128 256; do copyi "product_logo_${sz}.png" "chrome/app/theme/chromium/product_logo_${sz}.png"; done
copyi "product_logo_22_mono.png" "chrome/app/theme/chromium/product_logo_22_mono.png"
for sz in 24 48 64 128 256; do copyi "product_logo_${sz}.png" "chrome/app/theme/chromium/linux/product_logo_${sz}.png"; done
# NOTE: linux/product_logo_32.xpm not replaced (XPM format; Iris orb has gradient/alpha, poor XPM fit) - left as-is.

echo "=== rebrand complete ==="
