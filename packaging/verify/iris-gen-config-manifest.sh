#!/usr/bin/env bash
# Iris — config-integrity manifest generator (MAINTAINER side, run at package/build time).
# Records the KNOWN-GOOD state of Iris's launch configuration so the runtime checker
# (iris-config-check.sh) can detect if launch flags or policy files were modified externally.
#
# Tracks: the launcher script (which IS the source of default flags) + any policy files you pass.
# Also extracts the launcher's `--…` flag tokens into the manifest so the checker can show a
# human-readable flag DIFF (added/removed), not just "a file hash changed".
#
# HONEST LIMITATION: this is a TRIPWIRE, not tamper-proofing. An attacker who can rewrite the
# launcher can also rewrite the manifest/checker. Its value: it catches accidental drift, a bad
# package/update, or malware/other software quietly weakening the config, and shows the user exactly
# what changed. For stronger assurance, GPG-sign the manifest (command printed at the end) and/or
# store it on read-only/immutable media.
#
# Usage:  ./iris-gen-config-manifest.sh <launcher-path> [policy-file ...] > iris-config.manifest
#   e.g.  ./iris-gen-config-manifest.sh /opt/iris/iris-launcher /etc/iris/policies/managed.json
set -euo pipefail

LAUNCHER="${1:-}"
[ -n "$LAUNCHER" ] && [ -f "$LAUNCHER" ] || { echo "usage: $0 <launcher-path> [policy-file ...]" >&2; exit 2; }
shift
POLICIES=("$@")

# Extract sorted, de-duplicated --flag tokens from the launcher's ACTUAL command lines only
# (skip shell comments so NOTES text like "drop --no-sandbox." doesn't pollute the flag set).
extract_flags() {
  grep -vE '^[[:space:]]*#' "$1" \
    | grep -oE -- '--[A-Za-z0-9][A-Za-z0-9=,._-]*' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

printf '# Iris config manifest v1\n'
printf '# generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '# launcher: %s\n' "$LAUNCHER"
printf '# flags: %s\n' "$(extract_flags "$LAUNCHER")"
# hash lines: "<sha256>  <path>"
sha256sum "$LAUNCHER"
for p in "${POLICIES[@]}"; do
  [ -f "$p" ] || { echo "ERROR: policy file not found: $p" >&2; exit 1; }
  sha256sum "$p"
done

# guidance to stderr so stdout stays a clean manifest
{
  echo
  echo "manifest written to stdout. To sign it (recommended):"
  echo "  gpg --armor --detach-sign --output iris-config.manifest.asc iris-config.manifest"
  echo "install the manifest next to the launcher; the launcher calls iris-config-check.sh on startup."
} >&2
