#!/usr/bin/env bash
# Iris — TLS connection details in Page Info (verified against this checkout 2026-09-30).
# Click the lock -> "Connection is secure": under the certificate row, a "Connection details" section lists the
# protocol, cipher suite, key exchange group (e.g. X25519MLKEM768), server signature scheme and whether Encrypted
# Client Hello was used, each with its TLS code point. Desktop views only (Android Page Info is Java: TODO Phase C).
# Core: chrome/browser/iris/iris_tls_info.* (tab helper recording ECH per committed entry + the text builder).
# English-only labels (no new grit IDs = no full rebuild); localize with the other Iris strings.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
mkdir -p chrome/browser/iris
for f in iris_tls_info.h iris_tls_info.cc; do
  from="$DIR/src/chrome/browser/iris/$f"; to="chrome/browser/iris/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

edit("chrome/browser/BUILD.gn", "    \"iris/iris_google_signin_throttle.h\",  # Iris\n",
     "    \"iris/iris_google_signin_throttle.h\",  # Iris\n"
     "    \"iris/iris_tls_info.cc\",  # Iris\n    \"iris/iris_tls_info.h\",  # Iris\n",
     "iris/iris_tls_info.cc", "BUILD: sources")

t = "chrome/browser/ui/tab_helpers.cc"
edit(t, "  zoom::ZoomController::CreateForWebContents(web_contents);\n",
     "  zoom::ZoomController::CreateForWebContents(web_contents);\n"
     "  iris::TlsInfoTabHelper::CreateForWebContents(web_contents);  // Iris (TLS details)\n",
     "iris::TlsInfoTabHelper::CreateForWebContents", "tab helper attached")
edit(t, "#include \"chrome/browser/ui/tab_helpers.h\"\n",
     "#include \"chrome/browser/ui/tab_helpers.h\"\n"
     "#include \"chrome/browser/iris/iris_tls_info.h\"  // nogncheck  Iris (TLS details)\n",
     "chrome/browser/iris/iris_tls_info.h", "include")

h = "chrome/browser/ui/views/page_info/page_info_security_content_view.h"
edit(h, "  raw_ptr<RichHoverButton> certificate_button_ = nullptr;\n",
     "  raw_ptr<RichHoverButton> certificate_button_ = nullptr;\n\n"
     "  // Iris: TLS connection details (apply-page-info-tls.sh).\n"
     "  raw_ptr<SecurityInformationView> iris_tls_view_ = nullptr;\n",
     "iris_tls_view_", "member")

c = "chrome/browser/ui/views/page_info/page_info_security_content_view.cc"
edit(c, "#include \"chrome/browser/ui/color/chrome_color_id.h\"\n",
     "#include \"chrome/browser/iris/iris_tls_info.h\"  // nogncheck  Iris (TLS details)\n"
     "#include \"chrome/browser/ui/color/chrome_color_id.h\"\n",
     "chrome/browser/iris/iris_tls_info.h", "include")
edit(c, "  if (identity_info.show_change_password_buttons) {\n",
     "  // Iris: TLS connection details under the certificate row. Rebuilt on every call, like the rows above.\n"
     "  if (iris_tls_view_) {\n"
     "    RemoveChildViewT(iris_tls_view_.get());\n"
     "    iris_tls_view_ = nullptr;\n"
     "  }\n"
     "  if (identity_info.certificate) {\n"
     "    std::u16string iris_tls =\n"
     "        iris::GetTlsDetailsText(presenter_->iris_web_contents());\n"
     "    if (!iris_tls.empty()) {\n"
     "      iris_tls_view_ = AddChildView(std::make_unique<SecurityInformationView>(\n"
     "          ChromeLayoutProvider::Get()\n"
     "              ->GetInsetsMetric(views::INSETS_DIALOG)\n"
     "              .left()));\n"
     "      iris_tls_view_->SetIcon(\n"
     "          PageInfoViewFactory::GetImageModel(vector_icons::kShieldIcon));\n"
     "      iris_tls_view_->SetSummary(u\"Connection details\",\n"
     "                                 views::style::STYLE_BODY_3_MEDIUM);\n"
     "      iris_tls_view_->SetDetails(iris_tls);\n"
     "    }\n"
     "  }\n\n"
     "  if (identity_info.show_change_password_buttons) {\n",
     "iris::GetTlsDetailsText", "Connection details section")
PY
echo "=== Page Info TLS details applied ==="
