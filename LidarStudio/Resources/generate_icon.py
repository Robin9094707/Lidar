import sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048
out = sys.argv[1]
# background radial gradient
y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
d = np.sqrt((x-0.5)**2 + (y-0.38)**2)
top = np.array([16, 34, 68], np.float32)
bot = np.array([4, 6, 16], np.float32)
t = np.clip(d / 0.75, 0, 1)[..., None]
bg = top * (1 - t) + bot * t
# violet tint bottom right
v = np.clip(1 - np.sqrt((x-0.85)**2 + (y-0.95)**2) / 0.6, 0, 1)[..., None]
bg = bg + v * np.array([40, 10, 70], np.float32)
img = Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')

cyan = (80, 210, 255)
violet = (150, 110, 255)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# perspective dot floor
dots = Image.new('RGBA', (S, S), (0, 0, 0, 0))
dd = ImageDraw.Draw(dots)
horizon = S * 0.60
for r in range(1, 26):
    z = 1 + r * 0.32
    yy = horizon + (S * 0.55) / z - S * 0.12
    if yy > S: continue
    for c in range(-30, 31):
        xx = S / 2 + c * (S * 0.11) / z
        if xx < -20 or xx > S + 20: continue
        rad = max(2.0, 14 / z)
        col = lerp(cyan, violet, min(1, max(0, xx / S)))
        a = int(min(255, 60 + 900 / (z * 4)))
        dd.ellipse([xx - rad, yy - rad, xx + rad, yy + rad], fill=col + (a,))
img = Image.alpha_composite(img, dots)

# wireframe cube (isometric)
cx, cy, s = S / 2, S * 0.47, S * 0.24
def iso(px, py, pz):
    return (cx + (px - pz) * s * 0.866, cy + (px + pz) * s * 0.5 - py * s * 1.0)
V = [(-1, 0, -1), (1, 0, -1), (1, 0, 1), (-1, 0, 1), (-1, 1.6, -1), (1, 1.6, -1), (1, 1.6, 1), (-1, 1.6, 1)]
V = [(a * 0.62, b * 0.62 - 0.45, c2 * 0.62) for a, b, c2 in V]
E = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]
P = [iso(*p) for p in V]

def draw_edges(width, alpha):
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for a, b in E:
        pa, pb = P[a], P[b]
        n = 40
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            q0 = (pa[0] + (pb[0]-pa[0]) * t0, pa[1] + (pb[1]-pa[1]) * t0)
            q1 = (pa[0] + (pb[0]-pa[0]) * t1, pa[1] + (pb[1]-pa[1]) * t1)
            col = lerp(cyan, violet, min(1, max(0, (q0[1] - S*0.2) / (S*0.6))))
            ld.line([q0, q1], fill=col + (alpha,), width=width)
    return layer

glow = draw_edges(46, 150).filter(ImageFilter.GaussianBlur(40))
img = Image.alpha_composite(img, glow)
img = Image.alpha_composite(img, draw_edges(16, 255))
# vertex dots
vd = Image.new('RGBA', (S, S), (0, 0, 0, 0))
vdd = ImageDraw.Draw(vd)
for p in P:
    vdd.ellipse([p[0]-26, p[1]-26, p[0]+26, p[1]+26], fill=(255, 255, 255, 255))
img = Image.alpha_composite(img, vd.filter(ImageFilter.GaussianBlur(14)))
img = Image.alpha_composite(img, vd)

# laser line
ly = S * 0.50
laser = Image.new('RGBA', (S, S), (0, 0, 0, 0))
ldr = ImageDraw.Draw(laser)
ldr.rectangle([S*0.08, ly-40, S*0.92, ly+40], fill=cyan + (170,))
laser = laser.filter(ImageFilter.GaussianBlur(50))
img = Image.alpha_composite(img, laser)
core = Image.new('RGBA', (S, S), (0, 0, 0, 0))
cd = ImageDraw.Draw(core)
for i in range(200):
    xx0 = S*0.1 + i * (S*0.8/200)
    fade = math.sin(math.pi * i / 200)
    cd.line([(xx0, ly), (xx0 + S*0.8/200 + 1, ly)], fill=(220, 250, 255, int(255*fade)), width=10)
img = Image.alpha_composite(img, core)

img = img.convert('RGB').resize((1024, 1024), Image.LANCZOS)
img.save(out)
