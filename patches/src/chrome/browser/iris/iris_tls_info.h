// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: TLS connection details in Page Info ("Connection is secure" subpage). Shows the protocol, cipher suite,
// key exchange group, server signature scheme and whether Encrypted Client Hello was used for the page's main
// document. Protocol/cipher/group/signature come from the committed NavigationEntry's SSLStatus; SSLStatus has no
// ECH bit, so this tab helper records net::SSLInfo::encrypted_client_hello at DidFinishNavigation (the HTTP cache
// persists that bit, so cached loads report it correctly).
// Labels are English-only for now (new grit IDs would rebuild everything; see memory/01_GOTCHAS.md) — localize
// with the other Iris strings.

#ifndef CHROME_BROWSER_IRIS_IRIS_TLS_INFO_H_
#define CHROME_BROWSER_IRIS_IRIS_TLS_INFO_H_

#include <optional>
#include <string>

#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

namespace iris {

class TlsInfoTabHelper : public content::WebContentsObserver,
                         public content::WebContentsUserData<TlsInfoTabHelper> {
 public:
  TlsInfoTabHelper(const TlsInfoTabHelper&) = delete;
  TlsInfoTabHelper& operator=(const TlsInfoTabHelper&) = delete;
  ~TlsInfoTabHelper() override;

  // Whether the last committed page's main document used ECH; nullopt if unknown.
  std::optional<bool> GetEncryptedClientHello() const;

  // content::WebContentsObserver:
  void DidFinishNavigation(content::NavigationHandle* handle) override;

 private:
  friend class content::WebContentsUserData<TlsInfoTabHelper>;
  explicit TlsInfoTabHelper(content::WebContents* web_contents);

  // NavigationEntry unique id the ECH value belongs to (0 = none).
  int entry_id_ = 0;
  bool encrypted_client_hello_ = false;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

// Multi-line description of the page's TLS connection, or "" when there is none (http, chrome:// pages, ...).
std::u16string GetTlsDetailsText(content::WebContents* web_contents);

}  // namespace iris

#endif  // CHROME_BROWSER_IRIS_IRIS_TLS_INFO_H_
