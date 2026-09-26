#!/usr/bin/env bash
# Iris — blink runtime-feature disables (runtime_enabled_features.json5).
# Verified against checkout 2026-09-25. Idempotent; fails loudly on drift.
# Disabling = set a feature's status "stable" -> "test" (off by default; only in web tests).
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
J=third_party/blink/renderer/platform/runtime_enabled_features.json5

# disable a simple `name: "X", status: "stable",` feature by anchoring on the unique name line
# and flipping the status on the following line. Tight anchor (no bleed). Idempotent.
disable_stable() {
  local name="$1" nfrom nto
  nfrom=$(NAME="$name" perl -0777 -ne 'my $n=$ENV{NAME}; my $c=()=/name:\s*"\Q$n\E",\s*status:\s*"stable",/gs; print $c' "$J")
  nto=$(NAME="$name" perl -0777 -ne 'my $n=$ENV{NAME}; my $c=()=/name:\s*"\Q$n\E",\s*status:\s*"test",/gs; print $c' "$J")
  if [ "$nfrom" -eq 1 ]; then
    NAME="$name" perl -0777 -pi -e 'my $n=$ENV{NAME}; s/(name:\s*"\Q$n\E",\s*status:\s*")stable(",)/${1}test${2}/s;' "$J"
    echo "OK   disabled blink feature: $name"
  elif [ "$nto" -ge 1 ]; then echo "SKIP already disabled: $name"
  else echo "ERROR: $name not found as a simple stable feature (drift/format change?)" >&2; exit 1; fi
}

# DocumentPatching (declarative partial updates: <template patchfor>, streamHTMLUnsafe)
disable_stable "DocumentPatching"

echo "=== blink feature disables complete ==="
