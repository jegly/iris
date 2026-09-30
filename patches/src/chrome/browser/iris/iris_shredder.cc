// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_shredder.h"

#include "base/functional/bind.h"
#include "base/time/time.h"
#include "chrome/browser/browsing_data/chrome_browsing_data_remover_constants.h"
#include "chrome/browser/profiles/profile.h"
#include "components/pref_registry/pref_registry_syncable.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browsing_data_remover.h"
#include "ui/base/clipboard/scoped_clipboard_writer.h"

// static
void IrisShredder::RegisterProfilePrefs(
    user_prefs::PrefRegistrySyncable* registry) {
  registry->RegisterBooleanPref(kEnabledPref, false);
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
}

IrisShredder::~IrisShredder() = default;

void IrisShredder::UpdateClipboardClearing() {
  // The clipboard is shared by all profiles; the last change wins.
  ui::ScopedClipboardWriter::SetIrisClearCopiedTextAfter(
      profile_->GetPrefs()->GetBoolean(kEnabledPref)
          ? std::optional<base::TimeDelta>(base::Seconds(30))
          : std::nullopt);
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
