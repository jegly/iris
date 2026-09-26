#!/usr/bin/env bash
# Iris — Android: do NOT trust user-installed CA certificates by default (approved by jegly 2026-09-26;
# verified against checkout 2026-09-26). Idea from Cromite ("Disable UserCertificates by default"); own code.
# WHY: a user-installed CA (Settings > Security > Install certificate, MDM, "VPN" / "ad-block" apps, stalkerware)
# can MITM every TLS connection. Chromium on Android trusts them by default; desktop Iris doesn't consult an OS
# user store at all (Linux = Chrome Root Store only).
#
# MECHANISM (verified):
# - Android builds with chrome_root_store_optional (net/features.gni:52) and Chrome always turns the Chrome Root
#   Store verifier ON: chrome/browser/net/system_network_context_manager.cc SetUseChromeRootStore(true).
# - That verifier's trust = TrustStoreChrome (the Chrome Root Store) + TrustStoreAndroid, via
#   net/cert/internal/system_trust_store.cc CreateSslSystemTrustStoreChromeRoot() (Android branch).
#   TrustStoreAndroid holds exactly the user-added roots (AndroidNetworkLibrary.getUserAddedRoots()).
# - Fix: pass nullptr as the platform store unless the new base::Feature kIrisTrustAndroidUserCAs
#   (DISABLED by default, defined in that file) is enabled. The constructor documents nullptr ("if non-null"), and the only other consumer,
#   services/cert_verifier/cert_verifier_service_factory.cc (platform root-store info), already handles nullptr.
# - Publicly trusted sites are unaffected (Chrome Root Store). Sites issued by a user/enterprise CA fail with
#   ERR_CERT_AUTHORITY_INVALID.
# RE-ENABLE: base::Feature "IrisTrustAndroidUserCAs". NOTE: release Android ignores command-line files, so a
# user-facing switch would need a chrome://flags entry (not added here — open question for jegly).
# Guarded; idempotent (markers); fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(path, old, new, marker):
    s = open(path).read()
    if marker in s: print("SKIP already applied: " + path); return
    if s.count(old) != 1: die(f"{path}: expected 1 match, found {s.count(old)} (drift?): {old[:70]!r}")
    open(path, "w").write(s.replace(old, new, 1)); print("OK   " + path)

# Feature is defined locally in system_trust_store.cc (not net/base/features.h, which much of the tree includes ->
# editing it would inflate every rebuild). Name "IrisTrustAndroidUserCAs".
P = "net/cert/internal/system_trust_store.cc"
edit(P,
     '#elif BUILDFLAG(IS_ANDROID)\n#include "net/cert/internal/trust_store_android.h"\n#endif',
     '#elif BUILDFLAG(IS_ANDROID)\n#include "base/feature_list.h"\n#include "net/cert/internal/trust_store_android.h"\n#endif',
     '#include "base/feature_list.h"\n#include "net/cert/internal/trust_store_android.h"')
edit(P,
     "namespace {\nTrustStoreAndroid* GetGlobalTrustStoreAndroidForCRS() {",
     "namespace {\n// Iris: on Android, trust user-installed CA certificates (TrustStoreAndroid) in\n"
     "// the Chrome Root Store verifier. Disabled by default.\n"
     "BASE_FEATURE(kIrisTrustAndroidUserCAs, base::FEATURE_DISABLED_BY_DEFAULT);\n\n"
     "TrustStoreAndroid* GetGlobalTrustStoreAndroidForCRS() {",
     "BASE_FEATURE(kIrisTrustAndroidUserCAs")
edit(P,
     "  return std::make_unique<SystemTrustStoreChromeWithUnOwnedSystemStore>(\n"
     "      std::move(chrome_root), GetGlobalTrustStoreAndroidForCRS());",
     "  // Iris: user-installed CAs are not trusted unless kIrisTrustAndroidUserCAs.\n"
     "  return std::make_unique<SystemTrustStoreChromeWithUnOwnedSystemStore>(\n"
     "      std::move(chrome_root),\n"
     "      base::FeatureList::IsEnabled(kIrisTrustAndroidUserCAs)\n"
     "          ? GetGlobalTrustStoreAndroidForCRS()\n"
     "          : nullptr);",
     "IsEnabled(kIrisTrustAndroidUserCAs)")

# guard: Chrome must still force the CRS verifier on Android (else the old platform verifier trusts user CAs)
s = open("chrome/browser/net/system_network_context_manager.cc").read()
if "SetUseChromeRootStore(\n      true," not in s:
    die("system_network_context_manager.cc no longer forces SetUseChromeRootStore(true) — re-check the Android verifier")
print("OK   guard: Android uses the Chrome Root Store verifier")
PY
echo "=== Android user-CA distrust complete ==="
