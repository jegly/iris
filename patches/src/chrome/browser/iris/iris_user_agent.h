// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B2): per-site browser identity. A site can be told it is talking to Firefox on Linux, Chrome on
// Windows or Safari on macOS (Settings -> Site settings -> the site -> "Browser identity"); every other site sees
// Iris's normal user agent. Stored as the website setting ContentSettingsType::IRIS_USER_AGENT (a preset id).
// Applied in DidStartNavigation like Chromium's own "request desktop site" (upstream pattern). Only the User-Agent
// header and navigator.userAgent change; Iris sends no Sec-CH-UA hints at all, so nothing contradicts it there.

#ifndef CHROME_BROWSER_IRIS_IRIS_USER_AGENT_H_
#define CHROME_BROWSER_IRIS_IRIS_USER_AGENT_H_

#include <string>
#include <string_view>

#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

class GURL;

namespace content {
class BrowserContext;
}

namespace iris {

// Preset ids: see kPresetIds in iris_user_agent.cc (13: Firefox/Chrome/Edge/Safari/Samsung on desktop, Android and
// iPhone); "" = Iris default.
bool IsValidUserAgentPreset(std::string_view preset);
std::string GetUserAgentPreset(content::BrowserContext* context, const GURL& url);
void SetUserAgentPreset(content::BrowserContext* context,
                        const GURL& url,
                        std::string_view preset);
// The user agent string for a preset ("" for unknown).
std::string UserAgentForPreset(std::string_view preset);

class UserAgentTabHelper
    : public content::WebContentsObserver,
      public content::WebContentsUserData<UserAgentTabHelper> {
 public:
  UserAgentTabHelper(const UserAgentTabHelper&) = delete;
  UserAgentTabHelper& operator=(const UserAgentTabHelper&) = delete;
  ~UserAgentTabHelper() override;

  // content::WebContentsObserver:
  void DidStartNavigation(content::NavigationHandle* handle) override;

 private:
  friend class content::WebContentsUserData<UserAgentTabHelper>;
  explicit UserAgentTabHelper(content::WebContents* web_contents);
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace iris

#endif  // CHROME_BROWSER_IRIS_IRIS_USER_AGENT_H_
