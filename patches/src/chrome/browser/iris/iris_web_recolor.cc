// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_web_recolor.h"

#include <algorithm>
#include <optional>
#include <string_view>

#include "base/strings/string_number_conversions.h"
#include "base/strings/stringprintf.h"
#include "base/values.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/themes/theme_service_factory.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/color/iris_palettes.h"
#include "ui/native_theme/native_theme.h"
#include "url/gurl.h"

namespace iris::recolor {
namespace {

// The Theme editor's colours (chrome/browser/ui/color/iris_theme_mixer.h).
constexpr char kCustomColorsPref[] = "iris.theme.custom";
// Positions in ui::iris::kPaletteTokens.
constexpr size_t kTokenBase = 8;
constexpr size_t kTokenOnSurface = 21;
constexpr size_t kTokenPrimary = 26;

std::string SiteKey(const GURL& url) {
  const std::string site = net::registry_controlled_domains::GetDomainAndRegistry(
      url, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  return site.empty() ? std::string(url.host()) : site;
}

std::optional<SkColor> CustomColor(Profile* profile, std::string_view key) {
  const std::string* text =
      profile->GetPrefs()->GetDict(kCustomColorsPref).FindString(key);
  uint32_t value = 0;
  if (!text || text->size() != 7 || (*text)[0] != '#' ||
      !base::HexStringToUInt(std::string_view(*text).substr(1), &value)) {
    return std::nullopt;
  }
  return SkColorSetRGB((value >> 16) & 0xFF, (value >> 8) & 0xFF,
                       value & 0xFF);
}

// The Iris palette in use: the one picked, or the light/dark default.
const ui::iris::Palette& ActivePalette(Profile* profile) {
  bool dark = false;
  if (ThemeService* theme = ThemeServiceFactory::GetForProfile(profile)) {
    if (const ui::iris::Palette* picked =
            ui::iris::PaletteForSeed(theme->GetUserColor())) {
      return *picked;
    }
    switch (theme->GetBrowserColorScheme()) {
      case ThemeService::BrowserColorScheme::kDark:
        dark = true;
        break;
      case ThemeService::BrowserColorScheme::kLight:
        dark = false;
        break;
      case ThemeService::BrowserColorScheme::kSystem:
        dark = ui::NativeTheme::GetInstanceForNativeUi()
                   ->preferred_color_scheme() ==
               ui::NativeTheme::PreferredColorScheme::kDark;
        break;
    }
  }
  return ui::iris::kPalettes[dark ? ui::iris::kDefaultPalette
                                  : ui::iris::kDefaultLightPalette];
}

std::string Hex(SkColor color) {
  return base::StringPrintf("%02x%02x%02x", SkColorGetR(color),
                            SkColorGetG(color), SkColorGetB(color));
}

}  // namespace

bool IsEnabled(Profile* profile) {
  return profile && profile->GetPrefs()->GetBoolean(kEnabledPref);
}

bool IsOnForUrl(Profile* profile, const GURL& url) {
  return IsEnabled(profile) && url.SchemeIsHTTPOrHTTPS() &&
         !IsExcluded(profile, url);
}

bool IsExcluded(Profile* profile, const GURL& url) {
  const base::ListValue& sites =
      profile->GetPrefs()->GetList(kExcludedSitesPref);
  return std::ranges::find(sites, base::Value(SiteKey(url))) != sites.end();
}

void SetExcluded(Profile* profile, const GURL& url, bool excluded) {
  const std::string site = SiteKey(url);
  if (site.empty() || IsExcluded(profile, url) == excluded) {
    return;
  }
  ScopedListPrefUpdate update(profile->GetPrefs(), kExcludedSitesPref);
  if (excluded) {
    update->Append(site);
  } else {
    update->EraseValue(base::Value(site));
  }
}

std::string SwitchValue(Profile* profile) {
  if (!IsEnabled(profile)) {
    return std::string();
  }
  const ui::iris::Palette& palette = ActivePalette(profile);
  const SkColor background =
      CustomColor(profile, "background").value_or(palette.colors[kTokenBase]);
  const SkColor text =
      CustomColor(profile, "text").value_or(palette.colors[kTokenOnSurface]);
  const SkColor accent =
      CustomColor(profile, "accent").value_or(palette.colors[kTokenPrimary]);
  PrefService* prefs = profile->GetPrefs();
  return base::StringPrintf(
      "%s,%s,%s,%d,%d", Hex(background).c_str(), Hex(text).c_str(),
      Hex(accent).c_str(), std::clamp(prefs->GetInteger(kBrightnessPref), 50, 150),
      std::clamp(prefs->GetInteger(kContrastPref), 50, 150));
}

}  // namespace iris::recolor
