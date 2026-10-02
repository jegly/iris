// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: JNI for org.chromium.chrome.browser.iris.IrisAppLock — the Android UI uses the same native app lock as
// desktop (chrome/browser/iris/iris_app_lock.h: scrypt passphrase, wrapped data key in Local State).

#include <jni.h>

#include <cstdint>
#include <string>

#include "base/android/jni_string.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/iris/iris_app_lock.h"
#include "third_party/jni_zero/default_conversions.h"

// Must come after all headers that specialize FromJniType() / ToJniType().
#include "chrome/android/chrome_jni_headers/IrisAppLock_jni.h"

static bool JNI_IrisAppLock_IsEnabled(JNIEnv* env) {
  return iris_app_lock::IsEnabled(g_browser_process->local_state());
}

static bool JNI_IrisAppLock_Unlock(JNIEnv* env, const std::u16string& passphrase) {
  return iris_app_lock::Unlock(g_browser_process->local_state(), passphrase);
}

static int32_t JNI_IrisAppLock_SetPassphrase(JNIEnv* env,
                                             const std::u16string& current,
                                             const std::u16string& new_passphrase) {
  return static_cast<int32_t>(iris_app_lock::SetPassphrase(
      g_browser_process->local_state(), current, new_passphrase));
}

static int32_t JNI_IrisAppLock_Remove(JNIEnv* env, const std::u16string& current) {
  return static_cast<int32_t>(
      iris_app_lock::Remove(g_browser_process->local_state(), current));
}

DEFINE_JNI(IrisAppLock)
