#!/usr/bin/env bash
# Iris — release verifier (USER side; ships in verify/ + on the download page).
# Confirms a downloaded Iris artifact matches jegly's published release, in two steps:
#   1) AUTHENTICITY: verify SHA256SUMS was signed by jegly's key (needs SHA256SUMS.asc + the key).
#   2) INTEGRITY:    verify the downloaded file's SHA-256 matches the (now-trusted) SHA256SUMS line.
# Order matters: check the signature FIRST, then trust the hashes it contains.
#
# Usage:
#   ./iris-verify.sh <downloaded-artifact>
#     -> expects SHA256SUMS and SHA256SUMS.asc in the same directory, and jegly's public key
#        already imported into gpg (see --import hint below).
#   SKIP_SIG=1 ./iris-verify.sh <artifact>   # integrity-only (NOT recommended; no authenticity).
set -euo pipefail

ART="${1:-}"
[ -n "$ART" ] && [ -f "$ART" ] || { echo "usage: $0 <downloaded-artifact>" >&2; exit 2; }
DIR=$(cd "$(dirname "$ART")" && pwd)
BASE=$(basename "$ART")
SUMS="$DIR/SHA256SUMS"
SIG="$DIR/SHA256SUMS.asc"

[ -f "$SUMS" ] || { echo "ERROR: $SUMS not found (download it from the release page)." >&2; exit 1; }

# --- Step 1: authenticity (signature over the SUMS file) ---
if [ "${SKIP_SIG:-0}" = "1" ]; then
  echo "WARNING: SKIP_SIG=1 — skipping signature check. Integrity only, NO authenticity."
else
  [ -f "$SIG" ] || { echo "ERROR: $SIG not found. Get SHA256SUMS.asc + import jegly's key:
    gpg --import jegly-pubkey.asc" >&2; exit 1; }
  if ! gpg --verify "$SIG" "$SUMS" 2>&1 | tee /dev/stderr | grep -q "Good signature"; then
    echo "FAIL: signature on SHA256SUMS did NOT verify. Do NOT trust these hashes / this file." >&2
    exit 1
  fi
  echo "OK: SHA256SUMS signature verified (authentic)."
fi

# --- Step 2: integrity (this artifact's hash matches the trusted SUMS line) ---
line=$(grep -E "  ${BASE}\$" "$SUMS" || true)
[ -n "$line" ] || { echo "ERROR: no entry for '$BASE' in SHA256SUMS." >&2; exit 1; }
want=$(printf '%s' "$line" | awk '{print $1}')
have=$(cd "$DIR" && sha256sum "$BASE" | awk '{print $1}')

if [ "$want" = "$have" ]; then
  echo "OK: $BASE matches the published SHA-256."
  echo "    $have"
  echo "VERIFIED."
else
  echo "FAIL: hash mismatch for $BASE — the file is corrupt or tampered. DO NOT RUN IT." >&2
  echo "  expected: $want" >&2
  echo "  got:      $have" >&2
  exit 1
fi
