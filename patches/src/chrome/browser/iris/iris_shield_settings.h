// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: the per-site switches of the shield, shared by the desktop panel (iris_toolbar_buttons.cc) and the Android
// sheet (IrisShieldSheet.java via iris_shield_android.cc), so both read and write them the same way.
// A switch stores a per-site exception only when it differs from the default, so the global switches on the Iris
// hardening page keep reaching every site whose switch matches them.

#ifndef CHROME_BROWSER_IRIS_IRIS_SHIELD_SETTINGS_H_
#define CHROME_BROWSER_IRIS_IRIS_SHIELD_SETTINGS_H_

class GURL;
class Profile;

namespace iris::shield {

// Values are shared with IrisShield.java; keep them in sync.
enum class Switch {
  kAds = 0,         // block ads and trackers (ContentSettingsType::ADS)
  kCookies = 1,     // block cross-site cookies (third-party cookie setting)
  kJavaScript = 2,  // JavaScript allowed
  kJit = 3,         // JavaScript optimisation (JIT) allowed
  kWebGL = 4,       // WebGL allowed (IRIS_WEBGL)
  kSignIn = 5,      // Google sign-in prompts allowed (IRIS_GOOGLE_SIGNIN)
  kForget = 6,      // forget the site when Iris closes (cookies SESSION_ONLY)
  kRecolor = 7,     // "Recolour websites" on for this site (desktop)
  kMaxValue = kRecolor,
};

bool IsOn(Profile* profile, const GURL& url, Switch which);

// True when a global switch decides and the site switch has no effect
// ("Turn WebGL off completely" for kWebGL, "Recolour websites" off for
// kRecolor).
bool IsLocked(Profile* profile, Switch which);

void Set(Profile* profile, const GURL& url, Switch which, bool on);

// The master switch: ads and trackers, cross-site cookies and canvas/audio
// protection together.
void SetShield(Profile* profile, const GURL& url, bool on);

// Every shield setting of the site back to the defaults.
void Reset(Profile* profile, const GURL& url);

}  // namespace iris::shield

#endif  // CHROME_BROWSER_IRIS_IRIS_SHIELD_SETTINGS_H_
