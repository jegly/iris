// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_key_provider.h"

#include <utility>

#include "base/types/expected.h"
#include "chrome/browser/iris/iris_app_lock.h"
#include "components/os_crypt/async/common/algorithm.mojom.h"
#include "components/os_crypt/async/common/encryptor.h"

namespace {
constexpr char kTag[] = "i10";
}  // namespace

IrisKeyProvider::IrisKeyProvider(PrefService* local_state)
    : local_state_(local_state) {}

IrisKeyProvider::~IrisKeyProvider() = default;

void IrisKeyProvider::GetKey(KeyCallback callback) {
  std::optional<iris_app_lock::DataKey> key =
      iris_app_lock::GetDataKey(local_state_);
  if (!key) {
    // Locked but not unlocked (should not happen: the unlock dialog runs
    // first) -> temporary, so nothing treats earlier data as lost. Never used
    // -> permanent (no data carries this tag).
    std::move(callback).Run(
        kTag, base::unexpected(
                  iris_app_lock::IsEnabled(local_state_)
                      ? KeyError::kTemporarilyUnavailable
                      : KeyError::kPermanentlyUnavailable));
    return;
  }
  std::move(callback).Run(
      kTag, os_crypt_async::Encryptor::Key(
                *key, os_crypt_async::mojom::Algorithm::kAES256GCM));
}

bool IrisKeyProvider::UseForEncryption() {
  return iris_app_lock::IsEnabled(local_state_) && iris_app_lock::IsUnlocked();
}
