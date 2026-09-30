// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B10): os_crypt_async key provider backed by the app-lock data key (iris_app_lock.h).
// Registered with the highest precedence, so while the lock is on and unlocked, new cookies, saved logins,
// bookmarks and sessions are encrypted with the passphrase-protected key (tag "i10", AES-256-GCM). The other
// providers stay registered, so data written earlier with them stays readable.

#ifndef CHROME_BROWSER_IRIS_IRIS_KEY_PROVIDER_H_
#define CHROME_BROWSER_IRIS_IRIS_KEY_PROVIDER_H_

#include "base/memory/raw_ptr.h"
#include "components/os_crypt/async/browser/key_provider.h"

class PrefService;

class IrisKeyProvider : public os_crypt_async::KeyProvider {
 public:
  // Above every upstream Linux provider (15, 10, 5).
  static constexpr size_t kPrecedence = 20u;

  explicit IrisKeyProvider(PrefService* local_state);
  ~IrisKeyProvider() override;

  // os_crypt_async::KeyProvider:
  void GetKey(KeyCallback callback) override;
  bool UseForEncryption() override;

 private:
  raw_ptr<PrefService> local_state_;
};

#endif  // CHROME_BROWSER_IRIS_IRIS_KEY_PROVIDER_H_
