#!/usr/bin/env python3
"""
Vector-style textures for the slam-jump impact (src/vfx/slam_fx.gd), flat shapes only:
  - assets/images/vfx/slam_cracks_<n>.png       the crack decal (dark flat cracks on transparent), three
                                                densities: 0 light (5 cracks), 1 medium (8 + branches),
                                                2 heavy (12 + branches, a crushed crater, loose chips)
  - assets/images/vfx/slam_cracks_glow_<n>.png  the same cracks' cores only, hot orange on black: the decal's
                                                emission, lit at high intensity (embers in the cracks)
  - assets/images/vfx/slam_ring.png             the shockwave: a pale ring band with a chipped outer edge
  - assets/images/vfx/slam_puff.png             a dust puff: a flat cloud shape (a few overlapping circles)
Deterministic (fixed seeds). Run from the project root:
    python3 tools/texgen/slam_fx.py
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = "assets/images/vfx"
SS = 4  # supersampling

CRACK = (16, 12, 10)       # near-black brown: the crack's colour (the decal multiplies nothing, it's drawn as is)
CRATER = (34, 27, 23)      # the crushed middle, a touch lighter than the cracks
GLOW = (255, 120, 30)      # hot core


def jagged(rng, start, angle, length, steps, wobble):
    """A crack's centreline: a polyline from start, heading `angle`, kinking a little every step."""
    pts = [start]
    x, y = start
    a = angle
    seg = length / steps
    for _ in range(steps):
        a += rng.uniform(-wobble, wobble)
        x += math.cos(a) * seg
        y += math.sin(a) * seg
        pts.append((x, y))
    return pts


def tapered(pts, w0, w1):
    """A flat polygon along a polyline, w0 wide at its start, w1 at its tip (a wedge: cracks open at the hit)."""
    left, right = [], []
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        if i < n - 1:
            dx, dy = pts[i + 1][0] - x, pts[i + 1][1] - y
        else:
            dx, dy = x - pts[i - 1][0], y - pts[i - 1][1]
        d = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / d, dx / d
        w = (w0 + (w1 - w0) * i / (n - 1)) * 0.5
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


def blob(rng, cx, cy, r, sides, rough):
    """An irregular flat polygon round (cx, cy): the crater, a chip."""
    out = []
    a0 = rng.uniform(0, math.tau)
    for i in range(sides):
        a = a0 + math.tau * i / sides + rng.uniform(-0.15, 0.15)
        rr = r * rng.uniform(1.0 - rough, 1.0 + rough)
        out.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return out


def cracks(level, size=512):
    """Returns (albedo RGBA, glow RGB) for one density level."""
    rng = random.Random(1337 + level * 71)
    S = size * SS
    c = S / 2
    R = S / 2 * 0.96  # the longest crack reaches this far
    count = [5, 8, 12][level]
    branch_p = [0.0, 0.55, 0.9][level]
    alb = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glo = Image.new("RGB", (S, S), (0, 0, 0))
    da = ImageDraw.Draw(alb)
    dg = ImageDraw.Draw(glo)
    base_w = S * [0.022, 0.026, 0.03][level]

    # the crushed middle
    crater_r = S * [0.06, 0.08, 0.11][level]
    crater = blob(rng, c, c, crater_r, 14, 0.18)

    angles = [math.tau * i / count + rng.uniform(-0.25, 0.25) for i in range(count)]
    for a in angles:
        length = R * rng.uniform(0.6, 1.0)
        start = (c + math.cos(a) * crater_r * 0.3, c + math.sin(a) * crater_r * 0.3)
        line = jagged(rng, start, a, length - crater_r * 0.3, 7, 0.35)
        w = base_w * rng.uniform(0.75, 1.2)
        da.polygon(tapered(line, w, w * 0.08), fill=CRACK + (235,))
        dg.polygon(tapered(line[: len(line) * 2 // 3 + 1], w * 0.35, w * 0.05), fill=GLOW)
        # branches off the outer part
        for j in range(2, len(line) - 2):
            if rng.random() < branch_p * 0.35:
                ba = a + rng.choice((-1, 1)) * rng.uniform(0.45, 0.9)
                bl = length * rng.uniform(0.15, 0.32)
                bline = jagged(rng, line[j], ba, bl, 4, 0.4)
                bw = w * (1.0 - j / len(line)) * 0.7
                da.polygon(tapered(bline, bw, bw * 0.1), fill=CRACK + (225,))
    # the crushed middle, over the cracks' blunt starts
    da.polygon(crater, fill=CRATER + (225,))
    dg.polygon(blob(rng, c, c, crater_r * 0.4, 9, 0.3), fill=GLOW)
    # loose chips round the crater (heavy only) and a broken ring between the cracks (medium+)
    if level >= 1:
        ring_r = crater_r * 1.9
        for i in range(count):
            a0 = angles[i] + 0.12
            a1 = angles[(i + 1) % count] - 0.12 + (math.tau if i == count - 1 else 0)
            if rng.random() < 0.6:
                mid = (a0 + a1) / 2
                span = (a1 - a0) * rng.uniform(0.3, 0.6)
                arc = [(c + math.cos(mid - span / 2 + span * k / 6) * ring_r, c + math.sin(mid - span / 2 + span * k / 6) * ring_r) for k in range(7)]
                da.polygon(tapered(arc, base_w * 0.35, base_w * 0.35), fill=CRACK + (210,))
    if level == 2:
        for _ in range(14):
            a = rng.uniform(0, math.tau)
            r = crater_r * rng.uniform(1.1, 2.6)
            da.polygon(blob(rng, c + math.cos(a) * r, c + math.sin(a) * r, S * rng.uniform(0.008, 0.016), 5, 0.3), fill=CRACK + (220,))

    alb = alb.resize((size, size), Image.LANCZOS)
    glo = glo.filter(ImageFilter.GaussianBlur(SS * 1.5)).resize((size, size), Image.LANCZOS)
    return alb, glo


def ring(size=256):
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = random.Random(7)
    c = S / 2
    outer = []
    inner = []
    n = 72
    for i in range(n):
        a = math.tau * i / n
        ro = S / 2 * 0.97 * rng.uniform(0.94, 1.0)
        ri = S / 2 * 0.80 * rng.uniform(0.97, 1.03)
        outer.append((c + math.cos(a) * ro, c + math.sin(a) * ro))
        inner.append((c + math.cos(a) * ri, c + math.sin(a) * ri))
    d.polygon(outer, fill=(255, 255, 255, 255))
    d.polygon(inner, fill=(0, 0, 0, 0))
    return img.resize((size, size), Image.LANCZOS)


def puff(size=128):
    S = size * SS
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    for (ox, oy, r) in [(0, 0.06, 0.3), (-0.2, 0.1, 0.22), (0.2, 0.1, 0.23), (-0.1, -0.12, 0.22), (0.12, -0.1, 0.2)]:
        cx, cy, rr = c + ox * S, c + oy * S, r * S
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for level in range(3):
        alb, glo = cracks(level)
        alb.save(f"{OUT}/slam_cracks_{level}.png")
        glo.save(f"{OUT}/slam_cracks_glow_{level}.png")
    ring().save(f"{OUT}/slam_ring.png")
    puff().save(f"{OUT}/slam_puff.png")
    print("slam fx textures written to", OUT)


if __name__ == "__main__":
    main()
