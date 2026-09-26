#!/usr/bin/env bash
# Iris — remove the Payment Request API (hardening checklist review 2026-09-26; verified against this checkout).
# Before: Iris only turned off canMakePayment() (apply-degoogle-group3.sh); the PaymentRequest API itself stayed.
# MECHANISM: content/public/common/content_features.cc kWebPayments (ENABLED upstream) drives
#   - WebPreferences::payment_request_enabled (content/browser/web_contents/web_contents_impl.cc:4104) -> Blink's
#     PaymentRequest runtime feature -> the `PaymentRequest` interface is not exposed to pages, and
#   - the browser-side Mojo binding of payments::mojom::PaymentRequest (chrome/browser/chrome_browser_interface_binders.cc
#     :506 Android, :521 desktop) -> the IPC endpoint is not registered at all.
# Also read by components/payments/content/android/payment_feature_map.cc (Java side follows the same flag).
# Cost: sites that use the browser's payment sheet (some Google Pay / Apple-Pay-style checkouts) fall back to their
#   normal card form. Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "content/public/common/content_features.cc"
s = open(p).read()
old = "BASE_FEATURE(kWebPayments, base::FEATURE_ENABLED_BY_DEFAULT);"
new = "BASE_FEATURE(kWebPayments, base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no Payment Request API"
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write(f"ERROR: {p}: kWebPayments declaration changed (drift?)\n"); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : Payment Request API off")
PY
echo "=== Payment Request API off complete ==="
