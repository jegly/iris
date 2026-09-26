#!/usr/bin/env bash
# Iris — feature-default flips (verified against checkout 2026-09-24).
# Uses GUARDED string replacements (not line-numbered diffs) so it survives
# Chromium rebases: each edit checks the old string exists first, and fails
# loudly if the source has drifted (rather than silently misapplying).
#
# Run from the Chromium src root:  cd ~/Documents/chromium/src && ~/Documents/iris/patches/apply-feature-defaults.sh
# Idempotent: re-running after applied is a no-op.
set -euo pipefail

SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

# helper: replace OLD->NEW in FILE, but only if OLD is present exactly once.
# if OLD absent but NEW present -> already applied (skip). else -> error.
flip() {
  local file="$1" old="$2" new="$3"
  local n; n=$(grep -Fc -- "$old" "$file" || true)
  if [ "$n" -eq 1 ]; then
    # exact literal replace via perl \Q...\E (no regex surprises)
    perl -0777 -pi -e 'BEGIN{$o=shift;$n=shift} s/\Q$o\E/$n/' "$old" "$new" "$file"
    echo "OK   flipped in $file"
  elif grep -Fq -- "$new" "$file"; then
    echo "SKIP already applied in $file"
  else
    echo "ERROR: expected string not found in $file (rebase drift?):" >&2
    echo "       $old" >&2
    exit 1
  fi
}

# 1) StrictOriginIsolation: DISABLED -> ENABLED
flip content/public/common/content_features.cc \
  'BASE_FEATURE(kStrictOriginIsolation, base::FEATURE_DISABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kStrictOriginIsolation, base::FEATURE_ENABLED_BY_DEFAULT);'

# 2) OriginKeyedProcessesByDefault: DISABLED -> ENABLED
flip content/public/common/content_features.cc \
  'BASE_FEATURE(kOriginKeyedProcessesByDefault, base::FEATURE_DISABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kOriginKeyedProcessesByDefault, base::FEATURE_ENABLED_BY_DEFAULT);'

# 3) PartitionAlloc advanced checks: param default kBrowserOnly -> kAllProcesses
#    (context-anchored: the standalone 8-space param line is unique; the enum
#     option label kBrowserOnly elsewhere is left untouched.)
flip base/allocator/partition_alloc_features.cc \
  '        PartitionAllocWithAdvancedChecksEnabledProcesses::kBrowserOnly,' \
  '        PartitionAllocWithAdvancedChecksEnabledProcesses::kAllProcesses,'

echo "=== feature-default flips complete ==="
