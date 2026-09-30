#!/usr/bin/env bash
# Iris — release hash/signature generator (MAINTAINER side, run by jegly at release time).
# Produces SHA256SUMS + SHA512SUMS over the release artifacts, then (optionally) a detached
# GPG signature so users can verify the binary they run matches this release.
#
# SCOPE — be honest about what this is and isn't:
#   THIS provides *artifact verification*: users can confirm the file they downloaded is byte-identical
#   to what jegly released, and (with the signature) that jegly released it. That's the property that
#   actually protects users from tampered/MITM'd downloads, and it's achievable today.
#   THIS IS NOT full "bit-for-bit reproducible builds" (an independent rebuild yielding identical bits).
#   That is a much larger effort (pinned toolchain + fixed paths + stripped timestamps/build-ids +
#   deterministic archive metadata). Tracked separately in verify/README.md as a future goal.
#
# Usage:  ./iris-gen-hashes.sh <artifact> [<artifact> ...]
#   e.g.  ./iris-gen-hashes.sh iris_1.0_amd64.deb iris_1.0_amd64.snap ChromePublic.apk out/Linux/chrome
# Output (in CWD): SHA256SUMS, SHA512SUMS  (+ prints the GPG sign command to run yourself).
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: $0 <artifact> [<artifact> ...]" >&2; exit 2; }

for f in "$@"; do
  [ -f "$f" ] || { echo "ERROR: not a file: $f" >&2; exit 1; }
done

# Deterministic ordering (sort by basename) so the manifest is stable across runs.
mapfile -t FILES < <(for f in "$@"; do printf '%s\n' "$f"; done | sort)

: > SHA256SUMS
: > SHA512SUMS
for f in "${FILES[@]}"; do
  # Record by BASENAME (what a user downloads), not the local path.
  b=$(basename "$f")
  ( cd "$(dirname "$f")" && sha256sum "$(basename "$f")" ) | awk -v b="$b" '{print $1"  "b}' >> SHA256SUMS
  ( cd "$(dirname "$f")" && sha512sum "$(basename "$f")" ) | awk -v b="$b" '{print $1"  "b}' >> SHA512SUMS
  echo "hashed: $b"
done

echo
echo "Wrote SHA256SUMS and SHA512SUMS:"
echo "----------------------------------------"
cat SHA256SUMS
echo "----------------------------------------"
echo
echo "NEXT (sign it yourself — this script never touches your GPG key):"
echo "  openssl pkeyutl -sign -inkey <iris>/keys/jegly-mldsa87.key.pem -rawin -in SHA256SUMS -out SHA256SUMS.mldsa87.sig"
echo "  gpg --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS"
echo "  # publish SHA256SUMS, both signatures, keys/jegly-mldsa87.pub.pem and keys/jegly.asc with the release."
echo "  # users then run verify/iris-verify.sh (see that script)."
