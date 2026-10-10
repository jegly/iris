// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/color/iris_theme_mixer.h"

#include <functional>
#include <string>

#include "base/containers/flat_map.h"
#include "base/no_destructor.h"
#include "base/strings/string_number_conversions.h"
#include "chrome/browser/ui/color/chrome_color_id.h"
#include "ui/color/color_id.h"
#include "ui/color/color_mixer.h"
#include "ui/color/color_provider.h"
#include "ui/color/color_provider_key.h"
#include "ui/color/color_recipe.h"
#include "ui/color/color_transform.h"

namespace iris_theme {
namespace {

using ColorMap = base::flat_map<std::string, SkColor, std::less<>>;

// Contrast floor for the dimmed URL parts and the security indicator (WCAG's
// level for graphics and large text).
constexpr float kMinIndicatorContrast = 3.0f;

ColorMap& Colors() {
  static base::NoDestructor<ColorMap> colors;
  return *colors;
}

// `amount` (0-255) of `top` over `base`, both resolved against the final
// colours, so derived tones follow the other overrides.
ui::ColorTransform Over(ui::ColorTransform top,
                        ui::ColorTransform base,
                        SkAlpha amount) {
  return ui::AlphaBlend(std::move(top), std::move(base), amount);
}

}  // namespace

void SetCustomColors(const base::DictValue& colors) {
  ColorMap& map = Colors();
  map.clear();
  for (const auto [key, value] : colors) {
    if (!value.is_string()) {
      continue;
    }
    if (std::optional<SkColor> color = ParseColor(value.GetString())) {
      map[key] = *color;
    }
  }
}

std::optional<SkColor> GetCustomColor(std::string_view key) {
  const ColorMap& map = Colors();
  const auto it = map.find(key);
  if (it == map.end()) {
    return std::nullopt;
  }
  return it->second;
}

std::optional<SkColor> ParseColor(std::string_view text) {
  uint32_t value = 0;
  if (text.size() != 7 || text[0] != '#' ||
      !base::HexStringToUInt(text.substr(1), &value)) {
    return std::nullopt;
  }
  return SkColorSetRGB((value >> 16) & 0xFF, (value >> 8) & 0xFF,
                       value & 0xFF);
}

void AddIrisThemeMixer(ui::ColorProvider* provider,
                       const ui::ColorProviderKey& key) {
  if (Colors().empty() ||
      key.contrast_mode == ui::ColorProviderKey::ContrastMode::kHigh) {
    return;
  }
  ui::ColorMixer& mixer = provider->AddMixer();
  auto set = [&mixer](std::string_view name,
                      std::initializer_list<ui::ColorId> ids) {
    if (std::optional<SkColor> color = GetCustomColor(name)) {
      for (ui::ColorId id : ids) {
        mixer[id] = {*color};
      }
      return true;
    }
    return false;
  };

  // --- Whole browser: the Material tokens everything else derives from. ---
  if (set(kBackground, {ui::kColorSysBase})) {
    mixer[ui::kColorSysBaseContainer] =
        Over(ui::kColorSysOnSurface, ui::kColorSysBase, 0x14);
    mixer[ui::kColorSysBaseContainerElevated] =
        Over(ui::kColorSysOnSurface, ui::kColorSysBase, 0x1F);
  }
  if (set(kSurface, {ui::kColorSysSurface})) {
    mixer[ui::kColorSysSurface1] =
        Over(ui::kColorSysOnSurface, ui::kColorSysSurface, 0x08);
    mixer[ui::kColorSysSurface2] =
        Over(ui::kColorSysOnSurface, ui::kColorSysSurface, 0x0D);
    mixer[ui::kColorSysSurface3] =
        Over(ui::kColorSysOnSurface, ui::kColorSysSurface, 0x14);
    mixer[ui::kColorSysSurface4] =
        Over(ui::kColorSysOnSurface, ui::kColorSysSurface, 0x1C);
    mixer[ui::kColorSysSurface5] =
        Over(ui::kColorSysOnSurface, ui::kColorSysSurface, 0x24);
    mixer[ui::kColorSysSurfaceVariant] =
        Over(ui::kColorSysOnSurface, ui::kColorSysSurface, 0x1A);
  }
  if (set(kText, {ui::kColorSysOnSurface})) {
    mixer[ui::kColorSysOnSurfaceSecondary] =
        Over(ui::kColorSysOnSurface, ui::kColorSysBase, 0xD9);
  }
  set(kSecondaryText,
      {ui::kColorSysOnSurfaceSubtle, ui::kColorSysOnSurfaceVariant});
  if (set(kAccent, {ui::kColorSysPrimary, ui::kColorSysOnSurfacePrimary})) {
    mixer[ui::kColorSysOnPrimary] =
        ui::GetColorWithMaxContrast(ui::kColorSysPrimary);
    mixer[ui::kColorSysPrimaryContainer] =
        Over(ui::kColorSysPrimary, ui::kColorSysBase, 0x40);
    mixer[ui::kColorSysOnPrimaryContainer] = {ui::kColorSysOnSurface};
    mixer[ui::kColorSysBaseTonalContainer] =
        Over(ui::kColorSysPrimary, ui::kColorSysBase, 0x33);
    mixer[ui::kColorSysOnBaseTonalContainer] = {ui::kColorSysOnSurface};
    mixer[ui::kColorSysTonalContainer] =
        Over(ui::kColorSysPrimary, ui::kColorSysSurface, 0x33);
    mixer[ui::kColorSysOnTonalContainer] = {ui::kColorSysOnSurface};
  }

  // --- Title bar and tabs. ---
  if (set(kTitleBar, {ui::kColorSysHeader, ui::kColorFrameActive}) &&
      !GetCustomColor(kTitleBarInactive)) {
    // Unfocused windows: the same colour unless set separately.
    mixer[ui::kColorSysHeaderInactive] = {ui::kColorSysHeader};
    mixer[ui::kColorFrameInactive] = {ui::kColorFrameActive};
  }
  set(kTitleBarInactive, {ui::kColorSysHeaderInactive, ui::kColorFrameInactive});
  set(kTab, {kColorTabBackgroundActiveFrameActive,
             kColorTabBackgroundActiveFrameInactive});
  set(kTabText, {kColorTabForegroundActiveFrameActive,
                 kColorTabForegroundActiveFrameInactive});
  set(kTabTextInactive, {kColorTabForegroundInactiveFrameActive,
                         kColorTabForegroundInactiveFrameInactive});

  // --- Toolbar. ---
  set(kToolbar, {kColorToolbar});
  set(kToolbarIcons, {kColorToolbarButtonIcon, kColorToolbarButtonIconHovered,
                      kColorToolbarButtonIconPressed});
  set(kBookmarksText, {kColorBookmarkBarForeground, kColorBookmarkButtonIcon});

  // --- Address bar. ---
  if (set(kOmnibox, {kColorLocationBarBackground})) {
    mixer[kColorLocationBarBackgroundHovered] =
        Over(ui::kColorSysOnSurface, kColorLocationBarBackground, 0x10);
  }
  // Address bar readability floor (anti-spoofing; jegly 2026-10-10): whatever
  // colours are picked, the URL keeps Chromium's "readable" contrast (4.5:1)
  // against the address bar, and its dimmed parts and the security indicator
  // at least 3:1; a colour that is too close is blended until it reads. A
  // shared theme code can therefore not hide the real address or the padlock.
  const std::optional<SkColor> omnibox_text = GetCustomColor(kOmniboxText);
  mixer[kColorOmniboxText] = ui::BlendForMinContrast(
      omnibox_text ? ui::ColorTransform(*omnibox_text)
                   : ui::FromTransformInput(),
      kColorLocationBarBackground);
  mixer[kColorOmniboxTextDimmed] = ui::BlendForMinContrast(
      omnibox_text ? Over(kColorOmniboxText, kColorLocationBarBackground, 0xA6)
                   : ui::FromTransformInput(),
      kColorLocationBarBackground, std::nullopt, kMinIndicatorContrast);
  for (ui::ColorId id :
       {kColorOmniboxSecurityChipDefault, kColorOmniboxSecurityChipSecure,
        kColorOmniboxSecurityChipDangerous}) {
    mixer[id] = ui::BlendForMinContrast(ui::FromTransformInput(),
                                        kColorLocationBarBackground,
                                        std::nullopt, kMinIndicatorContrast);
  }
  if (set(kSuggestions, {kColorOmniboxResultsBackground})) {
    mixer[kColorOmniboxResultsBackgroundHovered] =
        Over(ui::kColorSysOnSurface, kColorOmniboxResultsBackground, 0x10);
  }

  // --- Pages and panels. ---
  set(kNewTabPage, {kColorNewTabPageBackground});
  set(kSidePanel, {kColorSidePanelBackground, kColorSidePanelContentBackground});
}

}  // namespace iris_theme
