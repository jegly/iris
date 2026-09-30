// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_user_agent.h"

#include "base/strings/stringprintf.h"
#include "base/values.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/version_info/version_info.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "third_party/blink/public/common/user_agent/user_agent_metadata.h"
#include "url/gurl.h"

namespace iris {

namespace {

// Versions follow Iris's Chromium release so the strings stay current without edits: Chrome = Iris's major,
// Firefox ~ Chrome + 3 (both ship every 4 weeks), Safari ~ one major per year (26 at Chrome 140, Sept 2025).
int ChromeMajor() {
  return static_cast<int>(version_info::GetMajorVersionNumberAsInt());
}

}  // namespace

bool IsValidUserAgentPreset(std::string_view preset) {
  return preset == "firefox_linux" || preset == "chrome_windows" ||
         preset == "safari_mac";
}

std::string UserAgentForPreset(std::string_view preset) {
  const int chrome = ChromeMajor();
  if (preset == "firefox_linux") {
    return base::StringPrintf(
        "Mozilla/5.0 (X11; Linux x86_64; rv:%d.0) Gecko/20100101 "
        "Firefox/%d.0",
        chrome + 3, chrome + 3);
  }
  if (preset == "chrome_windows") {
    return base::StringPrintf(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, "
        "like Gecko) Chrome/%d.0.0.0 Safari/537.36",
        chrome);
  }
  if (preset == "safari_mac") {
    return base::StringPrintf(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        "(KHTML, like Gecko) Version/%d.0 Safari/605.1.15",
        26 + (chrome - 140) / 13);
  }
  return std::string();
}

namespace {

// Website-setting values must be dictionaries (content_settings_pref.cc
// IsValueAllowedForType): stored as {"preset": "<id>"}. The plain string that
// 156.0.8073.0-1 stored is still read.
std::string PresetFromSettingValue(const base::Value& value) {
  if (value.is_string()) {
    return value.GetString();
  }
  if (const base::DictValue* dict = value.GetIfDict()) {
    if (const std::string* preset = dict->FindString("preset")) {
      return *preset;
    }
  }
  return std::string();
}

base::Value PresetToSettingValue(std::string_view preset) {
  base::DictValue dict;
  dict.Set("preset", preset);
  return base::Value(std::move(dict));
}

}  // namespace

std::string GetUserAgentPreset(content::BrowserContext* context,
                               const GURL& url) {
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(context);
  if (!map || !url.SchemeIsHTTPOrHTTPS()) {
    return std::string();
  }
  const base::Value value = map->GetWebsiteSetting(
      url, url, ContentSettingsType::IRIS_USER_AGENT);
  const std::string preset = PresetFromSettingValue(value);
  return IsValidUserAgentPreset(preset) ? preset : std::string();
}

void SetUserAgentPreset(content::BrowserContext* context,
                        const GURL& url,
                        std::string_view preset) {
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(context);
  if (!map || !url.SchemeIsHTTPOrHTTPS()) {
    return;
  }
  map->SetWebsiteSettingDefaultScope(
      url, GURL(), ContentSettingsType::IRIS_USER_AGENT,
      IsValidUserAgentPreset(preset) && !preset.empty()
          ? PresetToSettingValue(preset)
          : base::Value());
}

UserAgentTabHelper::UserAgentTabHelper(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents),
      content::WebContentsUserData<UserAgentTabHelper>(*web_contents) {}

UserAgentTabHelper::~UserAgentTabHelper() = default;

void UserAgentTabHelper::DidStartNavigation(content::NavigationHandle* handle) {
  if (!handle->IsInPrimaryMainFrame() || handle->IsSameDocument()) {
    return;
  }
  content::WebContents* contents = web_contents();
  const std::string preset =
      GetUserAgentPreset(contents->GetBrowserContext(), handle->GetURL());
  if (!preset.empty()) {
    contents->SetUserAgentOverride(
        blink::UserAgentOverride::UserAgentOnly(UserAgentForPreset(preset)),
        /*override_in_new_tabs=*/false);
    handle->SetIsOverridingUserAgent(true);
    return;
  }
  // Undo an identity Iris set for a previous site; leave other overrides alone.
  const std::string& current = contents->GetUserAgentOverride().ua_string_override;
  for (const char* p : {"firefox_linux", "chrome_windows", "safari_mac"}) {
    if (!current.empty() && current == UserAgentForPreset(p)) {
      handle->SetIsOverridingUserAgent(false);
      return;
    }
  }
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(UserAgentTabHelper);

}  // namespace iris
