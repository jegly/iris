// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_google_signin_throttle.h"

#include <memory>
#include <string_view>

#include "base/strings/string_util.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "url/gurl.h"

namespace {

// Google's own sites keep their sign-in frames.
bool IsGoogleSite(const GURL& url) {
  return url.DomainIs("google.com") || url.DomainIs("youtube.com");
}

}  // namespace

// static
void IrisGoogleSigninThrottle::MaybeCreateAndAdd(
    content::NavigationThrottleRegistry& registry) {
  // Only frames inside a page; top-level navigations to Google are untouched.
  if (registry.GetNavigationHandle().IsInMainFrame()) {
    return;
  }
  registry.AddThrottle(std::make_unique<IrisGoogleSigninThrottle>(registry));
}

// static
bool IrisGoogleSigninThrottle::IsGoogleSigninFrameUrl(const GURL& url) {
  if (!url.SchemeIs(url::kHttpsScheme) || url.host() != "accounts.google.com") {
    return false;
  }
  const std::string_view path = url.path();
  return base::StartsWith(path, "/gsi/") ||
         base::StartsWith(path, "/o/oauth2/iframe");
}

IrisGoogleSigninThrottle::IrisGoogleSigninThrottle(
    content::NavigationThrottleRegistry& registry)
    : content::NavigationThrottle(registry) {}

IrisGoogleSigninThrottle::~IrisGoogleSigninThrottle() = default;

content::NavigationThrottle::ThrottleCheckResult
IrisGoogleSigninThrottle::WillStartRequest() {
  return Check();
}

content::NavigationThrottle::ThrottleCheckResult
IrisGoogleSigninThrottle::WillRedirectRequest() {
  return Check();
}

const char* IrisGoogleSigninThrottle::GetNameForLogging() {
  return "IrisGoogleSigninThrottle";
}

content::NavigationThrottle::ThrottleCheckResult
IrisGoogleSigninThrottle::Check() {
  content::NavigationHandle* handle = navigation_handle();
  if (!IsGoogleSigninFrameUrl(handle->GetURL())) {
    return PROCEED;
  }
  content::RenderFrameHost* parent = handle->GetParentFrameOrOuterDocument();
  if (!parent) {
    return PROCEED;
  }
  const GURL site = parent->GetOutermostMainFrame()->GetLastCommittedURL();
  if (IsGoogleSite(site)) {
    return PROCEED;
  }
  HostContentSettingsMap* map = HostContentSettingsMapFactory::GetForProfile(
      handle->GetWebContents()->GetBrowserContext());
  if (map && map->GetContentSetting(site, site,
                                    ContentSettingsType::IRIS_GOOGLE_SIGNIN) ==
                 CONTENT_SETTING_ALLOW) {
    return PROCEED;
  }
  // Leave the frame empty (no error page inside the site).
  return CANCEL;
}
