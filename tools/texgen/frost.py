#!/usr/bin/env python3
"""
The Freeze frost (assets/gdshaders/frost_vignette.gdshader) as one baked texture:
  assets/images/vfx/frost.png  (2048 x 1152, 16:9, stretched over the screen)
    R  crystal lines: how bright the ice is there (0 = clear)
    G  growth time: when that bit of crystal forms, 0..254 (255 = never). The shader shows a pixel
       once its time has come, so as the frost's strength rises the crystals sprout at the edges and
       branch inward exactly the way they were grown here
    B  haze noise (fbm): breaks up the blue mist's inner edge so it isn't a clean oval

The crystals are snowflake stars (six arms with side branches, branches on the branches for the
big ones, a few long thin spikes) and frost feathers growing in off the screen's edges (a wandering
stem with alternating side shoots). Thick near the edges and corners, thinning toward the middle;
the ones further in start later. Deterministic (seeded). Run from the project root:
    python3 tools/texgen/frost.py
"""

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw

OUT = "assets/images/vfx"
W, H = 2048, 1152
SS = 2                      # supersampling (lines drawn at 2x, averaged down)
ASPECT = W / H
GROW = 0.28                 # how much of the 0..1 timeline one crystal takes to grow out
DEPTH_SCALE = 0.085         # seeds thin out inward like exp(-depth / this) (depth in screen heights)


class Canvas:
    def __init__(self):
        self.segs = []      # (t, x0, y0, x1, y1, width, bright), in supersampled pixels

    def line(self, t, a, b, width, bright):
        self.segs.append((t, a[0] * SS, a[1] * SS, b[0] * SS, b[1] * SS, width * SS, bright))

    def render(self):
        bright = Image.new("L", (W * SS, H * SS), 0)
        time = Image.new("L", (W * SS, H * SS), 255)
        db, dt = ImageDraw.Draw(bright), ImageDraw.Draw(time)
        # latest first, so the earliest time wins where crystals cross
        for t, x0, y0, x1, y1, w, br in sorted(self.segs, key=lambda s: -s[0]):
            dt.line((x0, y0, x1, y1), fill=int(min(max(t, 0.0), 1.0) * 254), width=max(1, round(w)))
            db.line((x0, y0, x1, y1), fill=int(br * 255), width=max(1, round(w)))
        b = np.asarray(bright, dtype=np.float32).reshape(H, SS, W, SS).mean(axis=(1, 3))
        t = np.asarray(time, dtype=np.uint8).reshape(H, SS, W, SS).min(axis=(1, 3))
        return b, t


def depth_of(x, y):
    """Distance in from the nearest screen edge, in screen heights."""
    u, v = x / W, y / H
    return min(u * ASPECT, (1 - u) * ASPECT, v, 1 - v)


def branch(cv, rng, x, y, ang, length, t0, speed, level, bright, width):
    """A dendrite: a straight arm growing out at `speed` px per time unit, side shoots at +-60
    degrees every few px (shorter toward the tip), the shoots branching again while `level` lasts."""
    step = 3.0
    n = max(1, int(length / step))
    px, py = x, y
    next_shoot = rng.uniform(4.0, 8.0)
    for i in range(1, n + 1):
        s = i * step
        nx, ny = x + math.cos(ang) * s, y + math.sin(ang) * s
        fade = 1.0 - 0.55 * (s / length)
        cv.line(t0 + (s - step) / speed, (px, py), (nx, ny), width * (0.6 + 0.4 * fade), bright * fade)
        px, py = nx, ny
        if level > 0 and s >= next_shoot and s < length * 0.92:
            left = (length - s) * rng.uniform(0.28, 0.48)
            if left > 2.5:
                for side in (-1.0, 1.0):
                    a2 = ang + side * math.radians(rng.uniform(55.0, 65.0))
                    branch(cv, rng, nx, ny, a2, left, t0 + s / speed, speed, level - 1, bright * 0.85, width * 0.75)
            next_shoot = s + rng.uniform(4.0, 9.0) * (1.0 + 0.6 * (level == 1))


def star(cv, rng, x, y, r, t0):
    """A snowflake star: six arms (a random turn), bigger ones branching twice, plus faint long spikes."""
    speed = r / GROW
    base = rng.uniform(0.0, math.pi / 3.0)
    level = 2 if r > 45 else (1 if r > 10 else 0)
    bright = rng.uniform(0.75, 1.0)
    for k in range(6):
        a = base + k * math.pi / 3.0 + rng.uniform(-0.06, 0.06)
        branch(cv, rng, x, y, a, r * rng.uniform(0.8, 1.1), t0, speed, level, bright, 1.3 if r > 45 else 1.0)
    if r > 45: # long thin spikes between the arms, like the big flakes in a frosted pane
        for k in range(rng.randint(2, 5)):
            a = base + rng.uniform(0.0, math.tau)
            branch(cv, rng, x, y, a, r * rng.uniform(1.3, 2.0), t0, speed, 0, bright * 0.6, 0.8)
        cv.line(t0, (x - 1.5, y), (x + 1.5, y), 3.0, 1.0) # a bright knot where it began


def feather(cv, rng, x, y, ang, length, t0):
    """Frost feather: a stem growing in off the edge, wandering a little, shoots alternating sides."""
    speed = length / GROW
    step = 3.0
    s = 0.0
    side = 1.0
    px, py = x, y
    next_shoot = rng.uniform(4.0, 7.0)
    while s < length:
        ang += rng.uniform(-0.05, 0.05)
        nx, ny = px + math.cos(ang) * step, py + math.sin(ang) * step
        cv.line(t0 + s / speed, (px, py), (nx, ny), 1.4 * (1.0 - 0.5 * s / length), 0.9 * (1.0 - 0.45 * s / length))
        s += step
        px, py = nx, ny
        if s >= next_shoot:
            shoot = (length - s) * rng.uniform(0.25, 0.42)
            if shoot > 3.0:
                branch(cv, rng, px, py, ang + side * math.radians(rng.uniform(50.0, 62.0)), shoot,
                       t0 + s / speed, speed, 1, 0.8, 1.0)
            side = -side
            next_shoot = s + rng.uniform(5.0, 10.0)


def seed_time(rng, x, y):
    """When a crystal starts: right away at the edge, later the further in (the frost closes in)."""
    return min(depth_of(x, y) / 0.42, 1.0) * 0.62 + rng.uniform(0.0, 0.1)


def place(rng, n, edge_bias=1.0):
    """n points thinning out inward (accept with exp(-depth / DEPTH_SCALE))."""
    pts = []
    while len(pts) < n:
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        if rng.random() < math.exp(-depth_of(x, y) / (DEPTH_SCALE * edge_bias)):
            pts.append((x, y))
    return pts


def fbm(rng, octaves=5):
    out = np.zeros((H, W), dtype=np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = 4 * 2 ** o
        small = Image.fromarray((np.array([[rng.random() for _ in range(cells * 2)] for _ in range(cells)]) * 255).astype(np.uint8))
        out += np.asarray(small.resize((W, H), Image.BICUBIC), dtype=np.float32) / 255.0 * amp
        total += amp
        amp *= 0.55
    return out / total


def main():
    rng = random.Random(1717)
    cv = Canvas()
    for x, y in place(rng, 70, 1.3):
        star(cv, rng, x, y, rng.uniform(50.0, 150.0), seed_time(rng, x, y))
    for x, y in place(rng, 240, 1.2):
        star(cv, rng, x, y, rng.uniform(15.0, 48.0), seed_time(rng, x, y))
    for x, y in place(rng, 1100, 1.0):
        star(cv, rng, x, y, rng.uniform(3.0, 13.0), seed_time(rng, x, y))
    # feathers off every edge, pointing in (a little off square)
    for _ in range(190):
        e = rng.randrange(4)
        if e == 0: x, y, a = rng.uniform(0, W), 0.0, math.pi * 0.5
        elif e == 1: x, y, a = rng.uniform(0, W), H, -math.pi * 0.5
        elif e == 2: x, y, a = 0.0, rng.uniform(0, H), 0.0
        else: x, y, a = W, rng.uniform(0, H), math.pi
        feather(cv, rng, x, y, a + rng.uniform(-0.45, 0.45), rng.uniform(60.0, 240.0), rng.uniform(0.0, 0.12))
    print(f"{len(cv.segs)} segments")
    bright, time = cv.render()
    bright = np.clip((bright / 255.0) ** 0.8 * 1.25, 0.0, 1.0)
    haze = fbm(rng)
    img = np.dstack([(bright * 255).astype(np.uint8), time, (haze * 255).astype(np.uint8)])
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(img, "RGB").save(f"{OUT}/frost.png")
    print(f"saved {OUT}/frost.png")


if __name__ == "__main__":
    main()
