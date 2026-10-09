#!/usr/bin/env python3
# Iris README banner (website/iris-banner.svg). Orb + "Iris" (DotGothic16 outlines, taken from website/readme-banner.svg) +
# subtitle + feature badges + a faint real night sky over a subtle 80s grid, Catppuccin Mocha.
# Usage (from website/): python3 make-iris-banner.py readme-banner.svg iris-banner.svg
import math, re, sys
src, out_path = sys.argv[1], sys.argv[2]
STYLE = sys.argv[3] if len(sys.argv) > 3 else "mauve"  # 80s grid: "mauve" (default) or "neon-green"
s = open(src).read()
g = re.search(r'<g fill="#CDD6F4" transform="translate\(72 178\)">(.*?)</g>', s, re.S).group(1)
paths = re.findall(r'<path transform="translate\(([\d.]+) 0\) scale\(([\d.]+) ([-\d.]+)\)" d="([^"]*)"/>', g)[:4]
iris = "".join(f'<path transform="translate({x} 0) scale({sx} {sy})" d="{d}"/>' for x, sx, sy, d in paths)

W, H = 1280, 480
HORIZON = 214  # 80s grid horizon
CRUST, BASE, SURF = "#11111b", "#1e1e2e", "#313244"
TEXT, SUB = "#cdd6f4", "#a6adc8"
MAUVE, GREEN, PEACH, SKY, BLUE, YELLOW, RED, TEAL, PINK = ("#cba6f7", "#a6e3a1", "#fab387", "#89dceb", "#89b4fa",
                                                          "#f9e2af", "#f38ba8", "#94e2d5", "#f5c2e7")
ROWS = [
    [("Post-quantum TLS (ML-KEM)", MAUVE), ("Strict PQ mode", MAUVE), ("TLS 1.3 only", BLUE),
     ("Encrypted Client Hello", BLUE), ("Strict site isolation", TEAL)],
    [("No JIT", PEACH), ("No WebAssembly", PEACH), ("No WebRTC", RED), ("No WebGPU", RED), ("CFI + Rust decoders", YELLOW)],
    [("Ad and tracker blocking", GREEN), ("Fingerprint randomisation", GREEN), ("No Google services", SKY),
     ("Zero telemetry", SKY), ("Encrypted DNS", BLUE)],
    [("App lock", PINK), ("Data shredding", PINK), ("Per-site identity", MAUVE), ("PQC-signed releases", YELLOW),
     ("Exploit mitigations", TEAL)],
]

# Night sky above the 80s grid: real stars (J2000 RA/Dec in degrees, visual magnitude), no lines, kept faint.
# A strip of the northern sky from Dec +24 to +66, centred on the Big Dipper, drawn as star charts are (north up,
# east to the left); each star's RA offset is scaled by cos(Dec) so shapes stay true across the strip.
STARS = [
    # Ursa Major
    (165.93, 61.75, 1.8), (165.46, 56.38, 2.4), (178.46, 53.69, 2.4), (183.86, 57.03, 3.3), (193.51, 55.96, 1.8),
    (200.98, 54.93, 2.2), (206.89, 49.31, 1.9), (127.57, 60.72, 3.4), (143.21, 51.68, 3.2), (134.80, 48.04, 3.1),
    (135.91, 47.16, 3.6), (154.27, 42.91, 3.5), (155.58, 41.50, 3.0), (169.62, 33.09, 3.5), (169.55, 31.53, 3.8),
    (167.42, 44.50, 3.0), (176.51, 47.78, 3.7),
    # Canes Venatici, Leo Minor, Lynx
    (194.01, 38.32, 2.9), (188.44, 41.36, 4.3), (163.33, 34.21, 3.8), (140.26, 34.39, 3.1), (139.71, 36.80, 3.8),
    # Bootes
    (221.25, 27.07, 2.4), (218.02, 38.31, 3.0), (225.49, 40.39, 3.5), (228.88, 33.31, 3.5), (217.96, 30.37, 3.6),
    # Corona Borealis
    (233.67, 26.71, 2.2), (231.96, 29.11, 3.7), (235.69, 26.30, 3.8), (237.40, 26.07, 4.6), (233.23, 31.36, 4.1),
    (239.40, 26.88, 4.2),
    # Hercules
    (250.32, 31.60, 2.8), (250.72, 38.92, 3.5), (258.76, 36.81, 3.2), (255.07, 30.93, 3.9), (258.76, 24.84, 3.1),
    (266.61, 27.72, 3.4), (269.06, 37.25, 3.9), (264.87, 46.01, 3.8), (244.94, 46.31, 3.9), (242.19, 44.94, 4.3),
    # Lyra
    (279.23, 38.78, 0.0), (282.52, 33.36, 3.5), (284.74, 32.69, 3.3), (281.19, 37.61, 4.4), (283.63, 36.90, 4.3),
    # Cygnus
    (310.36, 45.28, 1.3), (305.56, 40.26, 2.2), (311.55, 33.97, 2.5), (296.24, 45.13, 2.9), (292.68, 27.96, 3.1),
    (318.23, 30.23, 3.2), (292.43, 51.73, 3.8), (289.28, 53.37, 3.8), (299.08, 35.08, 3.9),
    # Draco
    (269.15, 51.49, 2.2), (262.61, 52.30, 2.8), (268.38, 56.87, 3.8), (288.14, 65.66, 3.1), (257.20, 65.71, 3.2),
    (245.99, 61.51, 2.7), (240.47, 58.57, 4.0), (231.23, 58.97, 3.3), (211.10, 64.38, 3.7),
    # Cepheus, Lacerta
    (319.64, 62.59, 2.5), (332.71, 58.20, 3.4), (337.29, 58.42, 3.8), (311.32, 61.84, 3.4), (337.82, 50.28, 3.8),
    # Andromeda, Triangulum
    (2.10, 29.09, 2.1), (17.43, 35.62, 2.1), (30.97, 42.33, 2.1), (9.83, 30.86, 3.3), (14.19, 38.50, 3.9),
    (9.22, 33.72, 4.4), (32.39, 34.99, 3.0), (28.27, 29.58, 3.4),
    # Cassiopeia
    (2.29, 59.15, 2.3), (10.13, 56.54, 2.2), (14.18, 60.72, 2.2), (21.45, 60.24, 2.7), (28.60, 63.67, 3.4),
    # Perseus
    (51.08, 49.86, 1.8), (47.04, 40.96, 2.1), (58.53, 31.88, 2.9), (59.46, 40.01, 2.9), (46.20, 53.51, 2.9),
    (55.73, 47.79, 3.0), (42.67, 55.90, 3.8), (56.30, 42.58, 3.8),
    # Auriga, Taurus (Elnath)
    (79.17, 45.99, 0.1), (89.88, 44.95, 1.9), (89.93, 37.21, 2.6), (74.25, 33.17, 2.7), (75.49, 43.82, 3.0),
    (76.63, 41.23, 3.2), (75.62, 41.08, 3.8), (81.57, 28.61, 1.7),
    # Gemini
    (113.65, 31.89, 1.6), (116.33, 28.03, 1.2),
]
RA0, DEC_TOP, SKY_SCALE, SKY_TOP = 186.0, 66.0, 4.5, 14   # Big Dipper in the middle; px per degree
def project(ra, dec):
    d_ra = (ra - RA0 + 180) % 360 - 180
    return W / 2 - d_ra * math.cos(math.radians(dec)) * SKY_SCALE, SKY_TOP + (DEC_TOP - dec) * SKY_SCALE
sky = []
for ra, dec, mag in STARS:
    x, y = project(ra, dec)
    if not (12 < x < W - 12) or (x - 150) ** 2 + (y - 136) ** 2 < 120 ** 2:   # off the edge, or on the orb
        continue
    r = max(0.6, 1.7 - 0.28 * mag)
    if mag < 1.0:
        sky.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r * 2.2:.1f}" fill="{MAUVE}" fill-opacity="0.12" filter="url(#starglow)"/>')
    sky.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.2f}" fill="{TEXT}" fill-opacity="{max(0.14, 0.6 - 0.1 * mag):.2f}"/>')
grid = '<g clip-path="url(#skyclip)">' + "".join(sky) + "</g>"
brackets = (f'<g stroke="{SURF}" stroke-width="2" fill="none"><path d="M 28 56 L 28 28 L 56 28"/>'
            f'<path d="M {W-56} 28 L {W-28} 28 L {W-28} 56"/><path d="M 28 {H-56} L 28 {H-28} L 56 {H-28}"/>'
            f'<path d="M {W-56} {H-28} L {W-28} {H-28} L {W-28} {H-56}"/></g>')

cx, cy, r = 150, 136, 76
NEON_FILTER = ('<filter id="neon" x="-10%" y="-10%" width="120%" height="120%">'
               '<feGaussianBlur stdDeviation="2.5"/></filter>\n') if STYLE == "neon-green" else ""

# 80s perspective grid: lines from a vanishing point on the horizon, rows closer together near it, faded towards it.
VPX = W // 2
retro = []
for k in range(-24, 25):
    retro.append(f'<line x1="{VPX}" y1="{HORIZON}" x2="{VPX + k * 110}" y2="{H}"/>')
for i in range(1, 11):
    y = HORIZON + (H - HORIZON) * (i / 10) ** 1.8
    retro.append(f'<line x1="0" y1="{y:.1f}" x2="{W}" y2="{y:.1f}"/>')
if STYLE == "neon-green":
    # a soft blurred glow under thin bright lines
    retro_grid = (f'<g mask="url(#retrofade)">'
                  f'<g stroke="{GREEN}" stroke-opacity="0.28" stroke-width="3" filter="url(#neon)">' + "".join(retro) + "</g>"
                  f'<g stroke="{GREEN}" stroke-opacity="0.30" stroke-width="1">' + "".join(retro) + "</g></g>")
else:
    retro_grid = (f'<g mask="url(#retrofade)" stroke="{MAUVE}" stroke-opacity="0.16" stroke-width="1.2">'
                  + "".join(retro) + "</g>")
def sectors(R):
    def sector(a0, a1, color):
        p = lambda a: (cx + R * math.sin(math.radians(a)), cy - R * math.cos(math.radians(a)))
        (x0, y0), (x1, y1) = p(a0), p(a1)
        large = 1 if (a1 - a0) % 360 > 180 else 0
        return f'<path fill="{color}" d="M{cx} {cy} L{x0:.1f} {y0:.1f} A{R} {R} 0 {large} 1 {x1:.1f} {y1:.1f} Z"/>'
    return "".join([sector(-35, 22, "#F3F06A"), sector(22, 78, "#A8FA5E"), sector(78, 160, "#D67563"),
                    sector(160, 258, "#339FFF"), sector(258, 325, "#E9EE9E")])

SIZE, GAP, ROWH, Y0 = 17, 10, 50, 252
def width(label): return int(len(label) * SIZE * 0.55) + 32
badges = []
for i, row in enumerate(ROWS):
    total = sum(width(l) for l, _ in row) + GAP * (len(row) - 1)
    assert total <= W - 120, ("row too wide", i, total)
    x, y = (W - total) // 2, Y0 + i * ROWH
    for label, color in row:
        w = width(label)
        badges.append(f'<g><rect x="{x}" y="{y}" width="{w}" height="38" rx="19" fill="none" stroke="{color}" stroke-width="1.25"/>'
                      f'<text x="{x + w/2:.0f}" y="{y + 19}" fill="{color}" font-family="Inter, system-ui, sans-serif" '
                      f'font-size="{SIZE}" font-weight="500" text-anchor="middle" dominant-baseline="middle">{label}</text></g>')
        x += w + GAP

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="Iris: a hardened, privacy-first browser built on Chromium">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{CRUST}"/><stop offset="1" stop-color="{BASE}"/></linearGradient>
<radialGradient id="corner" cx="0%" cy="100%" r="70%"><stop offset="0%" stop-color="{SURF}" stop-opacity="0.55"/><stop offset="100%" stop-color="{SURF}" stop-opacity="0"/></radialGradient>
<linearGradient id="accent" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{BLUE}"/><stop offset="0.5" stop-color="{MAUVE}"/><stop offset="1" stop-color="{PEACH}"/></linearGradient>
<linearGradient id="retrofadegrad" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="0.45" stop-color="white" stop-opacity="0.55"/><stop offset="1" stop-color="white" stop-opacity="1"/></linearGradient>
<mask id="retrofade" maskUnits="userSpaceOnUse" x="0" y="{HORIZON}" width="{W}" height="{H - HORIZON}"><rect x="0" y="{HORIZON}" width="{W}" height="{H - HORIZON}" fill="url(#retrofadegrad)"/></mask>
<clipPath id="skyclip"><rect x="0" y="0" width="{W}" height="{HORIZON - 4}"/></clipPath>
<clipPath id="orb"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath>
{NEON_FILTER}<filter id="starglow" x="-200%" y="-200%" width="500%" height="500%"><feGaussianBlur stdDeviation="2"/></filter>
<filter id="halo" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="30"/></filter>
<filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="15"/></filter>
</defs>
<rect width="{W}" height="{H}" fill="url(#bg)"/>
<rect width="{W}" height="{H}" fill="url(#corner)"/>
{grid}
{retro_grid}
{brackets}
<g filter="url(#halo)" opacity="0.6">{sectors(r * 1.05)}</g>
<g clip-path="url(#orb)"><g filter="url(#soft)">{sectors(r * 1.5)}</g></g>
<g fill="{TEXT}" transform="translate(272 156) scale(2.6)">{iris}</g>
<g fill="{TEXT}" transform="translate(277 156) scale(2.6)">{iris}</g>
<text x="574" y="104" fill="{SUB}" font-family="Inter, system-ui, sans-serif" font-size="27" dominant-baseline="hanging">A hardened, privacy-first browser</text>
<text x="574" y="140" fill="{SUB}" font-family="Inter, system-ui, sans-serif" font-size="27" dominant-baseline="hanging">built on Chromium</text>
<rect x="574" y="188" width="420" height="3" fill="url(#accent)"/>
{"".join(badges)}
</svg>
'''
open(out_path, "w").write(svg)
print(out_path, len(svg), "bytes,", sum(len(r) for r in ROWS), "badges")
