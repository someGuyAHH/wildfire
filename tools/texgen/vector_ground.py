#!/usr/bin/env python3
"""
Vector-art ground layers for Terrain3D (the M6 look: flat shapes, crisp edges, a few tones).
Drawn here as shapes, not photos; colours taken from reference photos of the Pont du Gard's
surroundings (olive garrigue grass with dry golden blades, pale limestone dust, pale grey
limestone outcrops). Each layer tiles seamlessly. Run from the project root:
    python3 tools/texgen/vector_ground.py

Writes, per layer (ground_<name>):
  assets/images/terrain/ground_<name>_ah.png  albedo (RGB, sRGB) + height (A): what Terrain3D's
                                              height blend reads, so grass tufts stand above the
                                              earth and win where they overlap it
  assets/images/terrain/ground_<name>_nr.png  normal (RGB, OpenGL: +Y up) baked from the height's
                                              bevels + roughness (A)
  assets/images/terrain/src/ground_<name>.png a plain preview of the colours
Deterministic (fixed seeds).
"""

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw

OUT = "assets/images/terrain"
SIZE = 1024   # output px
SS = 2        # supersampling
C = SIZE * SS


class Layer:
    """A tile's colour and height, drawn shape by shape (later shapes on top), wrapping."""

    def __init__(self, base, height):
        self.col = Image.new("RGB", (C, C), tuple(int(v * 255) for v in base))
        self.h = Image.new("F", (C, C), height)
        self.dc = ImageDraw.Draw(self.col)
        self.dh = ImageDraw.Draw(self.h)

    def poly(self, pts, colour, height):
        rgb = tuple(int(max(0, min(1, v)) * 255) for v in colour)
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                q = [((x + ox) * C, (y + oy) * C) for x, y in pts]
                self.dc.polygon(q, fill=rgb)
                self.dh.polygon(q, fill=height)

    def line(self, pts, colour, height, width):
        rgb = tuple(int(max(0, min(1, v)) * 255) for v in colour)
        w = max(1, int(width * C))
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                q = [((x + ox) * C, (y + oy) * C) for x, y in pts]
                self.dc.line(q, fill=rgb, width=w, joint="curve")
                self.dh.line(q, fill=height, width=w, joint="curve")

    def save(self, name, rough, bevel_px=1.5, depth=6.0):
        col = np.asarray(self.col).astype(np.float32).reshape(SIZE, SS, SIZE, SS, 3).mean(axis=(1, 3)) / 255
        h = np.asarray(self.h, dtype=np.float32).reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3))
        hb = blur_wrap(h, bevel_px)
        dx = (np.roll(hb, -1, 1) - np.roll(hb, 1, 1)) * 0.5
        dy = (np.roll(hb, -1, 0) - np.roll(hb, 1, 0)) * 0.5
        n = np.dstack([-dx * depth, dy * depth, np.ones_like(h)]) # OpenGL: green = up the image
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        r = np.clip(rough + (0.5 - h) * 0.1, 0, 1)
        os.makedirs(f"{OUT}/src", exist_ok=True)
        save_png(np.dstack([col, h]), f"{OUT}/ground_{name}_ah.png")
        save_png(np.dstack([n * 0.5 + 0.5, r]), f"{OUT}/ground_{name}_nr.png")
        Image.fromarray((col * 255 + 0.5).astype(np.uint8)).save(f"{OUT}/src/ground_{name}.png")


def blur_wrap(a, sigma):
    r = max(1, int(round(sigma * 2)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = sum(np.roll(a, i, 0) * w for i, w in zip(range(-r, r + 1), k))
    return sum(np.roll(out, i, 1) * w for i, w in zip(range(-r, r + 1), k))


def save_png(arr, path):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path)
    imp = path + ".import"
    if not os.path.exists(imp):
        with open(imp, "w") as f:
            f.write(f'''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{path}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
''')
    print("  ", path)


def jitter(c, rng, amount):
    k = rng.uniform(-amount, amount)
    return tuple(v * (1 + k) for v in c)


def blob(cx, cy, r, rng, sides=9, squash=1.0, rough=0.25):
    """A rounded irregular shape (pebble, plate, flake)."""
    a0 = rng.uniform(0, math.tau)
    return [(cx + math.cos(a0 + k / sides * math.tau) * r * rng.uniform(1 - rough, 1 + rough),
             cy + math.sin(a0 + k / sides * math.tau) * r * squash * rng.uniform(1 - rough, 1 + rough)) for k in range(sides)]


def blade(x, y, ang, length, width):
    """A grass blade seen from above: pointed, widest a third of the way out."""
    ca, sa = math.cos(ang), math.sin(ang)
    pts = [(0, -width * 0.5), (length * 0.35, -width * 0.55), (length, 0), (length * 0.35, width * 0.55), (0, width * 0.5)]
    return [(x + px * ca - py * sa, y + px * sa + py * ca) for px, py in pts]


def grass():
    """Olive garrigue grass: tufts of blades in three greens, dry golden blades, a few flowers.
    The tile spans ~3.3 m: a blade is ~7-15 cm."""
    rng = random.Random(11)
    L = Layer((0.3, 0.36, 0.15), 0.15)
    tones = [((0.36, 0.44, 0.18), 0.45, 560, 0.026), ((0.46, 0.53, 0.22), 0.65, 500, 0.024),
             ((0.58, 0.61, 0.28), 0.85, 280, 0.02)]
    for colour, height, count, length in tones:
        for _ in range(count):
            cx, cy = rng.random(), rng.random()
            c = jitter(colour, rng, 0.07)
            # a tuft leans one way: its blades fan over part of a circle, not a star
            lean = rng.uniform(0, math.tau)
            spread = rng.uniform(1.4, 3.2)
            k_n = rng.randint(4, 8)
            for k in range(k_n):
                a = lean + (k / max(1, k_n - 1) - 0.5) * spread + rng.uniform(-0.25, 0.25)
                L.poly(blade(cx, cy, a, length * rng.uniform(0.6, 1.3), 0.0045 * rng.uniform(0.8, 1.3)), c, height + rng.uniform(-0.05, 0.05))
    for _ in range(170): # dry blades, singly
        c = jitter((0.72, 0.64, 0.34), rng, 0.08)
        L.poly(blade(rng.random(), rng.random(), rng.uniform(0, math.tau), rng.uniform(0.018, 0.032), 0.004), c, 0.9)
    for _ in range(14): # tiny flowers: five dots round a centre
        cx, cy = rng.random(), rng.random()
        petal = (0.95, 0.94, 0.86) if rng.random() < 0.6 else (0.95, 0.82, 0.3)
        for k in range(5):
            a = k / 5 * math.tau
            L.poly(blob(cx + math.cos(a) * 0.004, cy + math.sin(a) * 0.004, 0.0028, rng, 6, 1.0, 0.1), petal, 1.0)
        L.poly(blob(cx, cy, 0.0022, rng, 6, 1.0, 0.1), (0.9, 0.7, 0.2), 1.0)
    L.save("grass", 0.88)


def dirt():
    """Pale limestone dust: flat drifts of lighter and darker dust, pebbles, hairline cracks.
    The tile spans ~4.4 m: pebbles are ~3-9 cm."""
    rng = random.Random(23)
    L = Layer((0.7, 0.64, 0.53), 0.25)
    for _ in range(26): # dust drifts
        c = jitter((0.7, 0.64, 0.53), rng, 0.06)
        L.poly(blob(rng.random(), rng.random(), rng.uniform(0.05, 0.12), rng, 12, rng.uniform(0.5, 1.0), 0.35), c, 0.28)
    for _ in range(9): # cracks in the dry crust
        x, y = rng.random(), rng.random()
        a = rng.uniform(0, math.tau)
        pts = [(x, y)]
        for _ in range(rng.randint(4, 8)):
            a += rng.uniform(-0.7, 0.7)
            x += math.cos(a) * 0.02
            y += math.sin(a) * 0.02
            pts.append((x, y))
        L.line(pts, (0.52, 0.46, 0.37), 0.05, 0.0018)
    palette = [(0.82, 0.79, 0.72), (0.62, 0.57, 0.48), (0.75, 0.71, 0.63), (0.56, 0.53, 0.48), (0.86, 0.84, 0.8)]
    for _ in range(320):
        r = rng.uniform(0.004, 0.011) if rng.random() < 0.85 else rng.uniform(0.014, 0.022)
        c = jitter(palette[rng.randrange(len(palette))], rng, 0.05)
        L.poly(blob(rng.random(), rng.random(), r, rng, rng.randint(6, 9), rng.uniform(0.6, 1.0), 0.22), c, rng.uniform(0.6, 1.0))
    L.save("dirt", 0.95)


def rock():
    """Pale limestone outcrop seen from above (and stretched down cliff faces): broken plates in
    pale greys, dark crack lines between them, flakes split off some, a few lichen spots.
    The tile spans ~11 m."""
    rng = random.Random(37)
    L = Layer((0.36, 0.34, 0.31), 0.0)
    n = 7
    cell = 1.0 / n
    pt = [[((i + rng.uniform(-0.32, 0.32)) * cell, (j + rng.uniform(-0.32, 0.32)) * cell) for j in range(n)] for i in range(n)]
    corner = lambda i, j: (pt[i % n][j % n][0] + (i // n), pt[i % n][j % n][1] + (j // n))
    palette = [(0.74, 0.72, 0.67), (0.66, 0.64, 0.6), (0.8, 0.78, 0.73), (0.6, 0.58, 0.55), (0.71, 0.68, 0.62)]
    for i in range(n):
        for j in range(n):
            q = [corner(i, j), corner(i + 1, j), corner(i + 1, j + 1), corner(i, j + 1)]
            parts = [q]
            if rng.random() < 0.45:
                parts = [[q[0], q[1], q[2]], [q[0], q[2], q[3]]] if rng.random() < 0.5 else [[q[0], q[1], q[3]], [q[1], q[2], q[3]]]
            for part in parts:
                cx = sum(p[0] for p in part) / len(part)
                cy = sum(p[1] for p in part) / len(part)
                shrunk = []
                for x, y in part: # pull in toward the middle: the crack between plates
                    dx, dy = x - cx, y - cy
                    d = math.hypot(dx, dy) or 1
                    shrunk.append((x - dx / d * 0.006, y - dy / d * 0.006))
                wob = []
                for k, a in enumerate(shrunk): # chipped, not ruled edges
                    b = shrunk[(k + 1) % len(shrunk)]
                    for s in range(3):
                        f = s / 3
                        wob.append((a[0] + (b[0] - a[0]) * f + (rng.uniform(-0.006, 0.006) if s else 0),
                                    a[1] + (b[1] - a[1]) * f + (rng.uniform(-0.006, 0.006) if s else 0)))
                c = jitter(palette[rng.randrange(len(palette))], rng, 0.04)
                h = rng.uniform(0.7, 1.0)
                L.poly(wob, c, h)
                if rng.random() < 0.5: # a flake split off its top: paler, higher
                    L.poly(blob(cx + rng.uniform(-0.02, 0.02), cy + rng.uniform(-0.02, 0.02), cell * rng.uniform(0.12, 0.25), rng, 7, rng.uniform(0.5, 1), 0.3),
                           jitter(c, rng, 0.03) if rng.random() < 0.5 else tuple(min(1, v * 1.1) for v in c), min(1.0, h + 0.08))
                if rng.random() < 0.25: # a crack across it
                    a = rng.uniform(0, math.tau)
                    L.line([(cx - math.cos(a) * cell * 0.3, cy - math.sin(a) * cell * 0.3), (cx + rng.uniform(-0.01, 0.01), cy + rng.uniform(-0.01, 0.01)),
                            (cx + math.cos(a) * cell * 0.35, cy + math.sin(a) * cell * 0.35)], (0.4, 0.38, 0.35), 0.1, 0.0016)
    for _ in range(22): # lichen
        c = (0.78, 0.7, 0.36) if rng.random() < 0.6 else (0.62, 0.66, 0.5)
        L.poly(blob(rng.random(), rng.random(), rng.uniform(0.004, 0.012), rng, 8, 1.0, 0.35), c, 1.0)
    L.save("rock", 0.86, bevel_px=2.0, depth=4.0)


if __name__ == "__main__":
    grass()
    dirt()
    rock()
