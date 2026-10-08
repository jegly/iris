// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B7): automatic data deletion, OFF by default (Settings -> Privacy and security ->
// "Delete browsing data automatically"). When on, every hour (and a minute after start) it deletes:
//   cookies and site data older than 24 hours, cached files older than 12 hours,
//   the downloads list older than 7 days.
// Clipboard clearing (text copied in Iris removed after 30 s, ui::ScopedClipboardWriter, apply-clipboard-clear.sh)
// is its own toggle since 2026-10-08 (kClearClipboardPref, apply-privacy-toggles-3.sh); profiles that had automatic
// deletion on keep it on.
// It uses Chromium's own BrowsingDataRemover; nothing is sent anywhere.
//
// It also keeps two "Privacy and security" toggles in effect (apply-privacy-toggles-2.sh, all off by default):
//  - "Use UTC and US English for websites" (kStandardLocalePref): while on, the website language list
//    (intl.accept_languages) is "en-US"; the user's own list is saved and put back when it is turned off.
//    (The UTC time zone part is a renderer switch, see chrome_content_browser_client.cc.)
//  - "Clear browsing data when Iris closes" (kClearOnExitPref): fills Chromium's own ClearBrowsingDataOnExitList
//    (history, downloads list, cookies + site data, cache; not passwords or site settings), which is cleared when the
//    last window closes (desktop) and, because the deletion is marked pending, again at every start (catches crashes;
//    on Android, where apps do not really close, this is when it happens).

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
  // Profile prefs for the hardening toggles (apply-privacy-toggles-2.sh), default false.
  static constexpr char kCoarseTimersPref[] = "iris.privacy.coarse_timers";
  static constexpr char kStandardLocalePref[] = "iris.privacy.standard_locale";
  static constexpr char kMemoryCachePref[] = "iris.privacy.memory_cache";
  static constexpr char kClearOnExitPref[] = "iris.privacy.clear_on_exit";
  // The user's own website language list while kStandardLocalePref is on.
  static constexpr char kSavedAcceptLanguagesPref[] =
      "iris.privacy.saved_accept_languages";
  // apply-privacy-toggles-3.sh, default false.
  static constexpr char kClearClipboardPref[] = "iris.privacy.clear_clipboard";
  static constexpr char kBlockWebFontsPref[] = "iris.privacy.block_web_fonts";
  static constexpr char kBlockAutoplayPref[] = "iris.privacy.block_autoplay";
  static void RegisterProfilePrefs(user_prefs::PrefRegistrySyncable* registry);

  explicit IrisShredder(Profile* profile);
  IrisShredder(const IrisShredder&) = delete;
  IrisShredder& operator=(const IrisShredder&) = delete;
  ~IrisShredder() override;

 private:
  void Run();
  void UpdateClipboardClearing();
  void ApplyStandardLocale();
  void ApplyClearOnExit();

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
