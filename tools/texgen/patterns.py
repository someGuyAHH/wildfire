#!/usr/bin/env python3
"""
Vector-style surface patterns for the world shader (assets/gdshaders/world_vector.gdshader).

Every pattern is a set of flat shapes (blocks, slabs, plates, inlays) defined here in tile
coordinates (0..1, the tile repeats seamlessly). Each one is written twice:
  - assets/images/patterns/src/<name>.svg  the shapes as SVG, to look at or edit by eye
  - assets/images/patterns/<name>.png      a packed data map the shader reads (linear, not colour):
        R  height: 0 in joints, ramping up over the bevel, 1 on faces (rivets/inlays can sit higher)
        G  tone: a flat grey per block (the shader spreads its colour by this), 0.5 = no change
        B  accent: 1 where an inlay / crack / trim is (the shader colours and may light it)
        A  0 where a block that wrapped round the tile's right edge shows on its left edge, so the
           shader can give it the same per-block variation as the rest of it (1 everywhere else)
  - assets/images/patterns/<name>_slope.png  the height's slope, baked so the shader needn't take
        four extra samples per pixel: R = 0.5 + dh/du / 3, G = 0.5 + dh/dv / 3, each the height's
        change across 3 texels (so -1.5..1.5 fits; tiling: neighbours wrap round the edges)
Deterministic (fixed seeds). Run from the project root:
    python3 tools/texgen/patterns.py
"""

import os
import random

import numpy as np
from PIL import Image, ImageDraw

OUT = "assets/images/patterns"
SIZE = 1024          # output px
SS = 2               # supersampling for the shapes
PAD = 96             # wrap padding (output-res px * SS) so blurs and shapes tile seamlessly


class Pattern:
    """Shapes on one tile. Coordinates in tile units (0..1); y down, like an image."""

    def __init__(self, name: str, bevel: float, size: int = 1024):
        self.name = name
        self.size = size     # output px
        self.bevel = bevel   # bevel width, in tile units
        self.grooves = []    # (polyline, width, depth 0..1): cracks cut into faces (height only)
        self.faces = []      # (polygon, tone 0..1, height 0..1)
        self.raised = []     # (polygon or circle, height): sit on top of faces, no bevel blur
        self.accents = []    # (kind, data, width): "line" polyline / "poly" polygon / "ring" circle

    def face(self, poly, tone, height=1.0, outline=0.0):
        """A flat shape. `outline` (tile units) rings it with a joint as it's drawn, so a face laid
        over others keeps its own edge (overlapping leaves)."""
        self.faces.append((poly, tone, height, outline))

    def rect(self, x0, y0, x1, y1, tone, cut=0.0, height=1.0):
        """A block, corners cut by `cut` (a chamfer reads as vector art more than a plain box)."""
        if cut <= 0.0:
            self.face([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], tone, height)
            return
        self.face([(x0 + cut, y0), (x1 - cut, y0), (x1, y0 + cut), (x1, y1 - cut),
                   (x1 - cut, y1), (x0 + cut, y1), (x0, y1 - cut), (x0, y0 + cut)], tone, height)


# ---- rasterizing ------------------------------------------------------------------------------

def _canvas():
    s = SIZE * SS + PAD * 2
    return Image.new("F", (s, s), 0.0)


def _xy(p, ox=0.0, oy=0.0):
    s = SIZE * SS
    return ((p[0] + ox) * s + PAD, (p[1] + oy) * s + PAD)


def _wrapped(draw_one):
    # draw a shape at every wrap offset so anything crossing the tile edge shows up on the far side
    for ox in (-1.0, 0.0, 1.0):
        for oy in (-1.0, 0.0, 1.0):
            draw_one(ox, oy)


def _fill_polys(items, value_of, outlines=False):
    img = _canvas()
    d = ImageDraw.Draw(img)
    for it in items:
        poly = it[0]
        v = value_of(it)
        w = int(it[3] * SIZE * SS) if outlines and len(it) > 3 and it[3] > 0.0 else 0
        _wrapped(lambda ox, oy: d.polygon([_xy(p, ox, oy) for p in poly], fill=v))
        if w > 0: # (PIL's polygon outline does nothing on float images: a closed line instead)
            _wrapped(lambda ox, oy: d.line([_xy(p, ox, oy) for p in poly + poly[:1]], fill=0.0, width=w, joint="curve"))
    return img


def _crop(img):
    a = np.asarray(img, dtype=np.float32)[PAD:-PAD, PAD:-PAD]
    # back to output size (box filter over the supersamples = anti-aliasing)
    return a.reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3))


def _box(a, r, axis):
    # running mean over 2r+1 samples along axis (edges clamp: the padding is wrapped content)
    if r < 1:
        return a
    a = np.moveaxis(a, axis, 0)
    padded = np.concatenate([np.repeat(a[:1], r + 1, 0), a, np.repeat(a[-1:], r, 0)], 0)
    c = np.cumsum(padded, 0, dtype=np.float64)
    out = (c[2 * r + 1:] - c[:-2 * r - 1]) / (2 * r + 1)
    return np.moveaxis(out.astype(np.float32), 0, axis)


def _blur(a, sigma):
    # three box passes per axis ~ a gaussian of this sigma
    r = int(round(np.sqrt(12.0 * sigma * sigma / 3.0 + 1.0) - 1.0) / 2.0)
    for _ in range(3):
        a = _box(_box(a, r, 0), r, 1)
    return a


def render(pat: Pattern):
    global SIZE
    SIZE = pat.size
    # height: faces at their height, joints 0; blurred so faces ramp up over the bevel width
    faces = _fill_polys(pat.faces, lambda it: it[2], outlines=True)
    blur = pat.bevel * SIZE * SS * 0.5
    h = _blur(np.asarray(faces, dtype=np.float32), blur)
    hard = np.asarray(faces, dtype=np.float32)
    # levels: a blurred edge's middle becomes the joint line, the plateau stays flat
    h = np.clip((h - 0.18) / 0.62, 0.0, 1.0) * np.where(hard > 0.0, hard, 1.0)
    h = Image.fromarray(h)
    d = ImageDraw.Draw(h)
    for shape, height in pat.raised:
        if shape[0] == "circle":
            _, c, r = shape
            _wrapped(lambda ox, oy: d.ellipse([_xy((c[0] - r, c[1] - r), ox, oy), _xy((c[0] + r, c[1] + r), ox, oy)], fill=height))
        else:
            _wrapped(lambda ox, oy: d.polygon([_xy(p, ox, oy) for p in shape], fill=height))
    for line, width, depth in pat.grooves:
        _wrapped(lambda ox, oy: d.line([_xy(q, ox, oy) for q in line], fill=1.0 - depth, width=max(1, int(width * SIZE * SS)), joint="curve"))
    tone = _fill_polys(pat.faces, lambda it: it[1])
    # wrap flag: faces drawn one tile to the left (they started near the right edge) get 0
    wrap = _canvas()
    wd = ImageDraw.Draw(wrap)
    for poly, *_ in pat.faces:
        for ox in (0.0, -1.0):
            for oy in (-1.0, 0.0, 1.0):
                wd.polygon([_xy(q, ox, oy) for q in poly], fill=0.0 if ox < 0.0 else 1.0)
    wrap_a = np.where(_crop(wrap) > 0.5, 1.0, 0.0)
    acc = _canvas()
    d = ImageDraw.Draw(acc)
    s = SIZE * SS
    for kind, data, width in pat.accents:
        w = max(1, int(width * s))
        if kind == "line":
            _wrapped(lambda ox, oy: d.line([_xy(p, ox, oy) for p in data], fill=1.0, width=w, joint="curve"))
        elif kind == "poly":
            _wrapped(lambda ox, oy: d.polygon([_xy(p, ox, oy) for p in data], fill=1.0))
        elif kind == "ring":
            c, r = data
            _wrapped(lambda ox, oy: d.ellipse([_xy((c[0] - r, c[1] - r), ox, oy), _xy((c[0] + r, c[1] + r), ox, oy)], outline=1.0, width=w))
    hc = _crop(h)
    rgba = np.stack([hc, _crop(tone), _crop(acc), np.where(hc > 0.02, wrap_a, 1.0)], axis=-1)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(rgba, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGBA").save(f"{OUT}/{pat.name}.png")
    # slope over 3 texels (the shader used to sample +-1.5 texels), from wrapped neighbours
    du = (np.roll(hc, -1, axis=1) - np.roll(hc, 1, axis=1)) * 1.5
    dv = (np.roll(hc, -1, axis=0) - np.roll(hc, 1, axis=0)) * 1.5
    slope = np.stack([0.5 + du / 3.0, 0.5 + dv / 3.0, np.full_like(hc, 0.5)], axis=-1)
    Image.fromarray((np.clip(slope, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGB").save(f"{OUT}/{pat.name}_slope.png")
    _write_import(f"{pat.name}_slope")
    _write_svg(pat)
    _write_import(pat.name)


def _write_svg(pat: Pattern):
    os.makedirs(f"{OUT}/src", exist_ok=True)
    s = 1000
    pts = lambda poly: " ".join(f"{x * s:.1f},{y * s:.1f}" for x, y in poly)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}" width="{s}" height="{s}">',
           f'<rect width="{s}" height="{s}" fill="#1a1414"/>']
    for poly, tone, *_ in pat.faces:
        g = int(80 + tone * 120)
        out.append(f'<polygon points="{pts(poly)}" fill="rgb({g},{g},{g})"/>')
    for shape, _ in pat.raised:
        if shape[0] == "circle":
            out.append(f'<circle cx="{shape[1][0] * s:.1f}" cy="{shape[1][1] * s:.1f}" r="{shape[2] * s:.1f}" fill="#ddd"/>')
        else:
            out.append(f'<polygon points="{pts(shape)}" fill="#ddd"/>')
    for kind, data, width in pat.accents:
        if kind == "line":
            out.append(f'<polyline points="{pts(data)}" fill="none" stroke="#ff7a1a" stroke-width="{width * s:.1f}"/>')
        elif kind == "poly":
            out.append(f'<polygon points="{pts(data)}" fill="#ff7a1a"/>')
        else:
            c, r = data
            out.append(f'<circle cx="{c[0] * s:.1f}" cy="{c[1] * s:.1f}" r="{r * s:.1f}" fill="none" stroke="#ff7a1a" stroke-width="{width * s:.1f}"/>')
    out.append("</svg>")
    with open(f"{OUT}/src/{pat.name}.svg", "w") as f:
        f.write("\n".join(out) + "\n")


def _write_import(name: str):
    # data, not colour: lossless with mipmaps (Godot keeps these params on import)
    path = f"{OUT}/{name}.png.import"
    if os.path.exists(path):
        return
    with open(path, "w") as f:
        f.write(f'''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://{OUT}/{name}.png"

[params]

compress/mode=0
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


# ---- the patterns -----------------------------------------------------------------------------

def _unit(v):
    d = (v[0] * v[0] + v[1] * v[1]) ** 0.5 or 1.0
    return (v[0] / d, v[1] / d)


def _rough_edge(a, b, rng, rough, steps, bite=None):
    """Points from a toward b (b itself left out): a hand-dressed edge, never ruled straight.
    bite = (t, length, depth): a piece knocked out of the edge there (inward is to the left of a->b
    in the y-down tile, which is the block's inside for a clockwise outline)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = _unit((dy, -dx)) # inward
    out = [a]
    for k in range(1, steps):
        f = k / steps
        o = rng.uniform(-rough, rough)
        if bite and abs(f - bite[0]) < bite[1] * 0.5:
            u = 1.0 - abs(f - bite[0]) / (bite[1] * 0.5)
            o += bite[2] * min(1.0, u * 1.8) * rng.uniform(0.75, 1.15)
        out.append((a[0] + dx * f + n[0] * o, a[1] + dy * f + n[1] * o))
    return out


def worn_block(p, rng, x0, y0, x1, y1, tone, course, wear=1.0):
    """A cut stone that has had a life: its outline hand-dressed (no straight edge), some corners
    broken off and some edges bitten into, showing a lower, rougher broken level underneath (or
    gone right down to the joint); shallow pits flaked off its face; now and then a crack.
    `course` = the block's height in tile units (sizes everything); wear scales how much happens."""
    rough = course * 0.022
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)] # clockwise on screen (y down)
    centre = ((x0 + x1) * 0.5, (y0 + y1) * 0.5)
    chips = [rng.uniform(0.15, 0.42) * course if rng.random() < 0.55 * wear else rng.uniform(0.0, 0.035) * course for _ in range(4)]
    deep = [c > 0.1 * course and rng.random() < 0.4 for c in chips] # broken right down: joint shows
    # the broken level: the same stone a little lower and paler, its corners only nicked (or, where
    # a deep break is, cut away too)
    low = []
    for i, c in enumerate(corners):
        cut = chips[i] * rng.uniform(0.75, 0.95) if deep[i] else rng.uniform(0.01, 0.04) * course
        dp = _unit((corners[i - 1][0] - c[0], corners[i - 1][1] - c[1]))
        dn = _unit((corners[(i + 1) % 4][0] - c[0], corners[(i + 1) % 4][1] - c[1]))
        a = (c[0] + dp[0] * cut, c[1] + dp[1] * cut)
        b = (c[0] + dn[0] * cut, c[1] + dn[1] * cut)
        low.append(a)
        low.extend(_rough_edge(b, corners[(i + 1) % 4], rng, rough * 0.6, 6)[:1])
    p.face(_wobbly(low, rng, rough * 0.5, 3), tone, rng.uniform(0.5, 0.62))
    # the intact top
    top = []
    pts_b = []
    for i, c in enumerate(corners):
        size = chips[i] * rng.uniform(0.85, 1.15)
        dp = _unit((corners[i - 1][0] - c[0], corners[i - 1][1] - c[1]))
        dn = _unit((corners[(i + 1) % 4][0] - c[0], corners[(i + 1) % 4][1] - c[1]))
        a = (c[0] + dp[0] * size * rng.uniform(0.6, 1.4), c[1] + dp[1] * size * rng.uniform(0.6, 1.4))
        b = (c[0] + dn[0] * size * rng.uniform(0.6, 1.4), c[1] + dn[1] * size * rng.uniform(0.6, 1.4))
        inward = _unit((dp[0] + dn[0], dp[1] + dn[1]))
        chip = [a]
        if size > 0.08 * course: # a break, not a chamfer: jagged, a step or two in it
            for k in range(1, rng.randint(3, 5)):
                f = k / 4.0
                push = rng.uniform(-0.18, 0.32) * size
                chip.append((a[0] + (b[0] - a[0]) * f + inward[0] * push, a[1] + (b[1] - a[1]) * f + inward[1] * push))
        chip.append(b)
        top.append(chip)
        pts_b.append(b)
    outline = []
    for i in range(4):
        outline.extend(top[i])
        a_next = top[(i + 1) % 4][0]
        length = ((a_next[0] - pts_b[i][0]) ** 2 + (a_next[1] - pts_b[i][1]) ** 2) ** 0.5
        bite = None
        if rng.random() < 0.4 * wear and length > course * 0.5:
            bite = (rng.uniform(0.25, 0.75), rng.uniform(0.12, 0.35) * course / length * 2.0, rng.uniform(0.05, 0.14) * course)
        outline.extend(_rough_edge(pts_b[i], a_next, rng, rough, max(4, int(length / (course * 0.12))), bite)[1:])
    p.face(outline, tone, 1.0)
    # flaked-off pits: shallow irregular dips in the face
    for _ in range(rng.choice([0, 1, 1, 2, 3]) if wear > 0.0 else 0):
        r = rng.uniform(0.05, 0.14) * course
        cx = rng.uniform(x0 + r * 2, x1 - r * 2) if x1 - x0 > r * 4 else centre[0]
        cy = rng.uniform(y0 + r * 2, y1 - r * 2) if y1 - y0 > r * 4 else centre[1]
        blob = []
        sides = rng.randint(6, 9)
        for k in range(sides):
            ang = k / sides * 6.2832
            rr = r * rng.uniform(0.55, 1.3)
            blob.append((cx + np.cos(ang) * rr * rng.uniform(1.0, 1.8), cy + np.sin(ang) * rr))
        p.raised.append((blob, rng.uniform(0.38, 0.5)))
    # pores and tiny knocks all over
    for _ in range(int(rng.uniform(4, 14) * wear)):
        r = rng.uniform(0.008, 0.022) * course
        if x1 - x0 < r * 6 or y1 - y0 < r * 6: break
        c = (rng.uniform(x0 + r * 3, x1 - r * 3), rng.uniform(y0 + r * 3, y1 - r * 3))
        p.raised.append((("circle", c, r), rng.uniform(0.4, 0.55)))
    # a crack: from one edge, wandering across, sometimes forking
    if rng.random() < 0.3 * wear:
        horizontal = (x1 - x0) > (y1 - y0) * 1.4 and rng.random() < 0.7
        if horizontal: # across the course, top to bottom
            x = rng.uniform(x0 + (x1 - x0) * 0.2, x1 - (x1 - x0) * 0.2)
            start, step = (x, y0), (0.0, (y1 - y0))
        else:
            y = rng.uniform(y0 + (y1 - y0) * 0.2, y1 - (y1 - y0) * 0.2)
            start, step = (x0, y), ((x1 - x0), 0.0)
        reach = rng.uniform(0.45, 1.0)
        line = [start]
        segs = rng.randint(7, 11)
        for k in range(1, segs + 1):
            f = k / segs * reach
            j = rng.uniform(-0.07, 0.07) * course
            line.append((start[0] + step[0] * f + (j if horizontal else 0.0), start[1] + step[1] * f + (0.0 if horizontal else j)))
        p.grooves.append((line, 0.0016, 0.95))
        if rng.random() < 0.5: # a fork off it, thinner
            k = rng.randint(1, len(line) - 2)
            fx, fy = line[k]
            fork = [(fx, fy)]
            for q in range(rng.randint(2, 3)):
                fx += rng.uniform(-0.12, 0.12) * course + (0.06 * course if not horizontal else 0.0)
                fy += rng.uniform(-0.12, 0.12) * course + (0.06 * course if horizontal else 0.0)
                fork.append((fx, fy))
            p.grooves.append((fork, 0.0011, 0.93))


def ashlar(name, rows, unit, seed, bevel=0.006, joint=0.004, size=2048, wear=1.0):
    """Cut-stone courses in running bond: walls, columns, blocks. Every stone worn its own way
    (worn_block). unit: a typical block's width in tile units."""
    rng = random.Random(seed)
    p = Pattern(name, bevel, size)
    rh = 1.0 / rows
    for r in range(rows):
        x = rng.random()
        end = x + 1.0
        while x < end - 1e-6:
            w = min(rng.uniform(0.9, 2.2) * unit, end - x)
            if end - (x + w) < unit * 0.7:
                w = end - x
            worn_block(p, rng, x + joint * rng.uniform(0.8, 1.5), r * rh + joint * rng.uniform(0.8, 1.5),
                       x + w - joint * rng.uniform(0.8, 1.5), (r + 1) * rh - joint * rng.uniform(0.8, 1.5),
                       rng.uniform(0.2, 0.8), rh, wear)
            x += w
    return p


def brick(name, rows, per_row, seed, bevel=0.0035, joint=0.0022, size=2048):
    """Worn bricks in running bond (each row half a brick over), laid by hand: corners knocked off
    at random, edges a little out of true, some bricks narrower, sunk or chipped, a few cracked.
    A big tile (rows x per_row distinct bricks) so the repeat is hard to spot."""
    rng = random.Random(seed)
    p = Pattern(name, bevel, size)
    rh, bw = 1.0 / rows, 1.0 / per_row
    j = lambda: rng.uniform(-0.25, 0.25) * joint # a corner's own wobble
    for r in range(rows):
        off = bw * 0.5 * (r % 2) + rng.uniform(-0.12, 0.12) * bw # rows aren't laid perfectly
        for k in range(per_row):
            x0 = off + k * bw + joint * rng.uniform(0.8, 1.6)
            x1 = off + (k + 1) * bw - joint * rng.uniform(0.8, 1.6)
            y0 = r * rh + joint * rng.uniform(0.8, 1.5)
            y1 = (r + 1) * rh - joint * rng.uniform(0.8, 1.5)
            # every corner cut its own amount; now and then one knocked right off
            c = [rng.uniform(0.0, 0.18) * rh for _ in range(4)]
            if rng.random() < 0.18:
                c[rng.randrange(4)] = rng.uniform(0.3, 0.55) * rh
            poly = [(x0 + c[0] + j(), y0 + j()), (x1 - c[1] + j(), y0 + j()), (x1 + j(), y0 + c[1] + j()),
                    (x1 + j(), y1 - c[2] + j()), (x1 - c[2] + j(), y1 + j()), (x0 + c[3] + j(), y1 + j()),
                    (x0 + j(), y1 - c[3] + j()), (x0 + j(), y0 + c[0] + j())]
            height = 1.0 if rng.random() > 0.12 else rng.uniform(0.72, 0.9) # a few sunk
            p.face(poly, rng.uniform(0.15, 0.85), height)
            if rng.random() < 0.07: # cracked through
                y = rng.uniform(y0, y1)
                x = x0 + (x1 - x0) * rng.uniform(0.2, 0.8)
                line = [(x, y0)]
                for q in range(1, 4):
                    line.append((x + rng.uniform(-0.4, 0.4) * rh, y0 + (y1 - y0) * q / 3.0))
                p.grooves.append((line, 0.0012, 0.75))
    return p


def _wobbly(pts, rng, amount, steps=3):
    """A polygon's edges, each split into `steps` with the middle points nudged: hand-cut, not ruled."""
    out = []
    for i, a in enumerate(pts):
        b = pts[(i + 1) % len(pts)]
        for s in range(steps):
            f = s / steps
            x = a[0] + (b[0] - a[0]) * f
            y = a[1] + (b[1] - a[1]) * f
            if s > 0:
                x += rng.uniform(-amount, amount)
                y += rng.uniform(-amount, amount)
            out.append((x, y))
    return out


def _shrink(poly, by):
    """Pull a polygon's corners toward its middle (leaves a joint round it)."""
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    out = []
    for x, y in poly:
        dx, dy = x - cx, y - cy
        d = (dx * dx + dy * dy) ** 0.5 or 1.0
        out.append((x - dx / d * by, y - dy / d * by))
    return out


def planks(name, rows, seed, bevel=0.006, joint=0.004, size=1024):
    """Boards in courses (rows run along u), staggered ends, a nail at each end, grain grooves."""
    rng = random.Random(seed)
    p = Pattern(name, bevel, size)
    rh = 1.0 / rows
    for r in range(rows):
        x = rng.random()
        end = x + 1.0
        y0, y1 = r * rh + joint, (r + 1) * rh - joint
        while x < end - 1e-6:
            w = min(rng.uniform(0.3, 0.6), end - x)
            if end - (x + w) < 0.12:
                w = end - x
            x0, x1 = x + joint, x + w - joint
            p.face(_wobbly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], rng, joint * 0.4, 4), rng.uniform(0.25, 0.75), rng.uniform(0.88, 1.0))
            for nx in (x0 + 0.02, x1 - 0.02):
                for ny in (y0 + rh * 0.28, y1 - rh * 0.28):
                    p.raised.append((("circle", (nx, ny), 0.0035), 0.7))
            for _ in range(rng.randint(1, 3)): # grain: long faint grooves along the board
                gy = rng.uniform(y0 + rh * 0.15, y1 - rh * 0.15)
                pts = [(x0 + 0.01, gy)]
                for k in range(1, 6):
                    pts.append((x0 + (x1 - x0) * k / 5.0, gy + rng.uniform(-0.15, 0.15) * rh))
                p.grooves.append((pts, 0.0012, 0.18))
            x += w
    return p


def bark(name, cols, seed, bevel=0.01, joint=0.006, size=1024):
    """Tree bark: long vertical ridges (rows run along v here: trunks are walls), split now and then."""
    rng = random.Random(seed)
    p = Pattern(name, bevel, size)
    cw = 1.0 / cols
    for c in range(cols):
        y = rng.random()
        end = y + 1.0
        while y < end - 1e-6:
            h = min(rng.uniform(0.25, 0.7), end - y)
            if end - (y + h) < 0.1:
                h = end - y
            x0 = c * cw + joint * rng.uniform(1.0, 2.5)
            x1 = (c + 1) * cw - joint * rng.uniform(1.0, 2.5)
            # ridges taper at their ends: an elongated hexagon, wobbly
            poly = [(x0 + cw * 0.15, y + joint), (x1 - cw * 0.15, y + joint), (x1, y + h * 0.15), (x1, y + h * 0.85),
                    (x1 - cw * 0.15, y + h - joint), (x0 + cw * 0.15, y + h - joint), (x0, y + h * 0.85), (x0, y + h * 0.15)]
            p.face(_wobbly(poly, rng, cw * 0.06, 3), rng.uniform(0.25, 0.75), rng.uniform(0.85, 1.0))
            y += h
    # bark tiles in v by wrapping ridges: draw is wrapped both ways already
    return p


def leaves(name, count, seed, bevel=0.003, size=1024):
    """Canopy: overlapping pointed leaves at every angle, drawn one over another, gaps dark."""
    rng = random.Random(seed)
    p = Pattern(name, bevel, size)
    import math
    for _ in range(count):
        cx, cy = rng.random(), rng.random()
        ln, wd = rng.uniform(0.07, 0.13), rng.uniform(0.025, 0.045)
        a = rng.uniform(0.0, math.tau)
        ca, sa = math.cos(a), math.sin(a)
        pts = []
        for k in range(12): # a leaf: pointed at both ends
            t = k / 12.0 * math.tau
            lx = math.cos(t) * ln
            ly = math.sin(t) * wd * abs(math.cos(t * 0.5)) ** 0.3 * (1.0 if math.sin(t) > 0 else 0.9)
            pts.append((cx + lx * ca - ly * sa, cy + lx * sa + ly * ca))
        p.face(pts, rng.uniform(0.15, 0.85), rng.uniform(0.8, 1.0), 0.006)
    return p


def facets(name, n, seed, bevel=0.01, joint=0.006, size=1024):
    """Broken rock: a jittered grid of corners (wrapping), each cell a facet, some split in two."""
    rng = random.Random(seed)
    p = Pattern(name, bevel, size)
    c = 1.0 / n
    pt = [[((i + rng.uniform(-0.3, 0.3)) * c, (j + rng.uniform(-0.3, 0.3)) * c) for j in range(n)] for i in range(n)]
    def corner(i, j):
        x, y = pt[i % n][j % n]
        return (x + (i // n) * 1.0, y + (j // n) * 1.0)
    for i in range(n):
        for j in range(n):
            q = [corner(i, j), corner(i + 1, j), corner(i + 1, j + 1), corner(i, j + 1)]
            if rng.random() < 0.45: # split along a diagonal
                parts = [[q[0], q[1], q[2]], [q[0], q[2], q[3]]] if rng.random() < 0.5 else [[q[0], q[1], q[3]], [q[1], q[2], q[3]]]
            else:
                parts = [q]
            for part in parts:
                p.face(_wobbly(_shrink(part, joint * 1.5), rng, c * 0.03, 2), rng.uniform(0.15, 0.85), rng.uniform(0.82, 1.0))
    return p


def flagstone(name, seed, cracks=4, inlay=True, bevel=0.01, joint=0.006):
    """Cathedral floor: 2 x 2 slabs, checkered tones, a border band, a diamond inlay; cracks."""
    rng = random.Random(seed)
    p = Pattern(name, bevel)
    for i in range(2):
        for j in range(2):
            x0, y0 = i * 0.5, j * 0.5
            tone = 0.3 if (i + j) % 2 == 0 else 0.68
            band = 0.045
            # border band and the slab inside it are separate stones
            p.rect(x0 + joint, y0 + joint, x0 + 0.5 - joint, y0 + band, 0.5 + (tone - 0.5) * 0.3, 0.0)
            p.rect(x0 + joint, y0 + 0.5 - band, x0 + 0.5 - joint, y0 + 0.5 - joint, 0.5 + (tone - 0.5) * 0.3, 0.0)
            p.rect(x0 + joint, y0 + band + joint * 2, x0 + band, y0 + 0.5 - band - joint * 2, 0.5 + (tone - 0.5) * 0.3, 0.0)
            p.rect(x0 + 0.5 - band, y0 + band + joint * 2, x0 + 0.5 - joint, y0 + 0.5 - band - joint * 2, 0.5 + (tone - 0.5) * 0.3, 0.0)
            p.rect(x0 + band + joint * 2, y0 + band + joint * 2, x0 + 0.5 - band - joint * 2, y0 + 0.5 - band - joint * 2, tone, 0.01)
            if inlay:
                cx, cy, r = x0 + 0.25, y0 + 0.25, 0.11
                p.accents.append(("line", [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy), (cx, cy - r)], 0.006))
                p.accents.append(("ring", ((cx, cy), r * 0.38), 0.005))
    for _ in range(cracks):
        x, y = rng.random(), rng.random()
        pts = [(x, y)]
        a = rng.uniform(0, 6.283)
        for _ in range(rng.randint(4, 7)):
            a += rng.uniform(-0.9, 0.9)
            x += np.cos(a) * 0.035
            y += np.sin(a) * 0.035
            pts.append((x, y))
        p.accents.append(("line", pts, 0.0035))
    return p


def plates(name, cols, rows, seed, bevel=0.008, joint=0.006):
    """Riveted iron plates: bridges, chains, parapets."""
    rng = random.Random(seed)
    p = Pattern(name, bevel)
    cw, rh = 1.0 / cols, 1.0 / rows
    for i in range(cols):
        for j in range(rows):
            x0, y0 = i * cw, j * rh
            p.rect(x0 + joint, y0 + joint, x0 + cw - joint, y0 + rh - joint, rng.uniform(0.35, 0.65), 0.0, 0.85)
            for cx in (x0 + 0.035, x0 + cw - 0.035):
                for cy in (y0 + 0.035, y0 + rh - 0.035):
                    p.raised.append((("circle", (cx, cy), 0.011), 1.0))
    return p


def trim(name, seed, bevel=0.01, joint=0.006):
    """Gothic trim: two bands of blocks, a row of quatrefoils between them: galleries, altars."""
    rng = random.Random(seed)
    p = Pattern(name, bevel)
    p.rect(0.0, joint, 1.0, 0.18, 0.62, 0.0)
    p.rect(0.0, 0.82, 1.0, 1.0 - joint, 0.62, 0.0)
    for k in range(4):
        x0 = k * 0.25
        p.rect(x0 + joint, 0.18 + joint * 2, x0 + 0.25 - joint, 0.82 - joint * 2, rng.uniform(0.3, 0.45), 0.012)
        cx, cy = x0 + 0.125, 0.5
        for dx, dy in ((0.045, 0), (-0.045, 0), (0, 0.045), (0, -0.045)):
            p.accents.append(("ring", ((cx + dx, cy + dy), 0.05), 0.007))
        p.accents.append(("poly", [(cx, cy - 0.03), (cx + 0.03, cy), (cx, cy + 0.03), (cx - 0.03, cy)], 0.0))
    p.accents.append(("line", [(0.0, 0.09), (1.0, 0.09)], 0.006))
    p.accents.append(("line", [(0.0, 0.91), (1.0, 0.91)], 0.006))
    return p


PATTERNS = [
    # (twice the tile they used to be, the materials' tile_size doubled to match: same stone sizes,
    # four times as many different stones before the tile repeats)
    ashlar("ashlar_large", 8, 0.17, 11),
    ashlar("ashlar_small", 12, 0.1, 23, bevel=0.008),
    brick("brick", 32, 16, 61),
    planks("planks", 8, 71),
    # (bark and leaves patterns retired: the Jungle's trees use real textures, tools/texgen/foliage.py)
    facets("facets", 7, 97),
    flagstone("flagstone", 31),
    flagstone("flagstone_plain", 37, cracks=2, inlay=False),
    plates("plates", 2, 4, 41),
    trim("trim", 53),
]

if __name__ == "__main__":
    for pat in PATTERNS:
        render(pat)
        print(f"  {pat.name}: {len(pat.faces)} faces, {len(pat.accents)} accents")
