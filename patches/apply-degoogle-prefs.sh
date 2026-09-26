#!/usr/bin/env bash
# Iris — de-Google pref-default flips (verified against checkout 2026-09-24).
# Guarded string replacement; idempotent; fails loudly on rebase drift.
# Run from Chromium src root. Group 1 of the Vanadium 0063-0100 de-Google set.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

# literal unique-string flip
flip() {
  local file="$1" old="$2" new="$3" n
  n=$(grep -Fc -- "$old" "$file" || true)
  if [ "$n" -eq 1 ]; then
    perl -0777 -pi -e 'BEGIN{$o=shift;$n=shift} s/\Q$o\E/$n/' "$old" "$new" "$file"
    echo "OK   $file : ${old:0:60}..."
  elif grep -Fq -- "$new" "$file"; then echo "SKIP already applied: $file"
  else echo "ERROR: string not found (drift?) in $file: $old" >&2; exit 1; fi
}

# context-anchored flip where the value is on the NEXT line: matches ANCHOR followed by
# ONLY whitespace then FROM (no arbitrary span -> cannot bleed to a later token).
# Idempotent: re-run finds 0 anchor+FROM and >=1 anchor+TO -> SKIP.
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

# 1) Hyperlink auditing (<a ping>): default true -> false
flip chrome/browser/chrome_content_browser_client.cc \
  'RegisterBooleanPref(prefs::kEnableHyperlinkAuditing, true);' \
  'RegisterBooleanPref(prefs::kEnableHyperlinkAuditing, false);'

# 2) Alternate error pages (navigation error-correction phone-home): default true -> false
#    default value is on the line after the pref name; anchor on the (unique) pref name.
flip_anchor chrome/browser/net/profile_network_context_service.cc \
  'embedder_support::kAlternateErrorPagesEnabled,' \
  'true);' 'false);'

# --- group 2: browser sign-in off + fingerprint/client-hints defaults ---
# 3) Browser sign-in (Google account) OFF
flip components/signin/internal/identity_manager/primary_account_manager.cc \
  'RegisterBooleanPref(prefs::kSigninAllowed, true);' \
  'RegisterBooleanPref(prefs::kSigninAllowed, false);'
flip chrome/browser/signin/account_consistency_mode_manager.cc \
  'RegisterBooleanPref(prefs::kSigninAllowedOnNextStartup, true);' \
  'RegisterBooleanPref(prefs::kSigninAllowedOnNextStartup, false);'

# 4) Client hints: stop honoring server ACCEPT_CH frame (less fingerprint exposure)
flip services/network/public/cpp/features.cc \
  'BASE_FEATURE(kAcceptCHFrame, base::FEATURE_ENABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kAcceptCHFrame, base::FEATURE_DISABLED_BY_DEFAULT);'

# 5) Reduce Accept-Language to a single value (less entropy)
flip services/network/public/cpp/features.cc \
  'BASE_FEATURE(kReduceAcceptLanguage, base::FEATURE_DISABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kReduceAcceptLanguage, base::FEATURE_ENABLED_BY_DEFAULT);'

echo "=== de-Google pref flips (groups 1+2) complete ==="
