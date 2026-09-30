#!/usr/bin/env bash
# Iris — fonts of the built-in pages (Settings, History, Downloads, ...) (jegly 2026-09-27; verified against this
# checkout). Linux only for now (the upstream Roboto mechanism below is Linux-only too).
# - Regular text: IBM Plex Sans (SIL OFL 1.1; branding/fonts/ibm-plex-sans, npm @ibm/plex-sans 1.1.0) instead of
#   Chromium's Roboto. Shipped INSIDE the browser exactly like upstream ships Roboto on Linux:
#   woff2 files in ui/webui/resources (served as chrome://resources/iris_fonts/...), @font-face in a stylesheet that
#   text_defaults_md.css imports (document level: @font-face is ignored inside shadow roots), and first place in the
#   WebUI font stack (ui/base/webui/web_ui_util.cc GetFontFamilyMd/GetFontFamily). Never fetched from the network.
# - Headers: DotGothic16 (OFL; website/fonts Latin subset) for the Settings section/subpage titles and the toolbar
#   title of cr-toolbar pages; the About page product name "Iris" in DotGothic16 with the website's pixel-bold
#   (text-shadow 1/16 em; the font has one weight, so font-synthesis is off). Non-Latin text falls back to Plex.
#   Exposed as CSS custom properties on :root (--iris-display-font), which inherit into shadow DOM.
# All pages keep working if a font fails to load (normal CSS fallback to the previous stack).
# TODO (release): ship both OFL texts with the packages (like filter-lists-LICENSE in apply-adblock.sh).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
FONTS="$DIR/../branding/fonts/ibm-plex-sans"
DG="$DIR/../website/fonts/DotGothic16-Regular-latin.woff2"
cd "$SRC"
OUT=ui/webui/resources/iris_fonts
mkdir -p "$OUT"
put() {
  [ -s "$1" ] || { echo "ERROR: $1 missing" >&2; exit 1; }
  if cmp -s "$1" "$2"; then echo "SKIP up to date: $2"; else cp "$1" "$2"; echo "OK   $2"; fi
}
put "$FONTS/IBMPlexSans-Regular.woff2"  "$OUT/ibm-plex-sans-regular.woff2"
put "$FONTS/IBMPlexSans-Medium.woff2"   "$OUT/ibm-plex-sans-medium.woff2"
put "$FONTS/IBMPlexSans-SemiBold.woff2" "$OUT/ibm-plex-sans-semibold.woff2"
put "$FONTS/IBMPlexSans-Bold.woff2"     "$OUT/ibm-plex-sans-bold.woff2"
put "$DG"                               "$OUT/dotgothic16-regular.woff2"

python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
def write(p, content, label):
    try: cur = open(p).read()
    except FileNotFoundError: cur = None
    if cur == content: print("SKIP up to date: " + p); return
    open(p, "w").write(content); print("OK   %s : %s" % (p, label))

# 1. font files into the chrome://resources pack (Linux block, next to Roboto)
edit("ui/webui/resources/BUILD.gn",
     '      "roboto/roboto-regular.woff2",\n    ]\n',
     '      "roboto/roboto-regular.woff2",\n'
     '      # Iris: IBM Plex Sans (UI text) + DotGothic16 (headers), apply-webui-font.sh\n'
     '      "iris_fonts/dotgothic16-regular.woff2",\n'
     '      "iris_fonts/ibm-plex-sans-bold.woff2",\n'
     '      "iris_fonts/ibm-plex-sans-medium.woff2",\n'
     '      "iris_fonts/ibm-plex-sans-regular.woff2",\n'
     '      "iris_fonts/ibm-plex-sans-semibold.woff2",\n    ]\n',
     "iris_fonts/ibm-plex-sans-regular.woff2", "font files in resources pack")

# 2. the @font-face stylesheet
face = lambda fam, w, f: ("@font-face {\n  font-family: '%s';\n  font-style: normal;\n  font-weight: %d;\n"
                          "  src: url(//resources/iris_fonts/%s) format('woff2');\n}\n\n" % (fam, w, f))
css = ("/* Iris: fonts of the built-in pages (patches/apply-webui-font.sh). Bundled, never fetched from the network.\n"
       " * IBM Plex Sans and DotGothic16 are licensed under the SIL Open Font License 1.1. */\n\n"
       + face("IBM Plex Sans", 400, "ibm-plex-sans-regular.woff2")
       + face("IBM Plex Sans", 500, "ibm-plex-sans-medium.woff2")
       + face("IBM Plex Sans", 600, "ibm-plex-sans-semibold.woff2")
       + face("IBM Plex Sans", 700, "ibm-plex-sans-bold.woff2")
       + face("DotGothic16", 400, "dotgothic16-regular.woff2")
       + ":root {\n  --iris-display-font: 'DotGothic16', 'IBM Plex Sans', sans-serif;\n}\n")
write("ui/webui/resources/css/iris_fonts.css", css, "IBM Plex Sans + DotGothic16 @font-face")
edit("ui/webui/resources/css/BUILD.gn",
     '    in_files += [ "roboto.css" ]\n',
     '    in_files += [ "roboto.css" ]\n    in_files += [ "iris_fonts.css" ]  # Iris: apply-webui-font.sh\n',
     '"iris_fonts.css"', "iris_fonts.css in css pack")
edit("ui/webui/resources/css/text_defaults_md.css",
     '@import url(//resources/css/roboto.css);\n',
     '@import url(//resources/css/roboto.css);\n@import url(//resources/css/iris_fonts.css);  /* Iris */\n',
     "iris_fonts.css", "imports iris_fonts.css")

# 3. font stack: IBM Plex Sans first (Linux)
edit("ui/base/webui/web_ui_util.cc",
     '  return "Roboto, " + GetFontFamily();\n',
     '  // Iris: IBM Plex Sans (bundled, ui/webui/resources/iris_fonts) before Roboto.\n'
     '  return "\\"IBM Plex Sans\\", Roboto, " + GetFontFamily();\n',
     'IBM Plex Sans', "WebUI font stack -> IBM Plex Sans")

# 4. DotGothic16 headers
disp = ("  /* Iris: DotGothic16 header (one weight: no synthetic bold). */\n"
        "  font-family: var(--iris-display-font, inherit);\n  font-synthesis: none;\n")
edit("chrome/browser/resources/settings/settings_page/settings_section.css",
     "#header .title {\n  color: var(--cr-primary-text-color);\n  font-size: 108%;\n  font-weight: 400;\n",
     "#header .title {\n  color: var(--cr-primary-text-color);\n" + disp + "  font-size: 108%;\n  font-weight: 400;\n",
     "--iris-display-font", "section titles in DotGothic16")
edit("chrome/browser/resources/settings/settings_page/settings_subpage.css",
     ".cr-title-text {\n  /* Title should stay on one line. */\n",
     ".cr-title-text {\n" + disp + "  font-weight: 400;\n  /* Title should stay on one line. */\n",
     "--iris-display-font", "subpage titles in DotGothic16")
edit("ui/webui/resources/cr_elements/cr_toolbar/cr_toolbar.css",
     "h1 {\n  flex: 1;\n  font-size: 170%;\n  font-weight: var(--cr-toolbar-header-font-weight, 500);\n",
     "h1 {\n  flex: 1;\n" + disp + "  font-size: 170%;\n  font-weight: 400;  /* Iris: was --cr-toolbar-header-font-weight, 500 */\n",
     "--iris-display-font", "toolbar titles in DotGothic16")
edit("chrome/browser/resources/settings/about_page/about_page.css",
     ".product-title {\n  font-size: 153.85%;  /* 20px / 13px */\n  font-weight: 400;\n",
     ".product-title {\n" + disp +
     "  text-shadow: 0.0625em 0 0 currentColor;  /* Iris: pixel-bold, as on the website */\n"
     "  letter-spacing: 0.03em;\n"
     "  font-size: 153.85%;  /* 20px / 13px */\n  font-weight: 400;\n",
     "--iris-display-font", "About \"Iris\" in pixel-bold DotGothic16")
PY
echo "=== WebUI fonts (IBM Plex Sans + DotGothic16 headers) complete ==="
