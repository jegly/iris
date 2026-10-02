// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_key_provider.h"

#include <utility>

#include "base/functional/bind.h"
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
  if (!key && iris_app_lock::IsEnabled(local_state_) &&
      !iris_app_lock::IsUnlocked()) {
    // Android: the browser starts before the user unlocks; answer once they do
    // (desktop unlocks before any key is requested, so it never gets here).
    iris_app_lock::RunWhenUnlocked(base::BindOnce(
        &IrisKeyProvider::GetKey, weak_factory_.GetWeakPtr(),
        std::move(callback)));
    return;
  }
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
  // Lock on = encrypt with the Iris key, even before the user has unlocked
  // (Android starts first; GetKey() then waits for the unlock).
  return iris_app_lock::IsEnabled(local_state_);
}
