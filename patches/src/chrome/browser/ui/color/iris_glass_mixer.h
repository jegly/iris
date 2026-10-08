// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: see-through "glass" window (patches/apply-glass-window.sh), the way jegly's Notas does it (src/glass.rs):
// the Linux browser window already has an alpha channel (BrowserNativeWidgetAuraLinux: WindowOpacity::kTranslucent,
// used upstream for the client-side shadow), so painting the frame, tab strip and toolbar colours with alpha < 1 lets
// the desktop show through. Web page content is not affected (sites paint their own backgrounds).
// Opacity 30-100 % (Settings -> Appearance), Notas' steps: the title bar / tab strip is the clearest (-0.25), the
// toolbar and the selected tab use the chosen opacity, nothing goes below 20 %. Inactive tabs are fully clear so they
// do not stack on the already-translucent tab strip. GNOME does not blur behind windows: this is clear glass, not frost.

#ifndef CHROME_BROWSER_UI_COLOR_IRIS_GLASS_MIXER_H_
#define CHROME_BROWSER_UI_COLOR_IRIS_GLASS_MIXER_H_

namespace ui {
class ColorProvider;
struct ColorProviderKey;
}  // namespace ui

namespace iris_glass {

// Profile prefs (registered by IrisShredder::RegisterProfilePrefs).
inline constexpr char kWindowPref[] = "iris.glass.window";
inline constexpr char kOpacityPref[] = "iris.glass.window_opacity";
inline constexpr int kDefaultOpacity = 78;

// Browser-wide state (the colour pipeline has no prefs); the last profile to set it wins.
void SetWindowGlass(bool enabled, int opacity_percent);

// Added last in AddChromeColorMixers().
void AddIrisGlassMixer(ui::ColorProvider* provider,
                       const ui::ColorProviderKey& key);

}  // namespace iris_glass

#endif  // CHROME_BROWSER_UI_COLOR_IRIS_GLASS_MIXER_H_
