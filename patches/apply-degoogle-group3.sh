#!/usr/bin/env bash
# Iris — de-Google flips, GROUP 3 (verified against checkout 2026-09-25).
# Attack-surface + phone-home + privacy default flips mirroring Vanadium 0077-0082.
# Guarded string replacement; idempotent; fails loudly on rebase drift.
# Run from Chromium src root (or pass it as $1). Copy-tested before landing.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

# literal unique-string flip (single line)
flip() {
  local file="$1" old="$2" new="$3" n
  n=$(grep -Fc -- "$old" "$file" || true)
  if [ "$n" -eq 1 ]; then
    perl -0777 -pi -e 'BEGIN{$o=shift;$n=shift} s/\Q$o\E/$n/' "$old" "$new" "$file"
    echo "OK   $file : ${old:0:60}..."
  elif grep -Fq -- "$new" "$file"; then echo "SKIP already applied: $file"
  else echo "ERROR: string not found (drift?) in $file: $old" >&2; exit 1; fi
}

# context-anchored flip where the value is on the NEXT line (or same line after a space):
# matches ANCHOR followed by ONLY whitespace then FROM -> replaces the FIRST such FROM only.
# Cannot bleed to a later token; idempotent (re-run finds 0 anchor+FROM, >=1 anchor+TO -> SKIP).
flip_anchor() {
  local file="$1" anchor="$2" from="$3" to="$4" nfrom nto
  nfrom=$(ANCHOR="$anchor" FROM="$from" perl -0777 -ne 'my($a,$f)=($ENV{ANCHOR},$ENV{FROM}); my $c=()=/\Q$a\E\s*\Q$f\E/g; print $c' "$file")
  nto=$(ANCHOR="$anchor" TO="$to" perl -0777 -ne 'my($a,$t)=($ENV{ANCHOR},$ENV{TO}); my $c=()=/\Q$a\E\s*\Q$t\E/g; print $c' "$file")
  if [ "$nfrom" -eq 1 ]; then
    ANCHOR="$anchor" FROM="$from" TO="$to" perl -0777 -pi -e 'my($a,$f,$t)=($ENV{ANCHOR},$ENV{FROM},$ENV{TO}); s/(\Q$a\E\s*)\Q$f\E/$1$t/;' "$file"
    echo "OK   $file : anchored ${anchor:0:50}..."
  elif [ "$nto" -ge 1 ]; then
    echo "SKIP already applied: $file"
  else
    echo "ERROR: anchor+value not found (drift?) in $file: $anchor" >&2; exit 1
  fi
}

# 1) Search suggestions (queries typed in the omnibox get sent to the search
#    provider as you type): default pref true -> false. (Vanadium-style.)
flip_anchor chrome/browser/profiles/profile.cc \
  'prefs::kSearchSuggestEnabled,' \
  'true,' 'false,'

# 2) Media Router / Cast (background discovery + mDNS-style device probing):
#    default pref true -> false. Also covered by gn enable_mdns/service_discovery=false,
#    but this stops the pref-gated Cast machinery too. (Vanadium 0082.)
flip chrome/browser/profiles/profile_impl.cc \
  'registry->RegisterBooleanPref(prefs::kEnableMediaRouter, true);' \
  'registry->RegisterBooleanPref(prefs::kEnableMediaRouter, false);'

# 3) Payment Request: canMakePayment()/hasEnrolledInstrument default off.
#    NOTE: this flips the user pref to false (canMakePayment reports no methods);
#    it does NOT remove the PaymentRequest JS API itself. Full API removal would be
#    a blink patch — tracked separately. (Vanadium 0081 partial.)
flip_anchor components/payments/core/payment_prefs.cc \
  'kCanMakePaymentEnabled,' \
  'true,' 'false,'

# 4) Generic Sensors (accelerometer/gyro/magnetometer/ambient-light via the
#    Sensor content setting): default ALLOW -> BLOCK. (Vanadium 0077.)
flip components/content_settings/core/browser/content_settings_registry.cc \
  'Register(ContentSettingsType::SENSORS, "sensors", CONTENT_SETTING_ALLOW,' \
  'Register(ContentSettingsType::SENSORS, "sensors", CONTENT_SETTING_BLOCK,'

# 5) Third-party cookies OFF by default: kCookieControlsMode default
#    kIncognitoOnly -> kBlockThirdParty (block 3p cookies everywhere). (Vanadium 0079.)
flip_anchor components/content_settings/core/browser/cookie_settings.cc \
  'prefs::kCookieControlsMode,' \
  'static_cast<int>(CookieControlsMode::kIncognitoOnly),' \
  'static_cast<int>(CookieControlsMode::kBlockThirdParty),'

# 6) Background Sync (lets sites finish network work after you leave — a
#    background phone-home + wake vector): content-setting default ALLOW -> BLOCK.
#    (One-shot; periodic background sync is already DISABLED by default upstream.)
#    (Vanadium 0080.)
flip_anchor components/content_settings/core/browser/content_settings_registry.cc \
  'ContentSettingsType::BACKGROUND_SYNC, "background-sync",' \
  'CONTENT_SETTING_ALLOW,' 'CONTENT_SETTING_BLOCK,'

echo "=== de-Google flips (group 3) complete ==="
