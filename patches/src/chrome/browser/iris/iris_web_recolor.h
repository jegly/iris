// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: "Recolour websites" (Settings > Appearance > Theme editor; apply-web-recolor.sh). Pages are drawn with their
// colours mapped onto the Iris theme (background, text, accent) by Blink's auto-dark-mode engine with an Iris colour
// filter. The theme colours reach renderers as --iris-recolor=<background>,<text>,<accent>,<brightness>,<contrast>
// (applies to pages opened after a change, like Coarser timers); whether a page is recoloured is decided per
// navigation (WebPreferences force_dark_mode_enabled), so the per-site switch in the shield works at once.

#ifndef CHROME_BROWSER_IRIS_IRIS_WEB_RECOLOR_H_
#define CHROME_BROWSER_IRIS_IRIS_WEB_RECOLOR_H_

#include <string>

class GURL;
class Profile;

namespace iris::recolor {

inline constexpr char kEnabledPref[] = "iris.web_recolor.enabled";
inline constexpr char kBrightnessPref[] = "iris.web_recolor.brightness";  // %
inline constexpr char kContrastPref[] = "iris.web_recolor.contrast";      // %
inline constexpr char kExcludedSitesPref[] = "iris.web_recolor.excluded";
inline constexpr char kSwitch[] = "iris-recolor";

bool IsEnabled(Profile* profile);

// True for http(s) pages of sites not excluded, while recolouring is on.
bool IsOnForUrl(Profile* profile, const GURL& url);

// The per-site switch ("Recolour this site").
bool IsExcluded(Profile* profile, const GURL& url);
void SetExcluded(Profile* profile, const GURL& url, bool excluded);

// The value of --iris-recolor for this profile's renderers, or "" when off.
std::string SwitchValue(Profile* profile);

}  // namespace iris::recolor

#endif  // CHROME_BROWSER_IRIS_IRIS_WEB_RECOLOR_H_
