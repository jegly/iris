// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B5): Google sign-in prompts ("One Tap" and the "Sign in with Google" button of Google Identity
// Services) are embedded as frames from accounts.google.com. They let Google see which sites you visit while you are
// signed in to Google, and nag you to sign in. Iris blocks those frames unless the site has the "Google sign-in
// prompts" permission (ContentSettingsType::IRIS_GOOGLE_SIGNIN, default BLOCK; Page Info / Site settings).
// Sign-in by clicking a normal link to Google (a top-level navigation) is never affected.

#ifndef CHROME_BROWSER_IRIS_IRIS_GOOGLE_SIGNIN_THROTTLE_H_
#define CHROME_BROWSER_IRIS_IRIS_GOOGLE_SIGNIN_THROTTLE_H_

#include "content/public/browser/navigation_throttle.h"

class GURL;

namespace content {
class NavigationThrottleRegistry;
}

class IrisGoogleSigninThrottle : public content::NavigationThrottle {
 public:
  static void MaybeCreateAndAdd(content::NavigationThrottleRegistry& registry);

  explicit IrisGoogleSigninThrottle(content::NavigationThrottleRegistry& registry);
  IrisGoogleSigninThrottle(const IrisGoogleSigninThrottle&) = delete;
  IrisGoogleSigninThrottle& operator=(const IrisGoogleSigninThrottle&) = delete;
  ~IrisGoogleSigninThrottle() override;

  // content::NavigationThrottle:
  ThrottleCheckResult WillStartRequest() override;
  ThrottleCheckResult WillRedirectRequest() override;
  const char* GetNameForLogging() override;

  // True for the Google Identity Services frames (exposed for tests).
  static bool IsGoogleSigninFrameUrl(const GURL& url);

 private:
  ThrottleCheckResult Check();
};

#endif  // CHROME_BROWSER_IRIS_IRIS_GOOGLE_SIGNIN_THROTTLE_H_
