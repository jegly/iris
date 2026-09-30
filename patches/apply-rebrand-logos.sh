#!/usr/bin/env bash
# Iris — the Chromium logos apply-rebrand.sh missed (found by jegly in the first dev-build run, 2026-09-27;
# every target verified against this checkout).
# 1. WebUI 16/32 px product logos. chrome://theme/current-channel-logo (Settings header via cr-toolbar, About page)
#    = IDR_PRODUCT_LOGO_32 = chrome/app/theme/default_{100,200}_percent/chromium/product_logo_32.png. Also
#    IDR_PRODUCT_LOGO_16 (tab icon fallback, task manager "Browser" row), the Linux copies, and the 2x variants.
# 2. Wordmarks (orb + "Iris" in DotGothic16, rendered by branding/wordmark/make-wordmarks.sh, same pixel sizes):
#    components/resources/.../chromium/product_logo{,_white}.png = IDR_PRODUCT_LOGO{,_WHITE} (chrome://version
#    header, NTP theme attribution) and chrome/app/theme/.../product_logo_name_22{,_white}.png (payment sheet;
#    Web Payments is off in Iris, replaced anyway so no Chromium wordmark ships).
# 3. IDR_PRODUCT_LOGO_SVG / IDR_PRODUCT_LOGO_ANIMATION_SVG (chrome/app/theme/chromium/*.svg): profile picker,
#    first-run intro, default-browser and search-engine-choice dialogs. Replaced by an SVG that wraps the 256 px orb
#    PNG (the orb is a raster gradient; the intro "animation" becomes the still orb).
# 4. The "chrome-product" WebUI icon (Settings sidebar "About Iris", Safety Hub, cr/webui-browser iconsets): every
#    <g id="chrome-product"> body becomes a vector orb — the four orb colours as sectors, blurred, clipped to a circle
#    (r = 5/12 of the box, Material keyline). Explicit fills, so it keeps its colours when the row is selected
#    (a plain disc took the icon tint and showed black; jegly 2026-09-27). Pure SVG: no data: image, no CSP question.
#    cr-iconset clones the whole <g> (defs included) into each icon. Upgrades the earlier disc in place.
# 5. The dark-mode header logo of cr-toolbar pages (Settings, Extensions, ...) is NOT current-channel-logo but
#    ui/webui/resources/images/chrome_logo_dark.svg -> an SVG wrapping the 64 px orb PNG.
# NOT CHANGED: chrome/app/theme/chromium/linux/product_logo_32.xpm (not referenced by any build file here).
# Needs branding/icon/generated/{product_logo_*.png,wordmark_*.png}. Idempotent (cmp / markers); fails on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
GEN="$DIR/../branding/icon/generated"
cd "$SRC"
put() {
  local from="$GEN/$1" to="$2"
  [ -f "$to" ] || { echo "ERROR: $to missing (drift?)" >&2; exit 1; }
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$to"; then echo "SKIP already applied: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
}
T=chrome/app/theme; C=components/resources
# 1. 16/32 px logos (1x and 2x)
put product_logo_16.png "$T/default_100_percent/chromium/product_logo_16.png"
put product_logo_32.png "$T/default_100_percent/chromium/product_logo_32.png"
put product_logo_16.png "$T/default_100_percent/chromium/linux/product_logo_16.png"
put product_logo_32.png "$T/default_100_percent/chromium/linux/product_logo_32.png"
put product_logo_32.png "$T/default_200_percent/chromium/product_logo_16.png"
put product_logo_64.png "$T/default_200_percent/chromium/product_logo_32.png"
# 2. wordmarks
put wordmark_22.png       "$T/default_100_percent/chromium/product_logo_name_22.png"
put wordmark_22_white.png "$T/default_100_percent/chromium/product_logo_name_22_white.png"
put wordmark_44.png       "$T/default_200_percent/chromium/product_logo_name_22.png"
put wordmark_44_white.png "$T/default_200_percent/chromium/product_logo_name_22_white.png"
put wordmark_32.png       "$C/default_100_percent/chromium/product_logo.png"
put wordmark_32_white.png "$C/default_100_percent/chromium/product_logo_white.png"
put wordmark_64.png       "$C/default_200_percent/chromium/product_logo.png"
put wordmark_64_white.png "$C/default_200_percent/chromium/product_logo_white.png"

python3 - "$GEN" <<'PY'
import base64, re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
gen = sys.argv[1]
# 3. SVG product logos
png = base64.b64encode(open(gen + "/product_logo_256.png", "rb").read()).decode()
svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><!-- Iris orb -->'
       '<image width="256" height="256" href="data:image/png;base64,' + png + '"/></svg>\n')
for p in ("chrome/app/theme/chromium/product_logo.svg", "chrome/app/theme/chromium/product_logo_animation.svg"):
    try: cur = open(p).read()
    except FileNotFoundError: die(p + " missing (drift?)")
    if cur == svg: print("SKIP already applied: " + p); continue
    open(p, "w").write(svg); print("OK   " + p)
png64 = base64.b64encode(open(gen + "/product_logo_64.png", "rb").read()).decode()
svg64 = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><!-- Iris orb -->'
         '<image width="24" height="24" href="data:image/png;base64,' + png64 + '"/></svg>\n')
p = "ui/webui/resources/images/chrome_logo_dark.svg"
try: cur = open(p).read()
except FileNotFoundError: die(p + " missing (drift?)")
if cur == svg64: print("SKIP already applied: " + p)
else: open(p, "w").write(svg64); print("OK   " + p + " (cr-toolbar dark-mode logo)")
# 4. chrome-product icons -> vector orb (24-unit design, scaled into each icon box)
import math
ORB = "<!-- Iris orb v2 -->"
def orb24():
    pts = lambda a: (12 + 16 * math.cos(math.radians(a)), 12 + 16 * math.sin(math.radians(a)))
    paths = ""
    for col, a0, a1 in (("#F3F06A", 195, 300), ("#A8FA5E", 300, 332), ("#D67563", 332, 420), ("#339FFF", 420, 555)):
        (x0, y0), (x1, y1) = pts(a0), pts(a1)
        paths += '<path fill="%s" d="M12 12L%.2f %.2fA16 16 0 0 1 %.2f %.2fZ"></path>' % (col, x0, y0, x1, y1)
    return ('<defs><clipPath id="iris-orb-clip"><circle cx="12" cy="12" r="10"></circle></clipPath>'
            '<filter id="iris-orb-blur" x="-50%" y="-50%" width="200%" height="200%">'
            '<feGaussianBlur stdDeviation="2.6"></feGaussianBlur></filter></defs>'
            '<g clip-path="url(#iris-orb-clip)"><g filter="url(#iris-orb-blur)">' + paths + '</g></g>')
files = ["ui/webui/resources/cr_elements/icons.html.ts",
         "chrome/browser/resources/settings/icons.html.ts",
         "chrome/browser/resources/webui_browser/icons.html.ts"]
g_re = re.compile(r'(<g id="chrome-product"(?: viewBox="([^"]+)")?>)(.*?)(</g>)', re.S)
for p in files:
    s = open(p).read()
    if not g_re.search(s): die(p + ": no chrome-product icon (drift?)")
    def disc(m):
        if ORB in m.group(3): return m.group(0)
        if m.group(2):
            x, y, w, h = (float(v) for v in m.group(2).split())
        else:  # size from the enclosing <cr-iconset size="N">; no size attribute means 24
            head = s[:m.start()]
            sz = re.findall(r'<cr-iconset name="[^"]+"(?: size="(\d+)")?>', head)
            if not sz: die(p + ": chrome-product outside a cr-iconset")
            x = y = 0.0; w = h = float(sz[-1] or 24)
        k = w / 24
        body = orb24() if (x, y, k) == (0, 0, 1) else '<g transform="translate(%g %g) scale(%g)">%s</g>' % (x, y, k, orb24())
        return m.group(1) + ORB + body + m.group(4)
    n = g_re.sub(disc, s)
    if n == s: print("SKIP already applied: " + p); continue
    open(p, "w").write(n); print("OK   " + p + " : chrome-product icon -> vector orb (%d)" % len(g_re.findall(s)))
# guard: current-channel-logo still maps unbranded builds to IDR_PRODUCT_LOGO_32
c = open("chrome/browser/ui/webui/current_channel_logo.cc").read()
if "IDR_PRODUCT_LOGO_32;" not in c: die("current_channel_logo.cc no longer returns IDR_PRODUCT_LOGO_32")
print("OK   guard: current-channel-logo -> IDR_PRODUCT_LOGO_32")
PY
echo "=== logo rebrand complete ==="
