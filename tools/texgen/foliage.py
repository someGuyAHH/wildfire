#!/usr/bin/env python3
"""
Leafy twig cards for the tree crowns, composed from single leaves (ambientCG LeafSet024, CC0;
sources in tools/texgen/sources/). Writes assets/images/foliage/twigs.png: a 2 x 2 atlas of
transparent twig cards (RGBA, straight alpha), each a stem with leaves angled off it. A crown
is a few dozen of these cards, not hundreds of single-leaf quads.
Deterministic. Run from the project root:
    python3 tools/texgen/foliage.py
"""

import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance

SRC = "tools/texgen/sources"
OUT = "assets/images/foliage/twigs.png"
CARD = 1024   # px per card
# the source atlas: 3 x 3 leaves, stems down (bands measured from its opacity map)
COLS = [(95, 593), (783, 1259), (1468, 1944)]
ROWS = [(8, 670), (695, 1354), (1382, 2031)]


def load_leaves():
    color = Image.open(f"{SRC}/leafset024_color.jpg").convert("RGB")
    alpha = Image.open(f"{SRC}/leafset024_opacity.jpg").convert("L")
    rgba = color.copy()
    rgba.putalpha(alpha)
    leaves = []
    for r0, r1 in ROWS:
        for c0, c1 in COLS:
            leaves.append(rgba.crop((c0, r0, c1 + 1, r1 + 1)))
    return leaves


def twig(leaves, seed):
    """One card: a stem from the bottom middle up to near the top, leaves off both sides."""
    rng = random.Random(seed)
    card = Image.new("RGBA", (CARD, CARD), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    # the stem: a gentle curve
    bend = rng.uniform(-0.12, 0.12) * CARD
    stem = [(CARD * 0.5 + bend * math.sin(t * math.pi * 0.8), CARD * (0.98 - t * 0.8)) for t in np.linspace(0, 1, 12)]
    d.line(stem, fill=(70, 52, 30, 255), width=10, joint="curve")
    count = rng.randint(12, 16)
    placed = []
    for i in range(count):
        t = 0.08 + 0.9 * i / count
        k = min(int(t * (len(stem) - 1)), len(stem) - 2)
        sx, sy = stem[k]
        side = -1 if i % 2 == 0 else 1
        # leaves point outward and up, more upright toward the tip
        angle = side * rng.uniform(55, 95) * (1.0 - 0.45 * t) + rng.uniform(-8, 8)
        size = rng.uniform(0.22, 0.29) * CARD * (1.0 - 0.3 * t)
        leaf = rng.choice(leaves)
        w, h = leaf.size
        scale = size / h
        leaf = leaf.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
        # a little variety: some leaves lighter or yellower, some darker
        leaf_rgb = ImageEnhance.Brightness(leaf.convert("RGB")).enhance(rng.uniform(0.75, 1.15))
        leaf_rgb = ImageEnhance.Color(leaf_rgb).enhance(rng.uniform(0.85, 1.2))
        leaf_rgb.putalpha(leaf.getchannel("A"))
        leaf = leaf_rgb.rotate(-angle, resample=Image.BICUBIC, expand=True)
        # the stem end of the leaf sits on the twig: after rotating, that's the leaf's base point
        a = math.radians(angle)
        lw, lh = leaf.size
        bx = lw / 2 - math.sin(a) * size * 0.48
        by = lh / 2 + math.cos(a) * size * 0.48
        placed.append((leaf, int(sx - bx), int(sy - by)))
    # tip leaves last so they sit on top
    for leaf, x, y in placed:
        card.paste(leaf, (x, y), leaf)
    return card


def bleed(img):
    """Transparent pixels take the leaves' mean colour, so mipmaps don't fringe dark."""
    a = np.asarray(img).astype(np.float32)
    mask = a[..., 3] > 8
    mean = a[mask][:, :3].mean(axis=0)
    a[~mask, :3] = mean
    return Image.fromarray(a.astype(np.uint8), "RGBA")


if __name__ == "__main__":
    leaves = load_leaves()
    atlas = Image.new("RGBA", (CARD * 2, CARD * 2), (0, 0, 0, 0))
    for i in range(4):
        atlas.paste(twig(leaves, 100 + i), ((i % 2) * CARD, (i // 2) * CARD))
    bleed(atlas).save(OUT)
    print(f"  {OUT}: 4 twig cards")
