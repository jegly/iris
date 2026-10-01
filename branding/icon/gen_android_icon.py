# Iris Android adaptive icon (jegly 2026-10-01: orb fills the icon, no ring). Pure PIL.
# Background layer: the orb sized to the visible circle (72/108 of the layer); outside it, each pixel takes the
# orb's edge colour along the same angle (radial edge extension), so square/squircle masks show no seam.
# Foreground layer: transparent.
# Usage: python3 gen_android_icon.py <orb.png> <out-dir> [preview.png]
#   <orb.png>: any square orb image with transparency, e.g. branding/icon/generated/product_logo_512.png
#   <out-dir>: branding/icon/generated-android (read by patches/apply-rebrand-android.sh)
import os, sys, math
from PIL import Image, ImageDraw
src = Image.open(sys.argv[1]).convert("RGBA"); out = sys.argv[2]
orb = src.crop(src.split()[-1].getbbox())
M = 1296; R = M*72/108/2; D = int(2*R)
o = orb.resize((D, D), Image.LANCZOS).convert("RGB"); op = o.load()
img = Image.new("RGB", (M, M)); ip = img.load(); c = (M-1)/2; off = c-R; lim = R*0.985
for y in range(M):
    dy = y-c
    for x in range(M):
        dx = x-c; r = math.hypot(dx, dy) or 1e-6; s = min(r, lim)/r
        sx = min(max(int(c+dx*s-off), 0), D-1); sy = min(max(int(c+dy*s-off), 0), D-1)
        ip[x, y] = op[sx, sy]
for d, n in {"mdpi":108,"hdpi":162,"xhdpi":216,"xxhdpi":324,"xxxhdpi":432}.items():
    os.makedirs(f"{out}/mipmap-{d}", exist_ok=True)
    img.resize((n,n), Image.LANCZOS).save(f"{out}/mipmap-{d}/layered_app_icon_background.png", optimize=True)
    Image.new("RGBA",(n,n),(0,0,0,0)).save(f"{out}/mipmap-{d}/layered_app_icon.png", optimize=True)
if len(sys.argv) > 3:
    p = Image.open(f"{out}/mipmap-xxxhdpi/layered_app_icon_background.png"); n = p.size[0]
    v = int(n*72/108); k = (n-v)//2; vis = p.crop((k,k,k+v,k+v))
    prev = Image.new("RGB",(v*3+40, v+20),(30,30,46))
    for i,s in enumerate(["circle","rr","sq"]):
        m = Image.new("L",(v,v),0); dr = ImageDraw.Draw(m); b = (0,0,v-1,v-1)
        if s == "circle": dr.ellipse(b, fill=255)
        elif s == "rr": dr.rounded_rectangle(b, radius=v//3, fill=255)
        else: dr.rectangle(b, fill=255)
        prev.paste(vis,(10+i*(v+10),10),m)
    prev.save(sys.argv[3])
print("ok")
