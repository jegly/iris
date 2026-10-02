#!/usr/bin/env bash
# Iris — Android Page Info: the two TLS facts Android was missing (jegly 2026-10-02 "get that all done now").
# Verified against this checkout and on the phone: Android's "Connection is secure" page ALREADY shows the TLS version,
# cipher and key exchange (upstream page_info_strings.grdp). Desktop Iris additionally shows the server's signature
# scheme and whether Encrypted Client Hello was used (apply-page-info-tls.sh). This adds those two sentences to the
# Android text, after the upstream cipher sentence (Android only: desktop Iris shows them in its own section).
#  - signature scheme: VisibleSecurityState::peer_signature_algorithm, named by BoringSSL (already used there).
#  - ECH: iris::TlsInfoTabHelper (attached on Android too, chrome/browser/ui/tab_helpers.cc) via a new optional
#    PageInfoDelegate method IrisGetEncryptedClientHello() (default "unknown"; ChromePageInfoDelegate answers it).
# English-only sentences (no new grit IDs). Needs apply-page-info-tls.sh (iris_tls_info) first.
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

p = "components/page_info/page_info_delegate.h"
# Declared here, default (nullopt) defined in page_info.cc: chromium-style rejects inline virtual bodies.
DECL = "  virtual std::optional<bool> IrisGetEncryptedClientHello();\n"
M = ("\n  // Iris: whether the page's main document used Encrypted Client Hello; nullopt if unknown.\n" + DECL)
s = open(p).read()
first = "  virtual std::optional<bool> IrisGetEncryptedClientHello() { return std::nullopt; }\n"  # first version
if first in s:
    open(p, "w").write(s.replace(first, DECL, 1)); print("OK   %s : inline default moved to page_info.cc" % p)
edit(p, "  virtual void OnSuspiciousSiteMarkAsSafe() {}\n};\n",
     "  virtual void OnSuspiciousSiteMarkAsSafe() {}\n" + M + "};\n", DECL, "delegate method")

p = "chrome/browser/ui/page_info/chrome_page_info_delegate.h"
edit(p, "  void OnSuspiciousSiteMarkAsSafe() override;\n",
     "  void OnSuspiciousSiteMarkAsSafe() override;\n"
     "  std::optional<bool> IrisGetEncryptedClientHello() override;  // Iris\n",
     "IrisGetEncryptedClientHello() override;  // Iris", "delegate override decl")
p = "chrome/browser/ui/page_info/chrome_page_info_delegate.cc"
# nogncheck: chrome/browser:core (iris_tls_info.h) depends on this target, so gn check cannot see the include;
# both are linked into the same browser (same as upstream's chrome_page_info_ui_delegate.cc includes from core).
INC = '#include "chrome/browser/iris/iris_tls_info.h"  // nogncheck (Iris)\n'
s = open(p).read()
first = '#include "chrome/browser/iris/iris_tls_info.h"  // Iris\n'  # first version, without nogncheck
if first in s:
    open(p, "w").write(s.replace(first, INC, 1)); print("OK   %s : include marked nogncheck" % p)
edit(p, '#include "chrome/browser/browser_process.h"\n', '#include "chrome/browser/browser_process.h"\n' + INC,
     INC, "include")
edit(p, "bool ChromePageInfoDelegate::IsIncognitoProfile() {\n",
     "// Iris: Encrypted Client Hello state recorded by iris::TlsInfoTabHelper.\n"
     "std::optional<bool> ChromePageInfoDelegate::IrisGetEncryptedClientHello() {\n"
     "  iris::TlsInfoTabHelper* helper =\n"
     "      web_contents_ ? iris::TlsInfoTabHelper::FromWebContents(web_contents_)\n"
     "                    : nullptr;\n"
     "  return helper ? helper->GetEncryptedClientHello() : std::nullopt;\n"
     "}\n\n"
     "bool ChromePageInfoDelegate::IsIncognitoProfile() {\n",
     "std::optional<bool> ChromePageInfoDelegate::IrisGetEncryptedClientHello() {", "delegate override")

p = "components/page_info/page_info.cc"
old = ("      site_connection_details_ += l10n_util::GetStringFUTF16(\n"
       "          IDS_PAGE_INFO_SECURITY_TAB_ENCRYPTION_DETAILS, ASCIIToUTF16(cipher),\n"
       "          ASCIIToUTF16(mac), ASCIIToUTF16(key_exchange));\n"
       "    }\n")
new = old + ("#if BUILDFLAG(IS_ANDROID)\n"
             "    // Iris: server signature scheme + Encrypted Client Hello (desktop Iris shows\n"
             "    // these in its own Page Info section).\n"
             "    if (visible_security_state.peer_signature_algorithm) {\n"
             "      const char* signature = SSL_get_signature_algorithm_name(\n"
             "          visible_security_state.peer_signature_algorithm, /*include_curve=*/1);\n"
             "      site_connection_details_ += u\"\\n\\nThe server signed the connection with \";\n"
             "      site_connection_details_ +=\n"
             "          signature ? ASCIIToUTF16(signature) : u\"an unknown algorithm\";\n"
             "      site_connection_details_ += u\".\";\n"
             "    }\n"
             "    if (std::optional<bool> ech = delegate_->IrisGetEncryptedClientHello()) {\n"
             "      site_connection_details_ +=\n"
             "          *ech ? u\"\\n\\nEncrypted Client Hello was used: the site's name was \"\n"
             "                 u\"hidden from the network.\"\n"
             "               : u\"\\n\\nEncrypted Client Hello was not used: the site's name \"\n"
             "                 u\"was visible to the network.\";\n"
             "    }\n"
             "#endif  // BUILDFLAG(IS_ANDROID)\n")
edit(p, old, new, "// Iris: server signature scheme + Encrypted Client Hello", "Android TLS sentences")
s = open(p).read()
D = ("\n// Iris: default for PageInfoDelegate::IrisGetEncryptedClientHello() (declared in page_info_delegate.h).\n"
     "std::optional<bool> PageInfoDelegate::IrisGetEncryptedClientHello() {\n  return std::nullopt;\n}\n")
if "std::optional<bool> PageInfoDelegate::IrisGetEncryptedClientHello() {" in s:
    print("SKIP already applied: %s (delegate default)" % p)
else:
    open(p, "w").write(s.rstrip("\n") + "\n" + D); print("OK   %s : delegate default" % p)
PY
