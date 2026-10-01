// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: "Iris protections" section of chrome://version. Reads the LIVE state of Iris's protections from the running
// browser (features, prefs, content settings, the command line), so a protection that is off shows as off. One
// line per protection; a final "built in" line lists compile-time hardening.

#ifndef CHROME_BROWSER_UI_WEBUI_VERSION_IRIS_PROTECTIONS_H_
#define CHROME_BROWSER_UI_WEBUI_VERSION_IRIS_PROTECTIONS_H_

#include <string>

class Profile;

namespace iris {

std::string ProtectionsReport(Profile* profile);

}  // namespace iris

#endif  // CHROME_BROWSER_UI_WEBUI_VERSION_IRIS_PROTECTIONS_H_
