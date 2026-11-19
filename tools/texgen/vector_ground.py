#!/usr/bin/env python3
"""
Vector-art ground layers for Terrain3D (the M6 look: flat shapes, crisp edges, a few tones).
Drawn here as shapes, not photos; colours taken from reference photos of the Pont du Gard's
surroundings (olive garrigue grass with dry golden blades, pale limestone dust, pale
limestone outcrops: broken rock). Each layer tiles seamlessly. Run from the project root:
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


def clip(poly, a, b):
    """Sutherland-Hodgman: the part of poly on the side of the bisector of a and b nearer a."""
    mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
    nx, ny = b[0] - a[0], b[1] - a[1]
    inside = lambda p: (p[0] - mx) * nx + (p[1] - my) * ny <= 0.0
    out = []
    for i, p in enumerate(poly):
        q = poly[(i + 1) % len(poly)]
        pi, qi = inside(p), inside(q)
        if pi:
            out.append(p)
        if pi != qi:
            dp = (p[0] - mx) * nx + (p[1] - my) * ny
            dq = (q[0] - mx) * nx + (q[1] - my) * ny
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def voronoi(sites, reach=0.35):
    """Each site's cell in a tiling unit square (neighbours across the edges count)."""
    cells = []
    for i, a in enumerate(sites):
        poly = [(a[0] - reach, a[1] - reach), (a[0] + reach, a[1] - reach), (a[0] + reach, a[1] + reach), (a[0] - reach, a[1] + reach)]
        for j, b in enumerate(sites):
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    if i == j and ox == 0 and oy == 0:
                        continue
                    bb = (b[0] + ox, b[1] + oy)
                    if abs(bb[0] - a[0]) > reach * 2 or abs(bb[1] - a[1]) > reach * 2:
                        continue
                    poly = clip(poly, a, bb)
                    if len(poly) < 3:
                        break
        cells.append(poly)
    return cells


def rock(name="rock", tones=None, moss=0, lichen=14, seed=37):
    """Uneven broken rock (cliffs, the canyon, the mesa, the rim: terrain_art.gdshader lays it on
    steep ground side-on). One continuous mass cut into irregular facets of every size: most facet
    edges are just where two planes meet (a change of tone, a hairline), a few are deep cracks of
    varying width, and some cracks wander across several facets. No outline round every piece:
    that read as crazy paving, and courses or beds read as brickwork. The tile spans ~11 m."""
    rng = random.Random(seed)
    tones = tones or [(0.84, 0.8, 0.72), (0.77, 0.73, 0.64), (0.7, 0.66, 0.57), (0.62, 0.58, 0.5), (0.8, 0.76, 0.67)]
    L = Layer(tones[2], 0.75)
    sites = []
    while len(sites) < 40:
        p = (rng.random(), rng.random())
        if all(min(abs(p[0] - q[0]), 1 - abs(p[0] - q[0])) ** 2 + min(abs(p[1] - q[1]), 1 - abs(p[1] - q[1])) ** 2 > 0.1 ** 2 for q in sites):
            sites.append(p)
    for _ in range(55):
        sites.append((rng.random(), rng.random()))
    # facet tones: planes turned toward the light, side-on, away (low-poly rock)
    cells = voronoi(sites)
    for poly in cells:
        if len(poly) < 3:
            continue
        c = jitter(tones[rng.randrange(len(tones))], rng, 0.035)
        L.poly(poly, c, rng.uniform(0.7, 1.0))
        L.line(poly + poly[:1], tuple(v * 0.88 for v in c), 0.6, 0.0012) # the edge where planes meet
    crack_col = (0.3, 0.26, 0.21)
    for poly in cells: # a few of the facet edges open into cracks
        for k in range(len(poly)):
            if rng.random() < 0.22:
                p0, p1 = poly[k], poly[(k + 1) % len(poly)]
                mid = ((p0[0] + p1[0]) * 0.5 + rng.uniform(-0.004, 0.004), (p0[1] + p1[1]) * 0.5 + rng.uniform(-0.004, 0.004))
                L.line([p0, mid, p1], crack_col, 0.0, rng.uniform(0.002, 0.006))
    for _ in range(9): # long cracks wandering across facets, thinning out
        x, y = rng.random(), rng.random()
        a = rng.uniform(0, math.tau)
        w = rng.uniform(0.004, 0.007)
        for _ in range(rng.randint(5, 10)):
            a += rng.uniform(-0.6, 0.6)
            nx, ny = x + math.cos(a) * 0.03, y + math.sin(a) * 0.03
            L.line([(x, y), (nx, ny)], crack_col, 0.0, w)
            x, y, w = nx, ny, max(0.0015, w * 0.85)
    for _ in range(moss): # moss in the hollows: soft clumps of green, a few big
        cx, cy = rng.random(), rng.random()
        for _ in range(rng.randint(3, 8)):
            g = jitter((0.3, 0.44, 0.18) if rng.random() < 0.6 else (0.38, 0.52, 0.22), rng, 0.08)
            L.poly(blob(cx + rng.uniform(-0.02, 0.02), cy + rng.uniform(-0.02, 0.02), rng.uniform(0.006, 0.02), rng, 9, rng.uniform(0.6, 1.0), 0.3), g, 1.0)
    for _ in range(lichen): # lichen, small
        L.poly(blob(rng.random(), rng.random(), rng.uniform(0.003, 0.008), rng, 8, 1.0, 0.35),
               (0.8, 0.7, 0.34) if rng.random() < 0.6 else (0.62, 0.66, 0.5), 1.0)
    L.save(name, 0.86, bevel_px=2.0, depth=4.0)


def leaf(cx, cy, ang, length, width):
    """A fallen leaf from above: pointed both ends, widest just below the middle."""
    ca, sa = math.cos(ang), math.sin(ang)
    pts = []
    for k in range(10):
        t = k / 10 * math.tau
        lx = math.cos(t) * length * 0.5
        ly = math.sin(t) * width * 0.5 * (abs(math.cos(t * 0.5)) ** 0.25) * (1.0 if math.cos(t) < 0.3 else 0.85)
        pts.append((cx + lx * ca - ly * sa, cy + lx * sa + ly * ca))
    return pts


def jungle_floor():
    """The forest floor: fallen leaves in browns, ochres and olive (each with its midrib), lying
    over one another, twigs, dark soil showing only in gaps. The tile spans ~4 m: a leaf is
    ~12-26 cm (broad jungle leaves)."""
    rng = random.Random(51)
    L = Layer((0.22, 0.17, 0.12), 0.2)
    cols = [(0.45, 0.32, 0.18), (0.55, 0.4, 0.2), (0.4, 0.37, 0.19), (0.32, 0.23, 0.13), (0.6, 0.47, 0.25), (0.36, 0.3, 0.16)]
    for _ in range(12): # twigs, under the leaves
        x, y = rng.random(), rng.random()
        a = rng.uniform(0, math.tau)
        pts = [(x, y)]
        for _ in range(3):
            a += rng.uniform(-0.4, 0.4)
            x += math.cos(a) * 0.03
            y += math.sin(a) * 0.03
            pts.append((x, y))
        L.line(pts, (0.24, 0.17, 0.1), 0.45, rng.uniform(0.002, 0.004))
    n = 1500
    for i in range(n): # (dense: the soil only shows in gaps)
        c = jitter(cols[rng.randrange(len(cols))], rng, 0.08)
        cx, cy = rng.random(), rng.random()
        ang = rng.uniform(0, math.tau)
        ln = rng.uniform(0.03, 0.065)
        h = 0.5 + 0.45 * i / n # later leaves lie on top
        L.poly(leaf(cx, cy, ang, ln, ln * rng.uniform(0.38, 0.55)), c, h)
        L.line([(cx - math.cos(ang) * ln * 0.45, cy - math.sin(ang) * ln * 0.45), (cx + math.cos(ang) * ln * 0.45, cy + math.sin(ang) * ln * 0.45)],
               tuple(v * 0.75 for v in c), h, 0.0012)
    L.save("jfloor", 0.9)


def jungle_moss():
    """Moss: soft round clumps in three greens, packed, the odd clover leaf. Tile ~4 m."""
    rng = random.Random(53)
    L = Layer((0.18, 0.26, 0.11), 0.25)
    greens = [((0.26, 0.38, 0.15), 0.55), ((0.33, 0.47, 0.18), 0.7), ((0.42, 0.56, 0.22), 0.85)]
    for col, h in greens:
        for _ in range(420):
            L.poly(blob(rng.random(), rng.random(), rng.uniform(0.006, 0.018), rng, 9, rng.uniform(0.7, 1.0), 0.3), jitter(col, rng, 0.06), h + rng.uniform(-0.05, 0.05))
    for _ in range(40): # clover: three round leaves
        cx, cy = rng.random(), rng.random()
        a0 = rng.uniform(0, math.tau)
        for k in range(3):
            a = a0 + k * math.tau / 3
            L.poly(blob(cx + math.cos(a) * 0.006, cy + math.sin(a) * 0.006, 0.0055, rng, 8, 1.0, 0.1), (0.36, 0.55, 0.22), 1.0)
    L.save("jmoss", 0.85)


def jungle_mud():
    """Wet mud (river banks, the pools' shores): dark, wetter patches darker still, rounded
    pebbles, a few puddle sheens. Tile ~4.4 m."""
    rng = random.Random(57)
    L = Layer((0.27, 0.22, 0.17), 0.3)
    for _ in range(30):
        L.poly(blob(rng.random(), rng.random(), rng.uniform(0.04, 0.1), rng, 12, rng.uniform(0.5, 1.0), 0.35), jitter((0.2, 0.17, 0.13), rng, 0.05), 0.2)
    pal = [(0.45, 0.42, 0.37), (0.35, 0.32, 0.28), (0.52, 0.49, 0.44), (0.3, 0.27, 0.23)]
    for _ in range(260):
        r = rng.uniform(0.004, 0.014)
        L.poly(blob(rng.random(), rng.random(), r, rng, 8, rng.uniform(0.6, 1.0), 0.2), jitter(pal[rng.randrange(len(pal))], rng, 0.05), rng.uniform(0.6, 1.0))
    L.save("jmud", 0.55)


def jungle():
    rock("jrock", [(0.55, 0.56, 0.49), (0.48, 0.5, 0.43), (0.6, 0.61, 0.54), (0.42, 0.44, 0.38), (0.52, 0.53, 0.46)], moss=40, lichen=8, seed=61)
    jungle_floor()
    jungle_moss()
    jungle_mud()


if __name__ == "__main__":
    grass()
    dirt()
    rock()
    jungle()
