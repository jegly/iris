// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B8 + B10): app lock and passphrase encryption.
//
// B8: when a passphrase is set, Iris asks for it before any window opens (IrisUnlockDialog, shown from
// ChromeBrowserMainParts next to the EULA dialog). Quit exits without opening anything.
// B10: the passphrase protects a random 256-bit data key. IrisKeyProvider hands that key to os_crypt_async,
// which Chromium uses for cookies, saved logins, bookmarks and sessions (tag "i10", AES-256-GCM). Data written
// before the lock was set stays readable with its old key and is re-encrypted as it is rewritten.
//
// Storage, all in Local State (nothing secret in plain text while the lock is on):
//   salt      16 random bytes;
//   verifier  SHA-256 of the second half of scrypt(passphrase, salt) (N=2^16, r=8, p=1, 64 bytes);
//   wrapped   AES-256-GCM(key = first half of that scrypt output) of the data key: nonce || ciphertext.
// Changing the passphrase re-wraps the same data key (no data is re-encrypted). Turning the lock off stores the
// data key unwrapped (plain_key) so data encrypted with it stays readable; turning it on again re-uses it.
// There is no recovery: a forgotten passphrase means the data encrypted with the data key is lost.

#ifndef CHROME_BROWSER_IRIS_IRIS_APP_LOCK_H_
#define CHROME_BROWSER_IRIS_IRIS_APP_LOCK_H_

#include <array>
#include <cstdint>
#include <optional>
#include <string_view>

class PrefRegistrySimple;
class PrefService;

namespace iris_app_lock {

inline constexpr char kEnabledPref[] = "iris.app_lock.enabled";
inline constexpr char kSaltPref[] = "iris.app_lock.salt";
inline constexpr char kVerifierPref[] = "iris.app_lock.verifier";
inline constexpr char kWrappedKeyPref[] = "iris.app_lock.wrapped_key";
inline constexpr char kPlainKeyPref[] = "iris.app_lock.plain_key";

using DataKey = std::array<uint8_t, 32>;

enum class Result {
  kOk,
  kWrongPassphrase,
  kEmptyPassphrase,
};

void RegisterLocalStatePrefs(PrefRegistrySimple* registry);

bool IsEnabled(PrefService* local_state);

// True once Unlock() (or SetPassphrase()) succeeded in this run.
bool IsUnlocked();

// Checks `passphrase`; on success keeps the data key in memory for this run.
bool Unlock(PrefService* local_state, std::u16string_view passphrase);

// The data key for this run: the unlocked key, or the stored plain key when
// the lock was turned off after being used. std::nullopt if neither.
std::optional<DataKey> GetDataKey(PrefService* local_state);

// Sets the passphrase (lock off) or changes it (lock on; `current` must be
// right). Slow on purpose (scrypt): call off the UI thread where possible.
Result SetPassphrase(PrefService* local_state,
                     std::u16string_view current,
                     std::u16string_view new_passphrase);

// Turns the lock off; `current` must be right.
Result Remove(PrefService* local_state, std::u16string_view current);

}  // namespace iris_app_lock

#endif  // CHROME_BROWSER_IRIS_IRIS_APP_LOCK_H_
