#!/usr/bin/env python3
"""
Vector-art ground layers for Terrain3D (the M6 look: flat shapes, crisp edges, a few tones).
Drawn here as shapes, not photos; colours taken from reference photos of the Pont du Gard's
surroundings (olive garrigue grass with dry golden blades, pale limestone dust, pale
limestone outcrops in beds). Each layer tiles seamlessly. Run from the project root:
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
    """Pale limestone in beds (the cliffs, the canyon, the mesa: terrain_art.gdshader lays it on
    steep ground sideways, so the beds run level): horizontal beds of uneven thickness, each
    snapped into slabs at jagged breaks, beds toned as a set (rock is laid down in layers), dark
    seams between them, now and then a hairline crack along a slab, a flake gone, lichen.
    The tile spans ~11 m: beds are ~0.4-1.4 m. (Broken plates seen from above read as spikes
    once stretched down a cliff.)"""
    rng = random.Random(37)
    L = Layer((0.4, 0.36, 0.31), 0.0)
    palette = [(0.8, 0.75, 0.66), (0.74, 0.69, 0.6), (0.84, 0.8, 0.72), (0.7, 0.65, 0.57), (0.77, 0.72, 0.62)]
    y = 0.0
    while y < 1.0 - 1e-6:
        t = min(rng.uniform(0.035, 0.12), 1.0 - y)
        if 1.0 - (y + t) < 0.03:
            t = 1.0 - y
        bed = palette[rng.randrange(len(palette))]
        x = rng.random()
        end = x + 1.0
        while x < end - 1e-6:
            w = min(rng.uniform(0.2, 0.65), end - x) # beds run long between breaks
            if end - (x + w) < 0.12:
                w = end - x
            j = 0.0028
            x0, x1, y0, y1 = x + j, x + w - j, y + j, y + t - j
            jag = lambda: rng.uniform(-0.18, 0.18) * t
            pts = [(x0 + jag(), y0)]
            for f in (0.33, 0.66):
                pts.append((x0 + (x1 - x0) * f, y0 + rng.uniform(-0.06, 0.06) * t))
            pts += [(x1 + jag(), y0), (x1 + jag(), y0 + (y1 - y0) * 0.5), (x1 + jag(), y1)]
            for f in (0.66, 0.33):
                pts.append((x0 + (x1 - x0) * f, y1 + rng.uniform(-0.06, 0.06) * t))
            pts += [(x0 + jag(), y1), (x0 + jag(), y0 + (y1 - y0) * 0.5)]
            c = jitter(bed, rng, 0.05)
            h = rng.uniform(0.75, 1.0)
            L.poly(pts, c, h)
            if rng.random() < 0.35: # a flake gone from the slab's face: a paler, lower patch
                fx, fy = x0 + (x1 - x0) * rng.uniform(0.2, 0.8), y0 + (y1 - y0) * rng.uniform(0.3, 0.7)
                L.poly(blob(fx, fy, min(w, t) * rng.uniform(0.15, 0.3), rng, 7, rng.uniform(0.5, 0.9), 0.3),
                       tuple(min(1, v * 1.07) for v in c), h - 0.12)
            if rng.random() < 0.2: # a hairline crack along it
                cy = y0 + (y1 - y0) * rng.uniform(0.3, 0.7)
                L.line([(x0 + (x1 - x0) * f, cy + rng.uniform(-0.1, 0.1) * t) for f in (0.08, 0.4, 0.7, 0.92)], (0.45, 0.4, 0.34), 0.1, 0.0015)
            x += w
        y += t
    for _ in range(26): # lichen
        c = (0.8, 0.7, 0.34) if rng.random() < 0.6 else (0.62, 0.66, 0.5)
        L.poly(blob(rng.random(), rng.random(), rng.uniform(0.004, 0.011), rng, 8, 1.0, 0.35), c, 1.0)
    L.save("rock", 0.86, bevel_px=2.0, depth=4.0)


if __name__ == "__main__":
    grass()
    dirt()
    rock()
