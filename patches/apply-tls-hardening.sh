#!/usr/bin/env bash
# Iris — TLS hardening (verified against checkout 2026-09-25).
# 1) Minimum TLS version -> 1.3 (drops TLS 1.2/1.1/1.0).
# 2) ECH (Encrypted ClientHello) -> assert still ON by default (guard, no-op).
# Guarded string replacement; idempotent; fails loudly on rebase drift.
# Run from Chromium src root (or pass it as $1). Copy-tested before landing.
#
# TRADEOFF (min TLS 1.3): a minority of legacy/enterprise/embedded servers that
# only speak TLS 1.2 will fail to connect. This is the intended hardening per
# HARDENED-BROWSER-SPEC §3b. If we later want it user-toggleable, expose the
# kSSLVersionMin pref in settings instead of only defaulting it here.
#
# ECH is ALREADY enabled by default upstream (kEncryptedClientHelloEnabled=true),
# and X25519MLKEM768 hybrid PQC key agreement is already the preferred group
# (see spec §3b) — neither needs a patch; #2 below only guards against upstream
# silently turning ECH off in a future rebase.
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

# assert a string is present (guard against upstream drift); no edit.
assert_present() {
  local file="$1" needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "OK   guard: present in $file : ${needle:0:60}..."
  else
    echo "ERROR: guard failed — expected string absent in $file (upstream changed?):" >&2
    echo "       $needle" >&2; exit 1
  fi
}

SSLMGR=chrome/browser/ssl/ssl_config_service_manager.cc

# 1) Minimum TLS version default 1.2 -> 1.3.
#    The pref registers empty (""), which parses to nothing -> mojom default kTLS12.
#    Register it as "tls1.3" so the unmanaged default floor becomes TLS 1.3.
flip "$SSLMGR" \
  'registry->RegisterStringPref(prefs::kSSLVersionMin, std::string());' \
  'registry->RegisterStringPref(prefs::kSSLVersionMin, switches::kSSLVersionTLSv13);'

# 2) ECH guard — must remain enabled by default.
assert_present "$SSLMGR" \
  'registry->RegisterBooleanPref(prefs::kEncryptedClientHelloEnabled, true);'

# 3) CNSA compliance ON by default (jegly 2026-09-30; Chrome's own flag "Cryptography Compliance (CNSA)", gone from
#    newer Chrome but present in our 156). chrome/browser/ssl/ssl_config_service_manager.cc: groups preset kCnsa2
#    (ML-KEM-1024 + X25519MLKEM768 + P-384 + P-256 + X25519; key shares still X25519MLKEM768 + X25519) and TLS 1.3
#    prefers AES-256-GCM. Desktop AND Android (chrome/common). Trade-off: ClientHello differs from stock Chrome.
flip chrome/common/chrome_features.cc \
  'BASE_FEATURE(kCryptographyComplianceCnsa, base::FEATURE_DISABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kCryptographyComplianceCnsa, base::FEATURE_ENABLED_BY_DEFAULT);  // Iris'

# 4) Merkle Tree Certificate verification ON (jegly 2026-09-30; flag #verify-mtcs). Uses the signer set COMPILED
#    into the build (net/data/ssl/chrome_root_store/signer_set.textproto), so it works without the component updater.
#    Needs kTLSTrustAnchorIDs, which is already ENABLED upstream (guarded below).
assert_present net/base/features.cc 'BASE_FEATURE(kTLSTrustAnchorIDs, base::FEATURE_ENABLED_BY_DEFAULT);'
flip net/base/features.cc \
  'BASE_FEATURE(kVerifyMTCs, base::FEATURE_DISABLED_BY_DEFAULT);' \
  'BASE_FEATURE(kVerifyMTCs, base::FEATURE_ENABLED_BY_DEFAULT);  // Iris'

echo "=== TLS hardening complete ==="
