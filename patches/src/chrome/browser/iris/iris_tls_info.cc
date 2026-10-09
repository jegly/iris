// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_tls_info.h"

#include <string>
#include <string_view>

#include "base/strings/strcat.h"
#include "base/strings/stringprintf.h"
#include "base/strings/utf_string_conversions.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/ssl_status.h"
#include "content/public/browser/web_contents.h"
#include "net/ssl/ssl_cipher_suite_names.h"
#include "net/ssl/ssl_connection_status_flags.h"
#include "net/ssl/ssl_info.h"
#include "third_party/boringssl/src/include/openssl/ssl.h"

namespace iris {

namespace {

int LastCommittedEntryId(content::WebContents* web_contents) {
  content::NavigationEntry* entry =
      web_contents->GetController().GetLastCommittedEntry();
  return entry ? entry->GetUniqueID() : 0;
}

// "Name (0x1301)"; just the hex value when BoringSSL has no name for it.
// The name only, no TLS code point (jegly 2026-10-09: no hex codes in the UI).
std::string NameAndValue(const char* name, uint16_t value) {
  return name ? std::string(name) : std::string("unknown");
}

}  // namespace

TlsInfoTabHelper::TlsInfoTabHelper(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents),
      content::WebContentsUserData<TlsInfoTabHelper>(*web_contents) {}

TlsInfoTabHelper::~TlsInfoTabHelper() = default;

std::optional<bool> TlsInfoTabHelper::GetEncryptedClientHello() const {
  if (entry_id_ == 0 || entry_id_ != LastCommittedEntryId(web_contents())) {
    return std::nullopt;
  }
  return encrypted_client_hello_;
}

void TlsInfoTabHelper::DidFinishNavigation(content::NavigationHandle* handle) {
  if (!handle->IsInPrimaryMainFrame() || !handle->HasCommitted()) {
    return;
  }
  if (handle->IsSameDocument()) {
    // Same connection, new entry (pushState, fragments): carry the value over.
    if (entry_id_ != 0) {
      entry_id_ = LastCommittedEntryId(web_contents());
    }
    return;
  }
  const std::optional<net::SSLInfo>& ssl_info = handle->GetSSLInfo();
  if (!ssl_info || !ssl_info->is_valid()) {
    entry_id_ = 0;
    return;
  }
  entry_id_ = LastCommittedEntryId(web_contents());
  encrypted_client_hello_ = ssl_info->encrypted_client_hello;
}

std::u16string GetTlsDetailsText(content::WebContents* web_contents) {
  if (!web_contents) {
    return std::u16string();
  }
  content::NavigationEntry* entry =
      web_contents->GetController().GetLastCommittedEntry();
  if (!entry || !entry->GetSSL().initialized ||
      entry->GetSSL().connection_status == 0) {
    return std::u16string();
  }
  const content::SSLStatus& ssl = entry->GetSSL();

  const int version_id =
      net::SSLConnectionStatusToVersion(ssl.connection_status);
  const char* version = nullptr;
  net::SSLVersionToString(&version, version_id);
  // QUIC always carries a TLS 1.3 handshake; say so.
  if (version_id == net::SSL_CONNECTION_VERSION_QUIC) {
    version = "QUIC (TLS 1.3)";
  }
  uint16_t cipher_suite =
      net::SSLConnectionStatusToCipherSuite(ssl.connection_status);
  const SSL_CIPHER* cipher = SSL_get_cipher_by_value(cipher_suite);

  std::string text = base::StrCat(
      {"Protocol: ", version ? version : "unknown", "\nCipher suite: ",
       NameAndValue(cipher ? SSL_CIPHER_standard_name(cipher) : nullptr,
                    cipher_suite)});
  // The hash / key-derivation function is part of the TLS 1.3 cipher suite name
  // (..._SHA256 or ..._SHA384): it is what HKDF uses to derive the session keys.
  if (cipher) {
    const std::string_view suite = SSL_CIPHER_standard_name(cipher);
    if (suite.ends_with("SHA384")) {
      base::StrAppend(&text, {"\nHash / key derivation: SHA-384 (HKDF)"});
    } else if (suite.ends_with("SHA256")) {
      base::StrAppend(&text, {"\nHash / key derivation: SHA-256 (HKDF)"});
    }
  }
  if (ssl.key_exchange_group) {
    base::StrAppend(&text, {"\nKey exchange: ",
                            NameAndValue(SSL_get_curve_name(ssl.key_exchange_group),
                                         ssl.key_exchange_group)});
  }
  if (ssl.peer_signature_algorithm) {
    base::StrAppend(
        &text, {"\nServer signature: ",
                NameAndValue(SSL_get_signature_algorithm_name(
                                 ssl.peer_signature_algorithm,
                                 /*include_curve=*/1),
                             ssl.peer_signature_algorithm)});
  }
  if (TlsInfoTabHelper* helper =
          TlsInfoTabHelper::FromWebContents(web_contents)) {
    std::optional<bool> ech = helper->GetEncryptedClientHello();
    if (ech) {
      base::StrAppend(&text, {"\nEncrypted Client Hello: ",
                              *ech ? "used" : "not used"});
    }
  }
  return base::UTF8ToUTF16(text);
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(TlsInfoTabHelper);

}  // namespace iris
