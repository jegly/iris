// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_shield_settings.h"

#include "base/memory/scoped_refptr.h"
#include "base/notreached.h"
#include "chrome/browser/content_settings/cookie_settings_factory.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/iris/iris_fingerprint_host.h"
#include "chrome/browser/iris/iris_user_agent.h"
#include "chrome/browser/iris/iris_web_recolor.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/content_settings/core/browser/cookie_settings.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/prefs/pref_service.h"
#include "url/gurl.h"

namespace iris::shield {
namespace {

HostContentSettingsMap* Map(Profile* profile) {
  return HostContentSettingsMapFactory::GetForProfile(profile);
}

scoped_refptr<content_settings::CookieSettings> Cookies(Profile* profile) {
  return CookieSettingsFactory::GetForProfile(profile);
}

ContentSetting Get(Profile* profile, const GURL& url, ContentSettingsType type) {
  return Map(profile)->GetContentSetting(url, url, type);
}

void Store(Profile* profile,
           const GURL& url,
           ContentSettingsType type,
           ContentSetting setting) {
  Map(profile)->SetContentSettingDefaultScope(url, GURL(), type, setting);
}

// A per-site exception only when it differs from the default.
void StoreForSite(Profile* profile,
                  const GURL& url,
                  ContentSettingsType type,
                  ContentSetting wanted) {
  Store(profile, url, type,
        wanted == Map(profile)->GetDefaultContentSetting(type)
            ? CONTENT_SETTING_DEFAULT
            : wanted);
}

void SetCookies(Profile* profile, const GURL& url, bool block) {
  if (block) {
    Cookies(profile)->ResetThirdPartyCookieSetting(url);
  } else {
    Cookies(profile)->SetThirdPartyCookieSetting(url, CONTENT_SETTING_ALLOW);
  }
}

ContentSetting AllowOrBlock(bool allow) {
  return allow ? CONTENT_SETTING_ALLOW : CONTENT_SETTING_BLOCK;
}

}  // namespace

bool IsOn(Profile* profile, const GURL& url, Switch which) {
  switch (which) {
    case Switch::kAds:
      return Get(profile, url, ContentSettingsType::ADS) !=
             CONTENT_SETTING_ALLOW;
    case Switch::kCookies:
      return !Cookies(profile)->IsThirdPartyAccessAllowed(url);
    case Switch::kJavaScript:
      return Get(profile, url, ContentSettingsType::JAVASCRIPT) !=
             CONTENT_SETTING_BLOCK;
    case Switch::kJit:
      return Get(profile, url, ContentSettingsType::JAVASCRIPT_JIT) ==
             CONTENT_SETTING_ALLOW;
    case Switch::kWebGL:
      return !IsLocked(profile, which) &&
             Get(profile, url, ContentSettingsType::IRIS_WEBGL) ==
                 CONTENT_SETTING_ALLOW;
    case Switch::kSignIn:
      return Get(profile, url, ContentSettingsType::IRIS_GOOGLE_SIGNIN) ==
             CONTENT_SETTING_ALLOW;
    case Switch::kForget:
      return Get(profile, url, ContentSettingsType::COOKIES) ==
             CONTENT_SETTING_SESSION_ONLY;
    case Switch::kRecolor:
      return iris::recolor::IsEnabled(profile) &&
             !iris::recolor::IsExcluded(profile, url);
  }
  NOTREACHED();
}

bool IsLocked(Profile* profile, Switch which) {
  switch (which) {
    case Switch::kWebGL:
      return profile->GetPrefs()->GetBoolean(prefs::kDisable3DAPIs);
    case Switch::kRecolor:
      return !iris::recolor::IsEnabled(profile);
    default:
      return false;
  }
}

void Set(Profile* profile, const GURL& url, Switch which, bool on) {
  switch (which) {
    case Switch::kAds:
      StoreForSite(profile, url, ContentSettingsType::ADS,
                   on ? CONTENT_SETTING_BLOCK : CONTENT_SETTING_ALLOW);
      return;
    case Switch::kCookies:
      SetCookies(profile, url, on);
      return;
    case Switch::kJavaScript:
      StoreForSite(profile, url, ContentSettingsType::JAVASCRIPT,
                   AllowOrBlock(on));
      return;
    case Switch::kJit:
      StoreForSite(profile, url, ContentSettingsType::JAVASCRIPT_JIT,
                   AllowOrBlock(on));
      return;
    case Switch::kWebGL:
      StoreForSite(profile, url, ContentSettingsType::IRIS_WEBGL,
                   AllowOrBlock(on));
      return;
    case Switch::kSignIn:
      StoreForSite(profile, url, ContentSettingsType::IRIS_GOOGLE_SIGNIN,
                   AllowOrBlock(on));
      return;
    case Switch::kForget:
      if (on) {
        StoreForSite(profile, url, ContentSettingsType::COOKIES,
                     CONTENT_SETTING_SESSION_ONLY);
      } else {
        // Back to the default, unless the default itself forgets every site.
        Store(profile, url, ContentSettingsType::COOKIES,
              Map(profile)->GetDefaultContentSetting(
                  ContentSettingsType::COOKIES) == CONTENT_SETTING_SESSION_ONLY
                  ? CONTENT_SETTING_ALLOW
                  : CONTENT_SETTING_DEFAULT);
      }
      return;
    case Switch::kRecolor:
      iris::recolor::SetExcluded(profile, url, !on);
      return;
  }
  NOTREACHED();
}

void SetShield(Profile* profile, const GURL& url, bool on) {
  Set(profile, url, Switch::kAds, on);
  SetCookies(profile, url, on);
  iris::SetFingerprintReadsPreset(profile, url, on ? "protected" : "real");
}

void Reset(Profile* profile, const GURL& url) {
  for (ContentSettingsType type :
       {ContentSettingsType::ADS, ContentSettingsType::JAVASCRIPT,
        ContentSettingsType::JAVASCRIPT_JIT, ContentSettingsType::IRIS_WEBGL,
        ContentSettingsType::IRIS_GOOGLE_SIGNIN, ContentSettingsType::COOKIES}) {
    Store(profile, url, type, CONTENT_SETTING_DEFAULT);
  }
  Cookies(profile)->ResetThirdPartyCookieSetting(url);
  iris::SetFingerprintReadsPreset(profile, url, "protected");
  iris::SetUserAgentPreset(profile, url, "");
  iris::recolor::SetExcluded(profile, url, false);
}

}  // namespace iris::shield
