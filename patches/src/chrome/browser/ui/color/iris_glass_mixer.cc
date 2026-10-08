// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/color/iris_glass_mixer.h"

#include <algorithm>

#include "chrome/browser/ui/color/chrome_color_id.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/color/color_id.h"
#include "ui/color/color_mixer.h"
#include "ui/color/color_provider.h"
#include "ui/color/color_provider_key.h"
#include "ui/color/color_recipe.h"
#include "ui/color/color_transform.h"

namespace iris_glass {

namespace {

bool g_enabled = false;
int g_opacity = kDefaultOpacity;

// Notas' floor: below this, unblurred wallpaper makes text hard to read.
constexpr float kMinAlpha = 0.20f;

SkAlpha ToAlpha(float alpha) {
  return static_cast<SkAlpha>(std::clamp(alpha, kMinAlpha, 1.0f) * 255.0f +
                              0.5f);
}

}  // namespace

void SetWindowGlass(bool enabled, int opacity_percent) {
  g_enabled = enabled;
  g_opacity = std::clamp(opacity_percent, 30, 100);
}

void AddIrisGlassMixer(ui::ColorProvider* provider,
                       const ui::ColorProviderKey& key) {
  // Installed/GTK/Qt themes and high contrast keep their opaque frame.
  if (!g_enabled || key.custom_theme ||
      key.contrast_mode == ui::ColorProviderKey::ContrastMode::kHigh) {
    return;
  }
  const float a = g_opacity / 100.0f;
  const SkAlpha body = ToAlpha(a);           // toolbar, selected tab, bookmarks
  const SkAlpha edge = ToAlpha(a - 0.25f);   // title bar + tab strip
  const SkAlpha hover = ToAlpha(a - 0.15f);  // inactive tab under the mouse

  ui::ColorMixer& mixer = provider->AddMixer();
  for (ui::ColorId id : {ui::kColorFrameActive, ui::kColorFrameInactive}) {
    mixer[id] = ui::SetAlpha(ui::FromTransformInput(), edge);
  }
  for (ui::ColorId id :
       {kColorToolbar, kColorBookmarkBarBackground,
        kColorTabBackgroundActiveFrameActive,
        kColorTabBackgroundActiveFrameInactive,
        kColorTabBackgroundSelectedFrameActive,
        kColorTabBackgroundSelectedFrameInactive}) {
    mixer[id] = ui::SetAlpha(ui::FromTransformInput(), body);
  }
  for (ui::ColorId id : {kColorTabBackgroundInactiveFrameActive,
                         kColorTabBackgroundInactiveFrameInactive}) {
    mixer[id] = {SK_ColorTRANSPARENT};
  }
  for (ui::ColorId id : {kColorTabBackgroundInactiveHoverFrameActive,
                         kColorTabBackgroundInactiveHoverFrameInactive,
                         kColorTabBackgroundSelectedHoverFrameActive,
                         kColorTabBackgroundSelectedHoverFrameInactive}) {
    mixer[id] = ui::SetAlpha(ui::FromTransformInput(), hover);
  }
}

}  // namespace iris_glass
