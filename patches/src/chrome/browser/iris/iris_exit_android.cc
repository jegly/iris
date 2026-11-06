// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: JNI for org.chromium.chrome.browser.iris.IrisExit (app menu > "Exit", apply-android-exit.sh).
// If the clear-on-exit list is set (IrisShredder fills it when "Clear browsing data when Iris starts" is on), the
// data is removed now through ChromeBrowsingDataLifetimeManager::ClearBrowsingDataForOnExitPolicy, which sets
// kClearBrowsingDataOnExitDeletionPending and clears it when the removal is done (keep_browser_alive = true).
// Iris waits for that, at most 10 s; if it times out the pending flag stays set, so the next start finishes the job.

#include <jni.h>

#include "base/android/jni_android.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_lifetime_manager.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_lifetime_manager_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "components/browsing_data/core/pref_names.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"

// Must come after all headers that specialize FromJniType() / ToJniType().
#include "chrome/android/chrome_jni_headers/IrisExit_jni.h"

namespace {

void ReadyToExit() {
  Java_IrisExit_onReadyToExit(base::android::AttachCurrentThread());
}

// Deletes itself once the removal is done or the time is up.
class IrisExitWaiter {
 public:
  explicit IrisExitWaiter(PrefService* prefs) : prefs_(prefs) {
    registrar_.Init(prefs_);
    registrar_.Add(
        browsing_data::prefs::kClearBrowsingDataOnExitDeletionPending,
        base::BindRepeating(&IrisExitWaiter::OnPendingChanged,
                            base::Unretained(this)));
    timeout_.Start(FROM_HERE, base::Seconds(10),
                   base::BindOnce(&IrisExitWaiter::Finish,
                                  base::Unretained(this)));
  }
  IrisExitWaiter(const IrisExitWaiter&) = delete;
  IrisExitWaiter& operator=(const IrisExitWaiter&) = delete;
  ~IrisExitWaiter() = default;

 private:

  void OnPendingChanged() {
    if (!prefs_->GetBoolean(
            browsing_data::prefs::kClearBrowsingDataOnExitDeletionPending)) {
      Finish();
    }
  }

  void Finish() {
    if (finished_) {
      return;
    }
    finished_ = true;
    registrar_.RemoveAll();
    timeout_.Stop();
    ReadyToExit();
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE,
                                                              this);
  }

  raw_ptr<PrefService> prefs_;
  PrefChangeRegistrar registrar_;
  base::OneShotTimer timeout_;
  bool finished_ = false;
};

}  // namespace

static void JNI_IrisExit_ClearThenExit(JNIEnv* env) {
  Profile* profile = ProfileManager::GetLastUsedProfile();
  ChromeBrowsingDataLifetimeManager* manager =
      profile ? ChromeBrowsingDataLifetimeManagerFactory::GetForProfile(profile)
              : nullptr;
  if (!manager || profile->GetPrefs()
                      ->GetList(browsing_data::prefs::kClearBrowsingDataOnExitList)
                      .empty()) {
    ReadyToExit();
    return;
  }
  manager->ClearBrowsingDataForOnExitPolicy(/*keep_browser_alive=*/true);
  if (!profile->GetPrefs()->GetBoolean(
          browsing_data::prefs::kClearBrowsingDataOnExitDeletionPending)) {
    ReadyToExit();  // nothing to remove (or it finished at once)
    return;
  }
  new IrisExitWaiter(profile->GetPrefs());
}

DEFINE_JNI(IrisExit)
