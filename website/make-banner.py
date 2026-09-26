#!/usr/bin/env python3
# Builds readme-banner.svg: the website hero (orb + "Iris, built on Chromium. / Made for security and privacy.")
# as a self-contained SVG for the GitHub README. Text is converted to outlines (GitHub serves SVGs with a CSP that
# blocks embedded fonts). Needs fontTools + brotli (reads fonts/DotGothic16-Regular-latin.woff2).
import math
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen

W, H = 1280, 400
SIZE = 48                      # px; 15 em longest line -> 720 px
BOLD = SIZE / 16               # one font-pixel: the page's pixel-bold offset
TEXT, MAUVE, BASE = "#CDD6F4", "#CBA6F7", "#1E1E2E"

font = TTFont("fonts/DotGothic16-Regular-latin.woff2")
gs, cmap, hmtx = font.getGlyphSet(), font.getBestCmap(), font["hmtx"]
scale = SIZE / font["head"].unitsPerEm

def text_path(s):
    out, x = [], 0
    for ch in s:
        name = cmap[ord(ch)]
        pen = SVGPathPen(gs)
        gs[name].draw(pen)
        d = pen.getCommands()
        if d:
            out.append(f'<path transform="translate({x:.2f} 0) scale({scale:.5f} {-scale:.5f})" d="{d}"/>')
        x += hmtx[name][0] * scale
    return "".join(out)

def line(s, y, color):
    g = text_path(s)
    return (f'<g fill="{color}" transform="translate(72 {y})">{g}</g>'
            f'<g fill="{color}" transform="translate({72 + BOLD} {y})">{g}</g>')

# Orb: blurred colour sectors clipped to a circle (the page uses a CSS conic-gradient + blur).
cx, cy, r = 1060, 200, 150
R = r * 1.5
def sector(a0, a1, color):
    p = lambda a: (cx + R * math.sin(math.radians(a)), cy - R * math.cos(math.radians(a)))
    (x0, y0), (x1, y1) = p(a0), p(a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f'<path fill="{color}" d="M{cx} {cy} L{x0:.1f} {y0:.1f} A{R} {R} 0 {large} 1 {x1:.1f} {y1:.1f} Z"/>'
sectors = "".join([sector(-35, 22, "#F3F06A"), sector(22, 78, "#A8FA5E"), sector(78, 160, "#D67563"),
                   sector(160, 258, "#339FFF"), sector(258, 325, "#E9EE9E")])

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="Iris, built on Chromium. Made for security and privacy.">
<defs>
<clipPath id="orb"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath>
<filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="26"/></filter>
</defs>
<rect width="{W}" height="{H}" rx="20" fill="{BASE}"/>
<g clip-path="url(#orb)"><g filter="url(#soft)">{sectors}</g></g>
{line("Iris, built on Chromium.", 178, TEXT)}
{line("Made for security and privacy.", 250, MAUVE)}
</svg>
'''
open("readme-banner.svg", "w").write(svg)
print("readme-banner.svg", len(svg), "bytes")
