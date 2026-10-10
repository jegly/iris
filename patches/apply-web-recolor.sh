#!/usr/bin/env bash
# Iris — "Recolour websites", like Dark Reader's custom colours (0.0.0.7 item 11, jegly 2026-10-10: "change say
# duckduckgo.com colour page so it would apply globally to all websites like what dark reader can do"; verified
# against 156.0.8078.11). Desktop.
#  - Blink (third_party/blink/renderer/platform/graphics): Chromium's auto-dark-mode engine draws the page with its
#    colours changed at paint time (the page's styles and scripts are untouched). With --iris-recolor an Iris filter
#    replaces the "invert lightness" one: a colour's lightness picks a point between the theme background (the page's
#    lightest colours) and the theme text (its darkest); colourful elements keep part of their hue, turned toward the
#    accent; brightness and contrast scale the result. Every colour is mapped (thresholds: always). Icons and
#    separators: inverted for dark themes as upstream, left alone for light themes. Photos are never touched.
#  - Browser: chrome/browser/iris/iris_web_recolor.{h,cc}: prefs iris.web_recolor.{enabled,brightness,contrast,
#    excluded}; --iris-recolor=<background>,<text>,<accent>,<brightness>,<contrast> for the profile's renderers
#    (theme colours = the Theme editor's background/text/accent, else the Iris palette in use); per navigation
#    WebPreferences.force_dark_mode_enabled = on for http(s) pages of sites not excluded (not error pages).
#    Colour changes reach pages opened afterwards (renderer start); on/off per site applies on the next load.
# Prefs are registered by IrisShredder (patches/src/chrome/browser/iris/iris_shredder.cc). The Settings UI is
# apply-theme-editor.sh; the shield's per-site switch is in iris_shield_settings.cc (Switch::kRecolor).
# Needs apply-iris-permissions.sh (WebGL block anchor) and apply-privacy-toggles-2.sh (renderer switch anchor).
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (Blink platform, chrome_content_browser_client.o,
#   iris_web_recolor.o). Large Blink rebuild (platform/graphics).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in chrome/browser/iris/iris_web_recolor.h chrome/browser/iris/iris_web_recolor.cc; do
  from="$DIR/src/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$f"; then echo "SKIP up to date: $f"; else cp "$from" "$f"; echo "OK   $f"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

# --- build ---
edit("chrome/browser/BUILD.gn", '    "iris/iris_tls_info.cc",  # Iris\n',
     '    "iris/iris_tls_info.cc",  # Iris\n'
     '    "iris/iris_web_recolor.cc",  # Iris (apply-web-recolor.sh)\n'
     '    "iris/iris_web_recolor.h",  # Iris (apply-web-recolor.sh)\n',
     '"iris/iris_web_recolor.cc"', "sources")

# --- Blink: the Iris colour filter ---
G = "third_party/blink/renderer/platform/graphics/"
f = G + "dark_mode_color_filter.cc"
edit(f, '#include "base/check.h"\n',
     '#include "base/check.h"\n'
     '#include "base/command_line.h"  // Iris\n'
     '#include "base/strings/string_number_conversions.h"  // Iris\n'
     '#include "base/strings/string_split.h"  // Iris\n',
     '#include "base/command_line.h"  // Iris', "includes")
edit(f, "  const lab::DarkModeSRGBLABTransformer transformer_;\n  sk_sp<cc::ColorFilter> filter_;\n};\n\n}  // namespace\n",
     "  const lab::DarkModeSRGBLABTransformer transformer_;\n  sk_sp<cc::ColorFilter> filter_;\n};\n\n"
     "// Iris: \"Recolour websites\" (apply-web-recolor.sh). Maps the page's colours\n"
     "// onto the Iris theme instead of inverting them: lightness picks a point\n"
     "// between the theme background (lightest page colours) and the theme text\n"
     "// (darkest); colourful elements keep part of their hue, turned toward the\n"
     "// accent.\n"
     "class IrisThemeColorFilter : public DarkModeColorFilter {\n"
     " public:\n"
     "  IrisThemeColorFilter(SkColor background,\n"
     "                       SkColor text,\n"
     "                       SkColor accent,\n"
     "                       float brightness,\n"
     "                       float contrast)\n"
     "      : transformer_(lab::DarkModeSRGBLABTransformer()),\n"
     "        background_(ToLab(background)),\n"
     "        text_(ToLab(text)),\n"
     "        accent_(ToLab(accent)),\n"
     "        brightness_(brightness),\n"
     "        contrast_(contrast) {\n"
     "    if (background_.x < text_.x) {\n"
     "      // Dark theme: icons and separators inverted, as upstream.\n"
     "      SkHighContrastConfig config;\n"
     "      config.fInvertStyle =\n"
     "          SkHighContrastConfig::InvertStyle::kInvertLightness;\n"
     "      config.fGrayscale = false;\n"
     "      config.fContrast = 0.0;\n"
     "      filter_ = cc::ColorFilter::MakeHighContrast(config);\n"
     "    } else {\n"
     "      // Light theme: images stay as they are.\n"
     "      static constexpr float kIdentity[20] = {1, 0, 0, 0, 0, 0, 1, 0, 0, 0,\n"
     "                                              0, 0, 1, 0, 0, 0, 0, 0, 1, 0};\n"
     "      filter_ = cc::ColorFilter::MakeMatrix(kIdentity);\n"
     "    }\n"
     "  }\n\n"
     "  SkColor4f InvertColor(const SkColor4f& color) const override {\n"
     "    const SkV3 lab = transformer_.SRGBToLAB({color.fR, color.fG, color.fB});\n"
     "    // 0 = the page's lightest colour, 1 = its darkest.\n"
     "    float t = 1.0f - std::clamp(lab.x, 0.0f, 100.0f) / 100.0f;\n"
     "    t = std::clamp(0.5f + (t - 0.5f) * contrast_, 0.0f, 1.0f);\n"
     "    SkV3 out = {background_.x + (text_.x - background_.x) * t,\n"
     "                background_.y + (text_.y - background_.y) * t,\n"
     "                background_.z + (text_.z - background_.z) * t};\n"
     "    const float chroma = std::hypot(lab.y, lab.z);\n"
     "    if (chroma > 12.0f) {\n"
     "      // Links, buttons and badges stay recognisable: part of their colour\n"
     "      // is kept, the more colourful the more it turns toward the accent.\n"
     "      const float accent_chroma =\n"
     "          std::max(std::hypot(accent_.y, accent_.z), 1.0f);\n"
     "      const float pull = std::min(chroma / 60.0f, 1.0f) * 0.35f;\n"
     "      constexpr float kKeep = 0.55f;\n"
     "      out.y += kKeep * ((1.0f - pull) * lab.y +\n"
     "                        pull * accent_.y / accent_chroma * chroma);\n"
     "      out.z += kKeep * ((1.0f - pull) * lab.z +\n"
     "                        pull * accent_.z / accent_chroma * chroma);\n"
     "    }\n"
     "    out.x = std::clamp(out.x * brightness_, 0.0f, 100.0f);\n"
     "    const SkV3 rgb = transformer_.LABToSRGB(out);\n"
     "    return {std::clamp(rgb.x, 0.0f, 1.0f), std::clamp(rgb.y, 0.0f, 1.0f),\n"
     "            std::clamp(rgb.z, 0.0f, 1.0f), color.fA};\n"
     "  }\n\n"
     "  sk_sp<cc::ColorFilter> ToColorFilter() const override { return filter_; }\n\n"
     " private:\n"
     "  SkV3 ToLab(SkColor color) const {\n"
     "    return transformer_.SRGBToLAB({SkColorGetR(color) / 255.0f,\n"
     "                                   SkColorGetG(color) / 255.0f,\n"
     "                                   SkColorGetB(color) / 255.0f});\n"
     "  }\n\n"
     "  const lab::DarkModeSRGBLABTransformer transformer_;\n"
     "  const SkV3 background_;\n"
     "  const SkV3 text_;\n"
     "  const SkV3 accent_;\n"
     "  const float brightness_;\n"
     "  const float contrast_;\n"
     "  sk_sp<cc::ColorFilter> filter_;\n"
     "};\n\n"
     "// --iris-recolor=<background>,<text>,<accent>,<brightness %>,<contrast %>\n"
     "// (hex rrggbb colours), set by the browser for Iris's \"Recolour websites\".\n"
     "std::unique_ptr<DarkModeColorFilter> MaybeCreateIrisThemeFilter() {\n"
     "  const std::string value =\n"
     "      base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII(\n"
     "          \"iris-recolor\");\n"
     "  const std::vector<std::string_view> parts = base::SplitStringPiece(\n"
     "      value, \",\", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY);\n"
     "  if (parts.size() != 5) {\n"
     "    return nullptr;\n"
     "  }\n"
     "  std::array<uint32_t, 3> colors = {};\n"
     "  for (size_t i = 0; i < colors.size(); ++i) {\n"
     "    if (!base::HexStringToUInt(parts[i], &colors[i])) {\n"
     "      return nullptr;\n"
     "    }\n"
     "  }\n"
     "  int brightness = 100;\n"
     "  int contrast = 100;\n"
     "  if (!base::StringToInt(parts[3], &brightness) ||\n"
     "      !base::StringToInt(parts[4], &contrast)) {\n"
     "    return nullptr;\n"
     "  }\n"
     "  auto rgb = [](uint32_t v) {\n"
     "    return SkColorSetRGB((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);\n"
     "  };\n"
     "  return std::make_unique<IrisThemeColorFilter>(\n"
     "      rgb(colors[0]), rgb(colors[1]), rgb(colors[2]),\n"
     "      std::clamp(brightness, 50, 150) / 100.0f,\n"
     "      std::clamp(contrast, 50, 150) / 100.0f);\n"
     "}\n\n"
     "}  // namespace\n",
     "class IrisThemeColorFilter", "Iris colour filter")
edit(f, "std::unique_ptr<DarkModeColorFilter> DarkModeColorFilter::Create() {\n  return std::make_unique<LABColorFilter>();\n",
     "std::unique_ptr<DarkModeColorFilter> DarkModeColorFilter::Create() {\n"
     "  if (std::unique_ptr<DarkModeColorFilter> iris =\n"
     "          MaybeCreateIrisThemeFilter()) {  // Iris\n"
     "    return iris;\n"
     "  }\n"
     "  return std::make_unique<LABColorFilter>();\n",
     "MaybeCreateIrisThemeFilter()) {  // Iris", "use the Iris filter")
edit(f, "#include <array>\n",
     "#include <algorithm>  // Iris\n#include <array>\n#include <cmath>  // Iris\n#include <string>  // Iris\n"
     "#include <string_view>  // Iris\n#include <vector>  // Iris\n",
     "#include <cmath>  // Iris", "std includes")

sb = G + "dark_mode_settings_builder.cc"
edit(sb, "      Clamp<int>(kDefaultBackgroundBrightnessThreshold, 0, 255);\n  return settings;\n",
     "      Clamp<int>(kDefaultBackgroundBrightnessThreshold, 0, 255);\n"
     "  // Iris: with --iris-recolor every colour is mapped onto the theme\n"
     "  // (apply-web-recolor.sh), not only light backgrounds and dark text.\n"
     "  if (base::CommandLine::ForCurrentProcess()->HasSwitch(\"iris-recolor\")) {\n"
     "    settings.foreground_brightness_threshold = 255;\n"
     "    settings.background_brightness_threshold = 0;\n"
     "  }\n"
     "  return settings;\n",
     'HasSwitch("iris-recolor")', "thresholds")

# --- browser ---
c = "chrome/browser/chrome_content_browser_client.cc"
edit(c, '      if (prefs->GetBoolean("iris.privacy.coarse_timers")) {\n',
     '      // Iris: "Recolour websites" colours (apply-web-recolor.sh).\n'
     '      if (const std::string iris_recolor =\n'
     '              iris::recolor::SwitchValue(profile);\n'
     '          !iris_recolor.empty()) {\n'
     '        command_line->AppendSwitchASCII(iris::recolor::kSwitch, iris_recolor);\n'
     '      }\n'
     '      if (prefs->GetBoolean("iris.privacy.coarse_timers")) {\n',
     "iris::recolor::SwitchValue(profile)", "renderer switch")
edit(c, "  web_prefs->force_dark_mode_enabled =\n      prefs->GetBoolean(prefs::kWebKitForceDarkModeEnabled);\n",
     "  web_prefs->force_dark_mode_enabled =\n      prefs->GetBoolean(prefs::kWebKitForceDarkModeEnabled) ||\n"
     "      iris::recolor::IsOnForUrl(profile, web_contents->GetVisibleURL());  // Iris\n",
     "iris::recolor::IsOnForUrl(profile, web_contents->GetVisibleURL());  // Iris", "recolour (initial prefs)")
edit(c, "    web_prefs->webgl2_enabled = iris_webgl;\n  }\n",
     "    web_prefs->webgl2_enabled = iris_webgl;\n  }\n"
     "  // Iris: \"Recolour websites\" per page (apply-web-recolor.sh): http(s)\n"
     "  // pages of sites not excluded; never error pages.\n"
     "  {\n"
     "    Profile* iris_profile =\n"
     "        Profile::FromBrowserContext(web_contents->GetBrowserContext());\n"
     "    const bool iris_dark =\n"
     "        iris_profile->GetPrefs()->GetBoolean(prefs::kWebKitForceDarkModeEnabled) ||\n"
     "        (iris::recolor::IsOnForUrl(iris_profile,\n"
     "                                   web_contents->GetLastCommittedURL()) &&\n"
     "         !web_contents->GetPrimaryMainFrame()->IsErrorDocument());\n"
     "    prefs_changed |= web_prefs->force_dark_mode_enabled != iris_dark;\n"
     "    web_prefs->force_dark_mode_enabled = iris_dark;\n"
     "  }\n",
     "const bool iris_dark =", "recolour (after navigation)")
edit(c, '#include "chrome/browser/chrome_content_browser_client.h"\n',
     '#include "chrome/browser/chrome_content_browser_client.h"\n'
     '#include "chrome/browser/iris/iris_web_recolor.h"  // Iris\n',
     'iris_web_recolor.h"  // Iris', "include")
PY
echo "=== Recolour websites complete ==="
