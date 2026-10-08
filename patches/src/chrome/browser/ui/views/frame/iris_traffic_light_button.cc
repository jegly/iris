// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/views/frame/iris_traffic_light_button.h"

#include <set>
#include <string>

#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/strings/string_number_conversions.h"
#include "cc/paint/paint_flags.h"
#include "components/prefs/pref_service.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/color_utils.h"
#include "ui/gfx/geometry/point_f.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/views/animation/ink_drop.h"

namespace {

// Live buttons (UI thread only), so the layout and the hover group can find them.
std::set<const views::View*>& Registry() {
  static base::NoDestructor<std::set<const views::View*>> registry;
  return *registry;
}

constexpr float kDotDiameter = 13.0f;
constexpr float kGlyphScale = 0.62f;
constexpr SkAlpha kGlyphAlpha = 158;  // 62% black, like AV.

SkColor ParseHexColor(const std::string& value, SkColor fallback) {
  uint32_t rgb = 0;
  if (value.size() != 7 || value[0] != '#' ||
      !base::HexStringToUInt(std::string_view(value).substr(1), &rgb)) {
    return fallback;
  }
  return SkColorSetRGB((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
}

}  // namespace

// static
bool IrisTrafficLightButton::IsEnabledFor(const PrefService* prefs) {
  return prefs && prefs->FindPreference(kEnabledPref) &&
         prefs->GetBoolean(kEnabledPref);
}

// static
bool IrisTrafficLightButton::IsIrisButton(const views::View* view) {
  return Registry().contains(view);
}

IrisTrafficLightButton::IrisTrafficLightButton(
    views::CaptionButtonIcon icon_type,
    int ht_component,
    Glyph glyph,
    PrefService* prefs)
    : views::FrameCaptionButton(views::Button::PressedCallback(),
                                icon_type,
                                ht_component),
      glyph_(glyph),
      prefs_(prefs) {
  Registry().insert(this);
  // No ripple or round hover highlight: the dot itself is the button.
  views::InkDrop::Get(this)->SetMode(views::InkDropHost::InkDropMode::OFF);
  pref_change_registrar_.Init(prefs_);
  for (const char* pref : {kClosePref, kMinimizePref, kMaximizePref}) {
    pref_change_registrar_.Add(
        pref, base::BindRepeating(&IrisTrafficLightButton::SchedulePaint,
                                  base::Unretained(this)));
  }
}

IrisTrafficLightButton::~IrisTrafficLightButton() {
  Registry().erase(this);
}

SkColor IrisTrafficLightButton::DotColor() const {
  const char* pref = kClosePref;
  const char* fallback = kCloseDefault;
  switch (glyph_) {
    case Glyph::kClose:
      break;
    case Glyph::kMinimize:
      pref = kMinimizePref;
      fallback = kMinimizeDefault;
      break;
    case Glyph::kMaximize:
    case Glyph::kRestore:
      pref = kMaximizePref;
      fallback = kMaximizeDefault;
      break;
  }
  const SkColor default_color = ParseHexColor(fallback, SK_ColorGRAY);
  if (!prefs_ || !prefs_->FindPreference(pref)) {
    return default_color;
  }
  return ParseHexColor(prefs_->GetString(pref), default_color);
}

bool IrisTrafficLightButton::IsGroupHovered() const {
  if (!parent()) {
    return IsMouseHovered();
  }
  for (const views::View* child : parent()->children()) {
    if (IsIrisButton(child) && child->GetVisible() &&
        child->IsMouseHovered()) {
      return true;
    }
  }
  return false;
}

void IrisTrafficLightButton::RepaintGroup() {
  if (!parent()) {
    SchedulePaint();
    return;
  }
  for (views::View* child : parent()->children()) {
    if (IsIrisButton(child)) {
      child->SchedulePaint();
    }
  }
}

void IrisTrafficLightButton::StateChanged(ButtonState old_state) {
  views::FrameCaptionButton::StateChanged(old_state);
  RepaintGroup();
}

void IrisTrafficLightButton::PaintButtonContents(gfx::Canvas* canvas) {
  const gfx::RectF bounds(GetContentsBounds());
  const gfx::PointF center = bounds.CenterPoint();
  const float radius = kDotDiameter / 2.0f;

  SkColor fill = DotColor();
  if (GetState() == STATE_PRESSED) {
    fill = color_utils::AlphaBlend(SK_ColorBLACK, fill, 0.2f);  // Qt.darker 1.25
  }
  cc::PaintFlags flags;
  flags.setAntiAlias(true);
  flags.setStyle(cc::PaintFlags::kFill_Style);
  flags.setColor(fill);
  canvas->DrawCircle(center, radius, flags);

  // Hairline edge so the dot reads on frame colours close to its own.
  const bool dark_frame = color_utils::IsDark(GetBackgroundColor());
  flags.setStyle(cc::PaintFlags::kStroke_Style);
  flags.setStrokeWidth(1.0f);
  flags.setColor(SkColorSetA(SK_ColorBLACK, dark_frame ? 56 : 36));
  canvas->DrawCircle(center, radius - 0.5f, flags);

  if (!IsGroupHovered()) {
    return;
  }
  // The glyph, drawn with lines so it stays crisp at this size.
  const float half = kDotDiameter * kGlyphScale / 2.0f;
  flags.setColor(SkColorSetA(SK_ColorBLACK, kGlyphAlpha));
  flags.setStrokeWidth(1.2f);
  flags.setStrokeCap(cc::PaintFlags::kRound_Cap);
  const float x = center.x();
  const float y = center.y();
  switch (glyph_) {
    case Glyph::kClose: {
      const float d = half * 0.75f;
      canvas->DrawLine(gfx::PointF(x - d, y - d), gfx::PointF(x + d, y + d),
                       flags);
      canvas->DrawLine(gfx::PointF(x - d, y + d), gfx::PointF(x + d, y - d),
                       flags);
      break;
    }
    case Glyph::kMinimize:
      canvas->DrawLine(gfx::PointF(x - half, y), gfx::PointF(x + half, y),
                       flags);
      break;
    case Glyph::kMaximize: {
      const float d = half * 0.8f;
      canvas->DrawRect(gfx::RectF(x - d, y - d, 2 * d, 2 * d), flags);
      break;
    }
    case Glyph::kRestore: {
      const float d = half * 0.6f;
      canvas->DrawRect(gfx::RectF(x - d - 1.0f, y - d + 1.0f, 2 * d, 2 * d),
                       flags);
      canvas->DrawLine(gfx::PointF(x - d + 1.0f, y - d - 1.0f),
                       gfx::PointF(x + d + 1.0f, y - d - 1.0f), flags);
      canvas->DrawLine(gfx::PointF(x + d + 1.0f, y - d - 1.0f),
                       gfx::PointF(x + d + 1.0f, y + d - 1.0f), flags);
      break;
    }
  }
}
