// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B7): automatic data deletion, OFF by default (Settings -> Privacy and security ->
// "Delete browsing data automatically"). When on, every hour (and a minute after start) it deletes:
//   cookies and site data older than 24 hours, cached files older than 12 hours,
//   the downloads list older than 7 days.
// While on, text copied in Iris is also cleared from the clipboard after 30 seconds if it is still there
// (ui::ScopedClipboardWriter, apply-clipboard-clear.sh).
// It uses Chromium's own BrowsingDataRemover; nothing is sent anywhere.

#ifndef CHROME_BROWSER_IRIS_IRIS_SHREDDER_H_
#define CHROME_BROWSER_IRIS_IRIS_SHREDDER_H_

#include <memory>

#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/timer/timer.h"
#include "components/prefs/pref_change_registrar.h"
#include "chrome/browser/profiles/profile_keyed_service_factory.h"
#include "components/keyed_service/core/keyed_service.h"

class Profile;

namespace user_prefs {
class PrefRegistrySyncable;
}

class IrisShredder : public KeyedService {
 public:
  // Profile pref, default false.
  static constexpr char kEnabledPref[] = "iris.shredding.enabled";
  static void RegisterProfilePrefs(user_prefs::PrefRegistrySyncable* registry);

  explicit IrisShredder(Profile* profile);
  IrisShredder(const IrisShredder&) = delete;
  IrisShredder& operator=(const IrisShredder&) = delete;
  ~IrisShredder() override;

 private:
  void Run();
  void UpdateClipboardClearing();

  raw_ptr<Profile> profile_;
  base::OneShotTimer first_run_;
  base::RepeatingTimer hourly_;
  PrefChangeRegistrar pref_change_registrar_;
};

class IrisShredderFactory : public ProfileKeyedServiceFactory {
 public:
  static IrisShredderFactory* GetInstance();

 private:
  friend base::NoDestructor<IrisShredderFactory>;
  IrisShredderFactory();
  ~IrisShredderFactory() override;

  // ProfileKeyedServiceFactory:
  std::unique_ptr<KeyedService> BuildServiceInstanceForBrowserContext(
      content::BrowserContext* context) const override;
  bool ServiceIsCreatedWithBrowserContext() const override;
};

#endif  // CHROME_BROWSER_IRIS_IRIS_SHREDDER_H_
