// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: the Theme editor's colours (Settings > Appearance > Theme editor; apply-theme-editor.sh). The profile pref
// iris.theme.custom holds "#rrggbb" values for the keys below; anything not set keeps the palette's colour.
// "Whole browser" keys override the Material sys tokens, so everything derived from them follows; the other keys set
// one part of the window. Added after Chrome's mixers and before the glass mixer (glass alpha still applies).
// Like glass, the state is browser-wide: ThemeService sets it from the profile pref and drops cached providers.

#ifndef CHROME_BROWSER_UI_COLOR_IRIS_THEME_MIXER_H_
#define CHROME_BROWSER_UI_COLOR_IRIS_THEME_MIXER_H_

#include <optional>
#include <string_view>

#include "base/values.h"
#include "third_party/skia/include/core/SkColor.h"

namespace ui {
class ColorProvider;
struct ColorProviderKey;
}  // namespace ui

namespace iris_theme {

inline constexpr char kCustomColorsPref[] = "iris.theme.custom";
inline constexpr char kSavedThemesPref[] = "iris.theme.saved";

// Keys of iris.theme.custom (also used in shared theme codes; keep stable).
// Whole browser
inline constexpr char kAccent[] = "accent";
inline constexpr char kText[] = "text";
inline constexpr char kSecondaryText[] = "text2";
inline constexpr char kBackground[] = "background";
inline constexpr char kSurface[] = "surface";
// Title bar and tabs
inline constexpr char kTitleBar[] = "titlebar";
inline constexpr char kTitleBarInactive[] = "titlebar_inactive";
inline constexpr char kTab[] = "tab";
inline constexpr char kTabText[] = "tab_text";
inline constexpr char kTabTextInactive[] = "tab_text_inactive";
// Toolbar
inline constexpr char kToolbar[] = "toolbar";
inline constexpr char kToolbarIcons[] = "toolbar_icons";
inline constexpr char kBookmarksText[] = "bookmarks_text";
// Address bar
inline constexpr char kOmnibox[] = "omnibox";
inline constexpr char kOmniboxText[] = "omnibox_text";
inline constexpr char kSuggestions[] = "suggestions";
// Pages and panels
inline constexpr char kNewTabPage[] = "ntp";
inline constexpr char kSidePanel[] = "side_panel";

// Sets the browser-wide colours from the pref value (a dictionary of
// "#rrggbb" strings; anything else is ignored).
void SetCustomColors(const base::DictValue& colors);

// The colour set for `key`, if any.
std::optional<SkColor> GetCustomColor(std::string_view key);

// Parses "#rrggbb".
std::optional<SkColor> ParseColor(std::string_view text);

void AddIrisThemeMixer(ui::ColorProvider* provider,
                       const ui::ColorProviderKey& key);

}  // namespace iris_theme

#endif  // CHROME_BROWSER_UI_COLOR_IRIS_THEME_MIXER_H_
