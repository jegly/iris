#!/usr/bin/env bash
# Iris — anti-popup hardening (verified against checkout 2026-09-25).
# Blocks abusive popup/new-window behavior BEYOND Chromium's normal popup policy, WITHOUT breaking
# legitimate user-initiated popups (e.g. OAuth/Gmail login windows).
# Guarded multi-line replacement; idempotent; fails loudly on rebase drift.
# Run from Chromium src root (or pass it as $1). Copy-tested before landing.
#
# MECHANISM (verified in components/blocked_content/popup_blocker.cc, GetPopupPolicy):
#   With POPUPS defaulting to BLOCK (already the default), a popup is evaluated as:
#     1. content setting == ALLOW            -> allowed
#     2. !user_gesture                       -> BLOCKED (kNoGesture)
#     3. trusted user action (real click, triggering_event != kFromUntrustedEvent) -> allowed
#     4. Safe Browsing "abusive" blocker says so -> BLOCKED (kAbusive)
#     5. else                                -> return kNotBlocked   <-- upstream fallthrough
#   Iris runs with safe_browsing_mode=0, so step 4 never fires; step 5 lets popups spawned from
#   UNTRUSTED/synthetic events through. We flip step 5 to BLOCK. Net effect: popups are allowed ONLY
#   when the site is user-allowlisted (step 1) or the popup came from a genuine user gesture (step 3).
#   Real clicks -> kFromTrustedEvent -> step 3 -> still allowed, so login popups keep working.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

F=components/blocked_content/popup_blocker.cc
MARKER='return PopupBlockType::kAbusive;  // Iris: block popups without a trusted user gesture'

if grep -Fq -- "$MARKER" "$F"; then
  echo "SKIP already applied: $F"
else
  # Count the (abusive-block -> final-fallthrough) pattern; must be exactly 1.
  n=$(perl -0777 -ne 'my $c=()=/return PopupBlockType::kAbusive;\s*\}\s*return PopupBlockType::kNotBlocked;/g; print $c' "$F")
  if [ "$n" -eq 1 ]; then
    # $1 backref written directly in perl (so it interpolates). `s!...!...!` avoids brace escaping.
    perl -0777 -pi -e 's!(return PopupBlockType::kAbusive;\s*\}\s*)return PopupBlockType::kNotBlocked;!${1}return PopupBlockType::kAbusive;  // Iris: block popups without a trusted user gesture (SB-independent)!' "$F"
    echo "OK   $F : popup fallthrough -> block"
  else
    echo "ERROR: expected exactly 1 match in $F (found $n; drift?)" >&2; exit 1
  fi
fi

echo "=== anti-popup hardening complete ==="
