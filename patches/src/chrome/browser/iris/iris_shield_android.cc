// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: JNI for org.chromium.chrome.browser.iris.IrisShield — the Android shield (toolbar count + sheet). Counts come
// from iris::ShieldStats (attached to every tab by tab_helpers.cc), the switches from iris_shield_settings.h, the
// connection lines from iris_tls_info.h: the same sources as the desktop shield.

#include <jni.h>

#include <string>
#include <vector>

#include "base/android/jni_android.h"
#include "base/android/jni_string.h"
#include "base/android/scoped_java_ref.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/iris/iris_shield_settings.h"
#include "chrome/browser/iris/iris_shield_stats.h"
#include "chrome/browser/iris/iris_tls_info.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "third_party/jni_zero/default_conversions.h"
#include "url/gurl.h"

// Must come after all headers that specialize FromJniType() / ToJniType().
#include "chrome/android/chrome_jni_headers/IrisShield_jni.h"

namespace {

using JIrisShield = ::org::chromium::chrome::browser::iris::JIrisShield;

// Tells one Java IrisShield when the counts of its tab change.
class ShieldObserver : public iris::ShieldStats::Observer,
                       public content::WebContentsObserver {
 public:
  ShieldObserver(JNIEnv* env,
                 const jni_zero::JavaRef<JIrisShield>& java_shield,
                 content::WebContents* web_contents)
      : content::WebContentsObserver(web_contents),
        java_shield_(env, java_shield),
        stats_(iris::ShieldStats::FromWebContents(web_contents)) {
    if (stats_) {
      stats_->AddObserver(this);
    }
  }

  ShieldObserver(const ShieldObserver&) = delete;
  ShieldObserver& operator=(const ShieldObserver&) = delete;

  ~ShieldObserver() override { StopObserving(); }

  // iris::ShieldStats::Observer:
  void OnShieldStatsChanged() override {
    Java_IrisShield_onStatsChanged(base::android::AttachCurrentThread(),
                                   java_shield_);
  }

  // content::WebContentsObserver: the stats go away with the tab.
  void WebContentsDestroyed() override { StopObserving(); }

 private:
  void StopObserving() {
    if (stats_) {
      stats_->RemoveObserver(this);
      stats_ = nullptr;
    }
  }

  base::android::ScopedJavaGlobalRef<jobject> java_shield_;
  raw_ptr<iris::ShieldStats> stats_;
};

}  // namespace

static int64_t JNI_IrisShield_Init(JNIEnv* env,
                                 const jni_zero::JavaRef<JIrisShield>& caller,
                                 content::WebContents* web_contents) {
  if (!web_contents) {
    return 0;
  }
  return reinterpret_cast<intptr_t>(
      new ShieldObserver(env, caller, web_contents));
}

static void JNI_IrisShield_Destroy(JNIEnv* env, int64_t observer) {
  delete reinterpret_cast<ShieldObserver*>(static_cast<intptr_t>(observer));
}

// {total, ads and trackers, cookies, fingerprints, lifetime}; zeros when the
// tab has no stats.
static std::vector<int32_t> JNI_IrisShield_GetCounts(
    JNIEnv* env,
    content::WebContents* web_contents) {
  iris::ShieldStats* stats =
      web_contents ? iris::ShieldStats::FromWebContents(web_contents) : nullptr;
  if (!stats) {
    return {0, 0, 0, 0, 0};
  }
  return {stats->total(), stats->ads(), stats->cookies(), stats->fingerprints(),
          stats->lifetime()};
}

static std::string JNI_IrisShield_GetConnectionDetails(
    JNIEnv* env,
    content::WebContents* web_contents) {
  return web_contents
             ? base::UTF16ToUTF8(iris::GetTlsDetailsText(web_contents))
             : std::string();
}

static bool IsValidSwitch(int32_t which) {
  return which >= 0 &&
         which <= static_cast<int32_t>(iris::shield::Switch::kMaxValue);
}

static bool JNI_IrisShield_IsOn(JNIEnv* env,
                                Profile* profile,
                                const std::string& url,
                                int32_t which) {
  return IsValidSwitch(which) &&
         iris::shield::IsOn(profile, GURL(url),
                            static_cast<iris::shield::Switch>(which));
}

static bool JNI_IrisShield_IsLocked(JNIEnv* env,
                                    Profile* profile,
                                    int32_t which) {
  return IsValidSwitch(which) &&
         iris::shield::IsLocked(profile,
                                static_cast<iris::shield::Switch>(which));
}

static void JNI_IrisShield_Set(JNIEnv* env,
                               Profile* profile,
                               const std::string& url,
                               int32_t which,
                               bool on) {
  if (IsValidSwitch(which)) {
    iris::shield::Set(profile, GURL(url),
                      static_cast<iris::shield::Switch>(which), on);
  }
}

static void JNI_IrisShield_SetShield(JNIEnv* env,
                                     Profile* profile,
                                     const std::string& url,
                                     bool on) {
  iris::shield::SetShield(profile, GURL(url), on);
}

static void JNI_IrisShield_Reset(JNIEnv* env,
                                 Profile* profile,
                                 const std::string& url) {
  iris::shield::Reset(profile, GURL(url));
}

DEFINE_JNI(IrisShield)
