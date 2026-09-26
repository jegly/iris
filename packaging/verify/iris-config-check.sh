#!/usr/bin/env bash
# Iris — config-integrity checker (RUNTIME side; invoked by iris-launcher at startup).
# Recomputes the tracked files' hashes + the launcher's flag set and compares to the manifest,
# printing a clear banner of EXACTLY what changed. Warns; does not block by default.
#
# Exit codes:  0 = config matches manifest.  3 = drift detected (files and/or flags changed).
#              2 = usage/manifest error.
# Env: IRIS_CONFIG_ENFORCE=1 makes drift a hard failure the launcher can refuse to start on.
#      SKIP_SIG=1 skips the optional manifest-signature check.
#
# Usage:  ./iris-config-check.sh <manifest-path>
#   (paths + expected flags are read FROM the manifest, so the checker needs no other args.)
set -uo pipefail   # not -e: we want to run all checks and summarize, not abort on first diff.

MAN="${1:-}"
[ -n "$MAN" ] && [ -f "$MAN" ] || { echo "iris-config-check: usage: $0 <manifest-path>" >&2; exit 2; }
DIR=$(cd "$(dirname "$MAN")" && pwd)

# --- optional: verify the manifest's own signature first (authenticity of the baseline) ---
if [ "${SKIP_SIG:-0}" != "1" ] && [ -f "$MAN.asc" ]; then
  if command -v gpg >/dev/null 2>&1 && gpg --verify "$MAN.asc" "$MAN" >/dev/null 2>&1; then
    :  # good signature
  else
    echo "iris-config-check: WARNING — manifest signature ($MAN.asc) did NOT verify." >&2
  fi
fi

launcher=$(sed -n 's/^# launcher: //p' "$MAN" | head -1)
exp_flags=$(sed -n 's/^# flags: //p' "$MAN" | head -1)

drift=0
changed_files=()

# --- file hash checks (every "<sha256>  <path>" line) ---
while IFS= read -r line; do
  case "$line" in \#*|'') continue;; esac
  want=${line%% *}
  path=${line#*  }
  if [ ! -f "$path" ]; then
    changed_files+=("MISSING: $path"); drift=1; continue
  fi
  have=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
  if [ "$want" != "$have" ]; then
    changed_files+=("MODIFIED: $path"); drift=1
  fi
done < "$MAN"

# --- flag diff (re-parse the current launcher, compare token sets) ---
flag_added=(); flag_removed=()
if [ -n "$launcher" ] && [ -f "$launcher" ]; then
  cur_flags=$(grep -vE '^[[:space:]]*#' "$launcher" \
    | grep -oE -- '--[A-Za-z0-9][A-Za-z0-9=,._-]*' | sort -u | tr '\n' ' ' | sed 's/ $//')
  # tokens present in expected but not current = removed; current but not expected = added.
  for f in $exp_flags; do case " $cur_flags " in *" $f "*) :;; *) flag_removed+=("$f"); drift=1;; esac; done
  for f in $cur_flags; do case " $exp_flags " in *" $f "*) :;; *) flag_added+=("$f"); drift=1;; esac; done
fi

if [ "$drift" -eq 0 ]; then
  # Silent on success (this runs on every GUI launch); set IRIS_CONFIG_VERBOSE=1 to confirm.
  [ "${IRIS_CONFIG_VERBOSE:-0}" = "1" ] && echo "iris-config-check: OK — configuration matches the manifest." >&2
  exit 0
fi

# --- report ---
{
  echo "=================================================================="
  echo " IRIS CONFIG INTEGRITY WARNING — launch configuration has CHANGED"
  echo "=================================================================="
  [ "${#changed_files[@]}" -gt 0 ] && { echo " Files:"; printf '   - %s\n' "${changed_files[@]}"; }
  [ "${#flag_removed[@]}" -gt 0 ] && { echo " Flags REMOVED (hardening possibly weakened):"; printf '   - %s\n' "${flag_removed[@]}"; }
  [ "${#flag_added[@]}" -gt 0 ]   && { echo " Flags ADDED (unexpected):"; printf '   + %s\n' "${flag_added[@]}"; }
  echo " If you did not make these changes, your Iris install may be tampered with."
  echo "=================================================================="
} >&2

[ "${IRIS_CONFIG_ENFORCE:-0}" = "1" ] && { echo "iris-config-check: IRIS_CONFIG_ENFORCE=1 -> refusing to launch." >&2; exit 3; }
exit 3
