#!/usr/bin/env bash
# Iris — Certificate Transparency enforced, SCT auditing never on (issue #1 items 1+2, jegly 2026-11-05).
# Verified against 157.0.8103.38 (gitiles copies, 2026-11-05):
# - SystemNetworkContextManager::IsCertificateTransparencyEnabled() (chrome/browser/net/
#   system_network_context_manager.cc) = features::kCertificateTransparencyAskBeforeEnabling, which is
#   ENABLED only #if BUILDFLAG(GOOGLE_CHROME_BRANDING) (chrome/browser/browser_features.cc). Iris is unbranded -> CT was
#   off on desktop and Android. With it on: enforce_chrome_ct_policy = true on every network context, the static CT log
#   list is sent to the network + cert verifier services, and PKIMetadataComponentInstallerService pushes the fresh
#   list from the PKI metadata component (already allowed by apply-no-google-startup.sh). CT itself sends nothing.
# - Turning CT on also turns on SCT auditing on desktop: SCTReportingService::GetReportingMode() (chrome/browser/ssl/
#   sct_reporting_service.cc) returns kHashdance (lookups to Google) when Safe Browsing is on, or
#   kEnhancedSafeBrowsingReporting (full reports) with extended reporting. Iris: is_sct_auditing_enabled stays false on
#   every platform = the exact code upstream already compiles on Android -> always kDisabled.
#   Second layer: features::kSCTAuditingHashdance off (chrome/common/chrome_features.cc; NOT services/network as the
#   issue said).
# Ship both halves together (never CT without the SCT-auditing gate).
# Cost: a site whose certificate has no valid SCTs fails with ERR_CERTIFICATE_TRANSPARENCY_REQUIRED (same as Chrome).
# STATUS 2026-11-05: copy-tested on 157 file copies, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

edit("chrome/browser/browser_features.cc",
     "BASE_FEATURE(kCertificateTransparencyAskBeforeEnabling,\n"
     "#if BUILDFLAG(GOOGLE_CHROME_BRANDING)\n"
     "             base::FEATURE_ENABLED_BY_DEFAULT);\n"
     "#else\n"
     "             base::FEATURE_DISABLED_BY_DEFAULT);\n"
     "#endif  // BUILDFLAG(GOOGLE_CHROME_BRANDING)\n",
     "// Iris (apply-ct-enforce): Certificate Transparency enforced in Iris too.\n"
     "BASE_FEATURE(kCertificateTransparencyAskBeforeEnabling,\n"
     "             base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "// Iris (apply-ct-enforce): Certificate Transparency enforced", "CT on")

edit("chrome/browser/ssl/sct_reporting_service.cc",
     "  bool is_sct_auditing_enabled = false;\n"
     "#if !BUILDFLAG(IS_ANDROID)\n"
     "  is_sct_auditing_enabled =\n"
     "      SystemNetworkContextManager::IsCertificateTransparencyEnabled();\n"
     "#endif\n",
     "  // Iris (apply-ct-enforce): CT is enforced, but SCT auditing (hashdance\n"
     "  // lookups and full reports to Google) stays off on every platform.\n"
     "  bool is_sct_auditing_enabled = false;\n",
     "// Iris (apply-ct-enforce): CT is enforced, but SCT auditing", "SCT auditing off")

edit("chrome/common/chrome_features.cc",
     "BASE_FEATURE(kSCTAuditingHashdance, base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "// Iris (apply-ct-enforce): second layer, see sct_reporting_service.cc.\n"
     "BASE_FEATURE(kSCTAuditingHashdance, base::FEATURE_DISABLED_BY_DEFAULT);\n",
     "// Iris (apply-ct-enforce): second layer", "hashdance off")
PY
echo "=== CT enforce + SCT auditing off complete ==="
