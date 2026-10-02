// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: JNI for org.chromium.chrome.browser.iris.IrisSiteSettings — per-site "Browser identity" and "Canvas and
// audio reading" on Android, using the same website settings as desktop (iris_user_agent, iris_fingerprint_host).

#include <jni.h>

#include <string>

#include "base/android/jni_string.h"
#include "chrome/browser/iris/iris_fingerprint_host.h"
#include "chrome/browser/iris/iris_user_agent.h"
#include "chrome/browser/profiles/profile.h"
#include "third_party/jni_zero/default_conversions.h"
#include "url/gurl.h"

// Must come after all headers that specialize FromJniType() / ToJniType().
#include "chrome/android/chrome_jni_headers/IrisSiteSettings_jni.h"

static std::string JNI_IrisSiteSettings_GetUserAgentPreset(JNIEnv* env,
                                                           Profile* profile,
                                                           const std::string& origin) {
  return iris::GetUserAgentPreset(profile, GURL(origin));
}

static void JNI_IrisSiteSettings_SetUserAgentPreset(JNIEnv* env,
                                                    Profile* profile,
                                                    const std::string& origin,
                                                    const std::string& preset) {
  iris::SetUserAgentPreset(profile, GURL(origin), preset);
}

static std::string JNI_IrisSiteSettings_GetFingerprintReadsPreset(JNIEnv* env,
                                                                  Profile* profile,
                                                                  const std::string& origin) {
  return iris::GetFingerprintReadsPreset(profile, GURL(origin));
}

static void JNI_IrisSiteSettings_SetFingerprintReadsPreset(JNIEnv* env,
                                                           Profile* profile,
                                                           const std::string& origin,
                                                           const std::string& preset) {
  iris::SetFingerprintReadsPreset(profile, GURL(origin), preset);
}

DEFINE_JNI(IrisSiteSettings)
