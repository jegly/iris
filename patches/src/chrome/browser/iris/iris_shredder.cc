// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_shredder.h"

#include "base/functional/bind.h"
#include "base/values.h"
#include "base/time/time.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_remover_constants.h"
#include "chrome/browser/profiles/profile.h"
#include "components/browsing_data/core/pref_names.h"
#include "components/language/core/browser/pref_names.h"
#include "components/pref_registry/pref_registry_syncable.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browsing_data_remover.h"
#include "ui/base/clipboard/scoped_clipboard_writer.h"

// static
void IrisShredder::RegisterProfilePrefs(
    user_prefs::PrefRegistrySyncable* registry) {
  registry->RegisterBooleanPref(kEnabledPref, false);
  registry->RegisterBooleanPref(kCoarseTimersPref, false);
  registry->RegisterBooleanPref(kStandardLocalePref, false);
  registry->RegisterBooleanPref(kMemoryCachePref, false);
  registry->RegisterBooleanPref(kClearOnExitPref, false);
  registry->RegisterStringPref(kSavedAcceptLanguagesPref, std::string());
}

IrisShredder::IrisShredder(Profile* profile) : profile_(profile) {
  first_run_.Start(FROM_HERE, base::Minutes(1),
                   base::BindOnce(&IrisShredder::Run, base::Unretained(this)));
  hourly_.Start(FROM_HERE, base::Hours(1),
                base::BindRepeating(&IrisShredder::Run,
                                    base::Unretained(this)));
  pref_change_registrar_.Init(profile_->GetPrefs());
  pref_change_registrar_.Add(
      kEnabledPref, base::BindRepeating(&IrisShredder::UpdateClipboardClearing,
                                        base::Unretained(this)));
  // At start only switch it on: a profile with the setting off (e.g. guest)
  // must not turn it off for a profile that has it on.
  if (profile_->GetPrefs()->GetBoolean(kEnabledPref)) {
    UpdateClipboardClearing();
  }
  pref_change_registrar_.Add(
      kStandardLocalePref,
      base::BindRepeating(&IrisShredder::ApplyStandardLocale,
                          base::Unretained(this)));
  pref_change_registrar_.Add(
      kClearOnExitPref, base::BindRepeating(&IrisShredder::ApplyClearOnExit,
                                            base::Unretained(this)));
  ApplyStandardLocale();
  ApplyClearOnExit();
}

IrisShredder::~IrisShredder() = default;

void IrisShredder::UpdateClipboardClearing() {
  // The clipboard is shared by all profiles; the last change wins.
  ui::ScopedClipboardWriter::SetIrisClearCopiedTextAfter(
      profile_->GetPrefs()->GetBoolean(kEnabledPref)
          ? std::optional<base::TimeDelta>(base::Seconds(30))
          : std::nullopt);
}

void IrisShredder::ApplyStandardLocale() {
  PrefService* prefs = profile_->GetPrefs();
  constexpr char kStandard[] = "en-US";
  const std::string current = prefs->GetString(language::prefs::kAcceptLanguages);
  if (prefs->GetBoolean(kStandardLocalePref)) {
    if (current != kStandard) {
      prefs->SetString(kSavedAcceptLanguagesPref, current);
      prefs->SetString(language::prefs::kAcceptLanguages, kStandard);
    }
  } else if (prefs->HasPrefPath(kSavedAcceptLanguagesPref)) {
    const std::string saved = prefs->GetString(kSavedAcceptLanguagesPref);
    if (!saved.empty()) {
      prefs->SetString(language::prefs::kAcceptLanguages, saved);
    }
    prefs->ClearPref(kSavedAcceptLanguagesPref);
  }
}

void IrisShredder::ApplyClearOnExit() {
  PrefService* prefs = profile_->GetPrefs();
  base::ListValue types;
  types.Append("browsing_history");
  types.Append("download_history");
  types.Append("cookies_and_other_site_data");
  types.Append("cached_images_and_files");
  if (prefs->GetBoolean(kClearOnExitPref)) {
    prefs->SetList(browsing_data::prefs::kClearBrowsingDataOnExitList,
                   types.Clone());
    // Also clear at the next start (after a crash; on Android the only time).
    prefs->SetBoolean(
        browsing_data::prefs::kClearBrowsingDataOnExitDeletionPending, true);
  } else if (prefs->GetList(browsing_data::prefs::kClearBrowsingDataOnExitList) ==
             types) {
    prefs->ClearPref(browsing_data::prefs::kClearBrowsingDataOnExitList);
    prefs->ClearPref(
        browsing_data::prefs::kClearBrowsingDataOnExitDeletionPending);
  }
}

void IrisShredder::Run() {
  if (!profile_->GetPrefs()->GetBoolean(kEnabledPref)) {
    return;
  }
  content::BrowsingDataRemover* remover = profile_->GetBrowsingDataRemover();
  const base::Time now = base::Time::Now();
  constexpr auto kWeb =
      content::BrowsingDataRemover::ORIGIN_TYPE_UNPROTECTED_WEB;
  remover->Remove(base::Time(), now - base::Hours(24),
                  chrome_browsing_data_remover::DATA_TYPE_SITE_DATA, kWeb);
  remover->Remove(base::Time(), now - base::Hours(12),
                  content::BrowsingDataRemover::DATA_TYPE_CACHE, kWeb);
  remover->Remove(base::Time(), now - base::Days(7),
                  content::BrowsingDataRemover::DATA_TYPE_DOWNLOADS, kWeb);
}

// static
IrisShredderFactory* IrisShredderFactory::GetInstance() {
  static base::NoDestructor<IrisShredderFactory> instance;
  return instance.get();
}

IrisShredderFactory::IrisShredderFactory()
    : ProfileKeyedServiceFactory(
          "IrisShredder",
          ProfileSelections::Builder()
              .WithRegular(ProfileSelection::kOriginalOnly)
              .WithGuest(ProfileSelection::kNone)
              .WithSystem(ProfileSelection::kNone)
              .WithAshInternals(ProfileSelection::kNone)
              .Build()) {}

IrisShredderFactory::~IrisShredderFactory() = default;

std::unique_ptr<KeyedService>
IrisShredderFactory::BuildServiceInstanceForBrowserContext(
    content::BrowserContext* context) const {
  return std::make_unique<IrisShredder>(Profile::FromBrowserContext(context));
}

bool IrisShredderFactory::ServiceIsCreatedWithBrowserContext() const {
  return true;
}
