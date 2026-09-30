#!/usr/bin/env bash
# Iris — release verifier (USER side).
# Confirms a downloaded Iris file matches jegly's published release:
#   1) AUTHENTICITY: SHA256SUMS is signed by jegly — ML-DSA-87 (SHA256SUMS.mldsa87.sig, OpenSSL 3.5+) and
#      Ed25519/GPG (SHA256SUMS.asc). Both keys are pinned below. Every signature that can be checked must pass,
#      and at least one must be checked.
#   2) INTEGRITY:    the downloaded file's SHA-256 matches its line in the now-trusted SHA256SUMS.
#
# Usage:
#   ./iris-verify.sh <downloaded-file>
#     Put SHA256SUMS, SHA256SUMS.mldsa87.sig, SHA256SUMS.asc, jegly-mldsa87.pub.pem and jegly.asc
#     (all on the release page) in the same folder as the file.
#   SKIP_SIG=1 ./iris-verify.sh <file>   # integrity only (NOT recommended; no authenticity).
set -euo pipefail

# jegly's keys (also published in keys/ of github.com/jegly/iris).
MLDSA_PUB_SHA256="3c57473c5b1158c5854d97072db1aca4364c75145aef46130f465a7969e5f91f"
GPG_FPR="6B84F8EB46B9B6340BF4A0E1A5A56CEB02445D37"

ART="${1:-}"
[ -n "$ART" ] && [ -f "$ART" ] || { echo "usage: $0 <downloaded-file>" >&2; exit 2; }
DIR=$(cd "$(dirname "$ART")" && pwd)
BASE=$(basename "$ART")
SUMS="$DIR/SHA256SUMS"
[ -f "$SUMS" ] || { echo "ERROR: $SUMS not found (download it from the release page)." >&2; exit 1; }

# --- Step 1: authenticity ---
if [ "${SKIP_SIG:-0}" = "1" ]; then
  echo "WARNING: SKIP_SIG=1 — skipping signature checks. Integrity only, NO authenticity."
else
  checked=0

  # ML-DSA-87 (post-quantum)
  MSIG="$DIR/SHA256SUMS.mldsa87.sig"
  MPUB="$DIR/jegly-mldsa87.pub.pem"
  if [ -f "$MSIG" ]; then
    if ! openssl list -signature-algorithms 2>/dev/null | grep -q "ML-DSA-87"; then
      echo "NOTE: this OpenSSL has no ML-DSA-87 (needs 3.5+); skipping the post-quantum signature."
    else
      [ -f "$MPUB" ] || { echo "ERROR: $MPUB not found (it is on the release page)." >&2; exit 1; }
      have_key=$(sha256sum "$MPUB" | awk '{print $1}')
      if [ "$have_key" != "$MLDSA_PUB_SHA256" ]; then
        echo "FAIL: jegly-mldsa87.pub.pem is not jegly's key. Do NOT trust this release." >&2
        exit 1
      fi
      if ! openssl pkeyutl -verify -pubin -inkey "$MPUB" -rawin -in "$SUMS" -sigfile "$MSIG" >/dev/null 2>&1; then
        echo "FAIL: ML-DSA-87 signature on SHA256SUMS did NOT verify. Do NOT trust this file." >&2
        exit 1
      fi
      echo "OK: ML-DSA-87 signature verified."
      checked=$((checked + 1))
    fi
  fi

  # Ed25519 (GPG)
  GSIG="$DIR/SHA256SUMS.asc"
  if [ -f "$GSIG" ] && command -v gpg >/dev/null; then
    [ -f "$DIR/jegly.asc" ] && gpg --quiet --import "$DIR/jegly.asc" 2>/dev/null || true
    if ! gpg --status-fd 1 --verify "$GSIG" "$SUMS" 2>/dev/null | grep -q "^\[GNUPG:\] VALIDSIG $GPG_FPR "; then
      echo "FAIL: GPG signature on SHA256SUMS is missing, bad, or not from jegly's key ($GPG_FPR)." >&2
      exit 1
    fi
    echo "OK: GPG (Ed25519) signature verified."
    checked=$((checked + 1))
  fi

  [ "$checked" -gt 0 ] || { echo "ERROR: no signature could be checked (need SHA256SUMS.mldsa87.sig with OpenSSL 3.5+, or SHA256SUMS.asc with gpg)." >&2; exit 1; }
fi

# --- Step 2: integrity ---
line=$(grep -E "  ${BASE}\$" "$SUMS" || true)
[ -n "$line" ] || { echo "ERROR: no entry for '$BASE' in SHA256SUMS." >&2; exit 1; }
want=$(printf '%s' "$line" | awk '{print $1}')
have=$(cd "$DIR" && sha256sum "$BASE" | awk '{print $1}')

if [ "$want" = "$have" ]; then
  echo "OK: $BASE matches the published SHA-256."
  echo "VERIFIED."
else
  echo "FAIL: hash mismatch for $BASE — the file is corrupt or tampered. Do NOT install it." >&2
  exit 1
fi
