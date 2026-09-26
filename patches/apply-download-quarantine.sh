#!/usr/bin/env bash
# Iris — download quarantine: NEVER auto-open downloaded files (verified against checkout 2026-09-25).
# Enforces "an explicit user action is required before a download is opened" — un-bypassable, even if
# the auto-open list or policy is somehow populated. Guarded; idempotent; fails loudly on drift.
# Run from Chromium src root (or pass it as $1). Copy-tested before landing.
#
# MECHANISM (verified in chrome/browser/download/download_prefs.cc, DownloadPrefs::IsAutoOpenEnabled):
#   Upstream returns `auto_open_by_user_.find(ext) != end() || IsAutoOpenByPolicy(url, path)`.
#   Both lists are empty by DEFAULT (kDownloadExtensionsToOpen ""), so nothing auto-opens out of the
#   box — but the user (or a policy / a bad actor toggling "always open this type") could enable it.
#   We hard-return false so auto-open can NEVER be enabled. The PDF branch above is separately gated
#   on kOpenPdfDownloadInSystemReader (default false) AND we build with enable_pdf=false, so PDFs
#   don't auto-open either. Chromium already applies Linux provenance xattrs (user.xdg.origin.url)
#   on downloads, and never auto-executes them; this closes the one remaining auto-open path.
#
# NOTE (the OTHER half — "isolated/quarantine directory"): DECIDED 2026-09-25 to KEEP the OS Downloads
#   folder (no directory isolation). Rationale: the un-bypassable no-auto-open below + Chromium's Linux
#   provenance xattrs (user.xdg.origin.url) already deliver "explicit action before opening" without
#   forcing a nonstandard download location on the user. (Chromium has no --download-directory switch;
#   isolating would require a managed policy, a first-run pref default, or a platform-specific patch —
#   none wanted.) This script's no-auto-open flip is the whole of the shipped feature.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

flip_slurp() {
  local file="$1" re="$2" new="$3" marker="$4" n
  if grep -Fq -- "$marker" "$file"; then echo "SKIP already applied: $file"; return; fi
  n=$(RE="$re" perl -0777 -ne 'my $r=$ENV{RE}; my $c=()=/$r/g; print $c' "$file")
  if [ "$n" -eq 1 ]; then
    RE="$re" NEW="$new" perl -0777 -pi -e 'my($r,$w)=($ENV{RE},$ENV{NEW}); s/$r/$w/;' "$file"
    echo "OK   $file : IsAutoOpenEnabled -> false"
  else
    echo "ERROR: expected exactly 1 match in $file (found $n; drift?)" >&2; exit 1
  fi
}

flip_slurp chrome/browser/download/download_prefs.cc \
  'return auto_open_by_user_\.find\(extension\) != auto_open_by_user_\.end\(\) \|\|\s*IsAutoOpenByPolicy\(url, path\);' \
  'return false;  // Iris: never auto-open downloads (require explicit user action)' \
  'return false;  // Iris: never auto-open downloads'

echo "=== download no-auto-open complete ==="
