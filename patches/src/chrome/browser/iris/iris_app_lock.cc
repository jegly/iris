// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_app_lock.h"

#include <string>
#include <vector>

#include "base/base64.h"
#include "base/check.h"
#include "base/containers/span.h"
#include "base/rand_util.h"
#include "base/strings/utf_string_conversions.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"
#include "crypto/aead.h"
#include "crypto/sha2.h"
#include "third_party/boringssl/src/include/openssl/evp.h"
#include "third_party/boringssl/src/include/openssl/mem.h"

namespace iris_app_lock {

namespace {

constexpr size_t kSaltSize = 16;
constexpr size_t kNonceSize = 12;
// scrypt: 64 MiB of memory per attempt (128 * r * N), about a quarter second.
constexpr uint64_t kScryptN = uint64_t{1} << 16;
constexpr uint64_t kScryptR = 8;
constexpr uint64_t kScryptP = 1;
constexpr size_t kScryptMaxMemory = size_t{128} * 1024 * 1024;

struct Derived {
  std::array<uint8_t, 32> kek;       // wraps the data key
  std::array<uint8_t, 32> verifier;  // stored, to check the passphrase
};

std::optional<DataKey>& UnlockedKey() {
  static std::optional<DataKey> key;
  return key;
}

std::optional<Derived> Derive(std::u16string_view passphrase,
                              base::span<const uint8_t> salt) {
  std::string utf8 = base::UTF16ToUTF8(passphrase);
  std::array<uint8_t, 64> out;
  const int ok = EVP_PBE_scrypt(utf8.data(), utf8.size(), salt.data(),
                                salt.size(), kScryptN, kScryptR, kScryptP,
                                kScryptMaxMemory, out.data(), out.size());
  OPENSSL_cleanse(utf8.data(), utf8.size());
  if (ok != 1) {
    OPENSSL_cleanse(out.data(), out.size());
    return std::nullopt;
  }
  Derived d;
  base::span(d.kek).copy_from(base::span(out).first<32>());
  base::span(d.verifier)
      .copy_from(crypto::SHA256Hash(base::span(out).last<32>()));
  OPENSSL_cleanse(out.data(), out.size());
  return d;
}

std::optional<std::vector<uint8_t>> ReadBytes(PrefService* local_state,
                                              const char* pref) {
  const std::string& value = local_state->GetString(pref);
  if (value.empty()) {
    return std::nullopt;
  }
  return base::Base64Decode(value);
}

// Checks `passphrase` against the stored lock; returns the data key if right.
std::optional<DataKey> OpenWithPassphrase(PrefService* local_state,
                                          std::u16string_view passphrase) {
  std::optional<std::vector<uint8_t>> salt = ReadBytes(local_state, kSaltPref);
  std::optional<std::vector<uint8_t>> verifier =
      ReadBytes(local_state, kVerifierPref);
  std::optional<std::vector<uint8_t>> wrapped =
      ReadBytes(local_state, kWrappedKeyPref);
  if (!salt || !verifier || !wrapped || verifier->size() != 32 ||
      wrapped->size() <= kNonceSize) {
    return std::nullopt;
  }
  std::optional<Derived> derived = Derive(passphrase, *salt);
  if (!derived) {
    return std::nullopt;
  }
  if (CRYPTO_memcmp(derived->verifier.data(), verifier->data(), 32) != 0) {
    OPENSSL_cleanse(derived->kek.data(), derived->kek.size());
    return std::nullopt;
  }
  base::span<const uint8_t> sealed(*wrapped);
  std::optional<std::vector<uint8_t>> plain = crypto::aead::Open(
      crypto::aead::AES_256_GCM, derived->kek, sealed.subspan(kNonceSize),
      sealed.first(kNonceSize), base::span<const uint8_t>());
  OPENSSL_cleanse(derived->kek.data(), derived->kek.size());
  if (!plain || plain->size() != 32) {
    return std::nullopt;
  }
  DataKey key;
  base::span(key).copy_from(*plain);
  OPENSSL_cleanse(plain->data(), plain->size());
  return key;
}

void StoreLock(PrefService* local_state,
               std::u16string_view passphrase,
               const DataKey& key) {
  std::array<uint8_t, kSaltSize> salt;
  base::RandBytes(salt);
  std::optional<Derived> derived = Derive(passphrase, salt);
  CHECK(derived);
  std::array<uint8_t, kNonceSize> nonce;
  base::RandBytes(nonce);
  std::vector<uint8_t> sealed =
      crypto::aead::Seal(crypto::aead::AES_256_GCM, derived->kek, key, nonce,
                         base::span<const uint8_t>());
  OPENSSL_cleanse(derived->kek.data(), derived->kek.size());
  CHECK(!sealed.empty());
  std::vector<uint8_t> wrapped(nonce.begin(), nonce.end());
  wrapped.insert(wrapped.end(), sealed.begin(), sealed.end());

  local_state->SetString(kSaltPref, base::Base64Encode(salt));
  local_state->SetString(kVerifierPref, base::Base64Encode(derived->verifier));
  local_state->SetString(kWrappedKeyPref, base::Base64Encode(wrapped));
  local_state->ClearPref(kPlainKeyPref);
  local_state->SetBoolean(kEnabledPref, true);
  local_state->CommitPendingWrite();
}

}  // namespace

void RegisterLocalStatePrefs(PrefRegistrySimple* registry) {
  registry->RegisterBooleanPref(kEnabledPref, false);
  registry->RegisterStringPref(kSaltPref, std::string());
  registry->RegisterStringPref(kVerifierPref, std::string());
  registry->RegisterStringPref(kWrappedKeyPref, std::string());
  registry->RegisterStringPref(kPlainKeyPref, std::string());
}

bool IsEnabled(PrefService* local_state) {
  return local_state && local_state->GetBoolean(kEnabledPref);
}

bool IsUnlocked() {
  return UnlockedKey().has_value();
}

bool Unlock(PrefService* local_state, std::u16string_view passphrase) {
  std::optional<DataKey> key = OpenWithPassphrase(local_state, passphrase);
  if (!key) {
    return false;
  }
  UnlockedKey() = *key;
  return true;
}

std::optional<DataKey> GetDataKey(PrefService* local_state) {
  if (UnlockedKey()) {
    return UnlockedKey();
  }
  if (!local_state) {
    return std::nullopt;
  }
  std::optional<std::vector<uint8_t>> plain =
      ReadBytes(local_state, kPlainKeyPref);
  if (!plain || plain->size() != 32) {
    return std::nullopt;
  }
  DataKey key;
  base::span(key).copy_from(*plain);
  return key;
}

Result SetPassphrase(PrefService* local_state,
                     std::u16string_view current,
                     std::u16string_view new_passphrase) {
  if (new_passphrase.empty()) {
    return Result::kEmptyPassphrase;
  }
  DataKey key;
  if (IsEnabled(local_state)) {
    std::optional<DataKey> existing = OpenWithPassphrase(local_state, current);
    if (!existing) {
      return Result::kWrongPassphrase;
    }
    key = *existing;
  } else if (std::optional<DataKey> previous = GetDataKey(local_state)) {
    key = *previous;  // lock was on before: keep data encrypted with it readable
  } else {
    base::RandBytes(key);
  }
  StoreLock(local_state, new_passphrase, key);
  UnlockedKey() = key;
  return Result::kOk;
}

Result Remove(PrefService* local_state, std::u16string_view current) {
  if (!IsEnabled(local_state)) {
    return Result::kOk;
  }
  std::optional<DataKey> key = OpenWithPassphrase(local_state, current);
  if (!key) {
    return Result::kWrongPassphrase;
  }
  local_state->SetString(kPlainKeyPref, base::Base64Encode(*key));
  local_state->ClearPref(kSaltPref);
  local_state->ClearPref(kVerifierPref);
  local_state->ClearPref(kWrappedKeyPref);
  local_state->SetBoolean(kEnabledPref, false);
  local_state->CommitPendingWrite();
  return Result::kOk;
}

}  // namespace iris_app_lock
