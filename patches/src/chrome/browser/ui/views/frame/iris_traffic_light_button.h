// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: macOS-style "traffic light" window buttons for the Linux browser frame (patches/apply-traffic-lights.sh).
// Same look as jegly's AV (modules/gui/qt/widgets/qml/CSDWindowButton*.qml): a 13 px filled dot in a 22 px slot with
// 2 px between buttons, close #FF5F57 / minimise #FEBC2E / maximise #28C840 (colours changeable in Settings ->
// Appearance), 25% darker while pressed, a hairline edge (14% black, 22% on dark frames), and the glyph (62% black,
// 62% of the dot) shown on all buttons while any of them is hovered. Settings -> Appearance -> "Traffic-light window
// buttons" (on by default) switches back to Chromium's buttons for new windows.
//
// It is a views::FrameCaptionButton (same class metadata), so OpaqueBrowserFrameView keeps treating it like the
// upstream MD caption button (active state, background colour, hit testing); only the painting differs.

#ifndef CHROME_BROWSER_UI_VIEWS_FRAME_IRIS_TRAFFIC_LIGHT_BUTTON_H_
#define CHROME_BROWSER_UI_VIEWS_FRAME_IRIS_TRAFFIC_LIGHT_BUTTON_H_

#include "base/memory/raw_ptr.h"
#include "components/prefs/pref_change_registrar.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/views/window/frame_caption_button.h"

class PrefService;

class IrisTrafficLightButton : public views::FrameCaptionButton {
 public:
  enum class Glyph { kClose, kMinimize, kMaximize, kRestore };

  // Profile prefs (registered by IrisShredder::RegisterProfilePrefs).
  static constexpr char kEnabledPref[] = "iris.ui.traffic_lights";
  static constexpr char kClosePref[] = "iris.ui.traffic_light_close";
  static constexpr char kMinimizePref[] = "iris.ui.traffic_light_minimize";
  static constexpr char kMaximizePref[] = "iris.ui.traffic_light_maximize";
  // Show the ×/−/□ symbols on hover (Settings -> Appearance; default true).
  static constexpr char kSymbolsPref[] = "iris.ui.traffic_light_symbols";
  static constexpr char kCloseDefault[] = "#ff5f57";
  static constexpr char kMinimizeDefault[] = "#febc2e";
  static constexpr char kMaximizeDefault[] = "#28c840";

  // Width of one button: AV's 22 px slot + its 2 px spacing.
  static constexpr int kSlotWidth = 24;

  static bool IsEnabledFor(const PrefService* prefs);
  // True for buttons created by this class (used by the frame layout).
  static bool IsIrisButton(const views::View* view);

  IrisTrafficLightButton(views::CaptionButtonIcon icon_type,
                         int ht_component,
                         Glyph glyph,
                         PrefService* prefs);
  IrisTrafficLightButton(const IrisTrafficLightButton&) = delete;
  IrisTrafficLightButton& operator=(const IrisTrafficLightButton&) = delete;
  ~IrisTrafficLightButton() override;

 protected:
  // views::FrameCaptionButton:
  void PaintButtonContents(gfx::Canvas* canvas) override;
  // views::Button:
  void StateChanged(ButtonState old_state) override;

 private:
  bool IsGroupHovered() const;
  SkColor DotColor() const;
  void RepaintGroup();

  const Glyph glyph_;
  raw_ptr<PrefService> prefs_;
  PrefChangeRegistrar pref_change_registrar_;
};

#endif  // CHROME_BROWSER_UI_VIEWS_FRAME_IRIS_TRAFFIC_LIGHT_BUTTON_H_
