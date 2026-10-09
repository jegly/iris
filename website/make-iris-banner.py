#!/usr/bin/env python3
# Iris README banner (website/iris-banner.svg). Orb + "Iris" (DotGothic16 outlines, taken from website/readme-banner.svg) +
# subtitle + feature badges + a subtle 80s grid, Catppuccin Mocha.
# Usage (from website/): python3 make-iris-banner.py readme-banner.svg iris-banner.svg
import math, re, sys
src, out_path = sys.argv[1], sys.argv[2]
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

grid = "".join(f'<g stroke="rgba(203,166,247,0.18)" stroke-width="1"><line x1="{x-5}" y1="{y}" x2="{x+5}" y2="{y}"/>'
               f'<line x1="{x}" y1="{y-5}" x2="{x}" y2="{y+5}"/></g>' for x in range(128, W, 128) for y in range(80, HORIZON, 80))
brackets = (f'<g stroke="{SURF}" stroke-width="2" fill="none"><path d="M 28 56 L 28 28 L 56 28"/>'
            f'<path d="M {W-56} 28 L {W-28} 28 L {W-28} 56"/><path d="M 28 {H-56} L 28 {H-28} L 56 {H-28}"/>'
            f'<path d="M {W-56} {H-28} L {W-28} {H-28} L {W-28} {H-56}"/></g>')

cx, cy, r = 150, 136, 76

# 80s perspective grid: lines from a vanishing point on the horizon, rows closer together near it, faded towards it.
VPX = W // 2
retro = []
for k in range(-24, 25):
    retro.append(f'<line x1="{VPX}" y1="{HORIZON}" x2="{VPX + k * 110}" y2="{H}"/>')
for i in range(1, 11):
    y = HORIZON + (H - HORIZON) * (i / 10) ** 1.8
    retro.append(f'<line x1="0" y1="{y:.1f}" x2="{W}" y2="{y:.1f}"/>')
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
<clipPath id="orb"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath>
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
