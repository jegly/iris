#!/usr/bin/env bash
# Iris — content-setting defaults, GROUP 4 (verified against checkout 2026-09-26).
# From the 2026-09-25 hardening-checklist triage (approved): Idle Detection + Web MIDI default BLOCK.
# Guarded; idempotent; fails loudly on rebase drift. Same shape as group-3's sensors/bg-sync flips.
#
# - Idle Detection (IDLE_DETECTION, "idle-detection"): default ASK -> BLOCK. valid_settings include BLOCK.
# - Web MIDI (MIDI_SYSEX, "midi-sysex"): default ASK -> BLOCK. Because blink feature
#   kBlockMidiByDefault is ENABLED by default (third_party/blink/common/features.cc), ALL MIDI access
#   (not just SysEx) is gated by the MIDI_SYSEX permission — so this blocks Web MIDI entirely.
#   Guarded below: if upstream ever disables kBlockMidiByDefault, this script errors instead of
#   silently leaving non-SysEx MIDI open.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
F=components/content_settings/core/browser/content_settings_registry.cc

flip() {
  local file="$1" old="$2" new="$3" n
  n=$(grep -Fc -- "$old" "$file" || true)
  if [ "$n" -eq 1 ]; then
    perl -0777 -pi -e 'BEGIN{$o=shift;$n=shift} s/\Q$o\E/$n/' "$old" "$new" "$file"
    echo "OK   $file : ${old:0:60}..."
  elif grep -Fq -- "$new" "$file"; then echo "SKIP already applied: $file"
  else echo "ERROR: string not found (drift?) in $file: $old" >&2; exit 1; fi
}
flip_anchor() {
  local file="$1" anchor="$2" from="$3" to="$4" nfrom nto
  nfrom=$(ANCHOR="$anchor" FROM="$from" perl -0777 -ne 'my($a,$f)=($ENV{ANCHOR},$ENV{FROM}); my $c=()=/\Q$a\E\s*\Q$f\E/g; print $c' "$file")
  nto=$(ANCHOR="$anchor" TO="$to" perl -0777 -ne 'my($a,$t)=($ENV{ANCHOR},$ENV{TO}); my $c=()=/\Q$a\E\s*\Q$t\E/g; print $c' "$file")
  if [ "$nfrom" -eq 1 ]; then
    ANCHOR="$anchor" FROM="$from" TO="$to" perl -0777 -pi -e 'my($a,$f,$t)=($ENV{ANCHOR},$ENV{FROM},$ENV{TO}); s/(\Q$a\E\s*)\Q$f\E/$1$t/;' "$file"
    echo "OK   $file : anchored ${anchor:0:50}..."
  elif [ "$nto" -ge 1 ]; then echo "SKIP already applied: $file"
  else echo "ERROR: anchor+value not found (drift?) in $file: $anchor" >&2; exit 1; fi
}

# Guard: MIDI_SYSEX must gate ALL MIDI for the MIDI flip to mean "Web MIDI off".
grep -Fq 'BASE_FEATURE(kBlockMidiByDefault, base::FEATURE_ENABLED_BY_DEFAULT);' \
  third_party/blink/common/features.cc \
  || { echo "ERROR: kBlockMidiByDefault no longer ENABLED upstream — MIDI_SYSEX BLOCK won't cover all MIDI. Re-check." >&2; exit 1; }
echo "OK   guard: kBlockMidiByDefault enabled (MIDI_SYSEX gates all MIDI)"

# 1) Idle Detection: ASK -> BLOCK (default value is on the line after the anchor)
flip_anchor "$F" 'ContentSettingsType::IDLE_DETECTION, "idle-detection",' \
  'CONTENT_SETTING_ASK,' 'CONTENT_SETTING_BLOCK,'

# 2) Web MIDI: ASK -> BLOCK (single-line, unique)
flip "$F" \
  'Register(ContentSettingsType::MIDI_SYSEX, "midi-sysex", CONTENT_SETTING_ASK,' \
  'Register(ContentSettingsType::MIDI_SYSEX, "midi-sysex", CONTENT_SETTING_BLOCK,'

echo "=== content-setting defaults (group 4) complete ==="
