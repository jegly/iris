#!/usr/bin/env bash
# Iris — privacy/isolation "easy flips" batch 1 (verified against checkout 2026-09-26). Ideas from Cromite's
# feature list; our own code (default flips only). Both platforms unless noted.
#  1 window.name cleared on cross-site top-level navigation (kClearCrossSiteCrossBrowsingContextGroupWindowName
#    exists upstream but is OFF) — stops sites passing an ID to the next site through window.name
#  2 FedCM off: browser-side kFedCm -> DISABLED **and** Blink "FedCm" stable -> test. The Blink feature is
#    applied with kSetOnlyIfOverridden (content/child/runtime_features.cc), so the base::Feature default
#    alone would NOT switch the web API off. Normal web logins (incl. YubiKey/WebAuthn) unaffected.
#  3 Compression Dictionary Transport off (network::features; Blink maps to the same feature)
#  4 Preloading off: kNetworkPredictionOptions default kDefault -> kDisabled
#    (= PreloadPagesState::kNoPreloading: no prefetch / prerender / preconnect)
#  5 Text fragments (#:~:text=) off: Blink TextFragmentIdentifiers stable -> test (precedent for test+OT: Canvas2dMesh)
#  6 Signed exchanges off: pref kSignedHTTPExchangeEnabled true -> false
#  7 Translate offer off: kOfferTranslateEnabled true -> false  (Google Translate endpoint)
#  8 Translate ranker query off: kTranslateRankerQuery -> DISABLED (ranker model is a Google fetch)
#  9 Autofill server communication off: kAutofillServerCommunication -> DISABLED (Vanadium does the same)
# 10 Android feed hidden by default: kArticlesListVisible true -> false (Discover/feed; needs Google anyway)
# NOT here: Privacy Sandbox — its back-ends (Topics, Protected Audience, Shared Storage, Private Aggregation)
#   are already removed upstream in this tree; Google geolocation — no API key in unbranded Linux builds.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

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
CF=content/public/common/content_features.cc
J=third_party/blink/renderer/platform/runtime_enabled_features.json5

# 1 window.name
flip_anchor $CF 'BASE_FEATURE(kClearCrossSiteCrossBrowsingContextGroupWindowName,' \
  'base::FEATURE_DISABLED_BY_DEFAULT' 'base::FEATURE_ENABLED_BY_DEFAULT'
# 2 FedCM (browser + Blink)
flip $CF 'BASE_FEATURE(kFedCm, base::FEATURE_ENABLED_BY_DEFAULT);' 'BASE_FEATURE(kFedCm, base::FEATURE_DISABLED_BY_DEFAULT);'
flip_anchor $J 'name: "FedCm",
      public: true,' 'status: "stable",' 'status: "test",'
# 3 Compression dictionaries
flip services/network/public/cpp/features.cc \
  'BASE_FEATURE(kCompressionDictionaryTransport, base::FEATURE_ENABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kCompressionDictionaryTransport, base::FEATURE_DISABLED_BY_DEFAULT);'
# 4 Preloading
flip_anchor chrome/browser/preloading/preloading_prefs.cc 'prefs::kNetworkPredictionOptions,' \
  'static_cast<int>(NetworkPredictionOptions::kDefault),' 'static_cast<int>(NetworkPredictionOptions::kDisabled),'
# 5 Text fragments
flip_anchor $J 'name: "TextFragmentIdentifiers",
      origin_trial_feature_name: "TextFragmentIdentifiers",
      public: true,' 'status: "stable",' 'status: "test",'
# 6 Signed exchanges
flip chrome/browser/chrome_content_browser_client.cc \
  'registry->RegisterBooleanPref(prefs::kSignedHTTPExchangeEnabled, true);' \
  'registry->RegisterBooleanPref(prefs::kSignedHTTPExchangeEnabled, false);'
# 7 Translate offer
flip_anchor chrome/browser/ui/browser_ui_prefs.cc 'translate::prefs::kOfferTranslateEnabled,' 'true,' 'false,'
# 8 Translate ranker
flip components/translate/core/browser/translate_ranker_impl.cc \
  'BASE_FEATURE(kTranslateRankerQuery, base::FEATURE_ENABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kTranslateRankerQuery, base::FEATURE_DISABLED_BY_DEFAULT);'
# 9 Autofill server
flip components/autofill/core/common/autofill_debug_features.cc \
  'BASE_FEATURE(kAutofillServerCommunication, base::FEATURE_ENABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kAutofillServerCommunication, base::FEATURE_DISABLED_BY_DEFAULT);'
# 10 Android feed
flip components/feed/core/shared_prefs/pref_names.cc \
  'registry->RegisterBooleanPref(kArticlesListVisible, true);' \
  'registry->RegisterBooleanPref(kArticlesListVisible, false);'
echo "=== privacy batch 1 complete ==="
