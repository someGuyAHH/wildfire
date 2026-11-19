#!/usr/bin/env python3
"""
Stain a wood colour map a flat colour, keeping its grain: each pixel's brightness relative to the
image's mean scales the target colour (in linear light), so the result averages to the target.
A tint in the material can't do this: the source is dark, and a tint only multiplies down.
    python3 tools/texgen/stain.py
"""

import numpy as np
from PIL import Image

JOBS = [
    # (source, output, target sRGB colour, contrast 0..1)
    ("assets/images/wood/planks023a_color.jpg", "assets/images/wood/planks023a_orange_color.png", (0.86, 0.56, 0.26), 0.8),
]


def lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


for src, out, colour, contrast in JOBS:
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255
    lum = lin(a) @ np.array([0.2126, 0.7152, 0.0722])
    rel = 1.0 + (lum / lum.mean() - 1.0) * contrast
    t = lin(np.array(colour)) * 0.9
    img = srgb(np.clip(t[None, None, :] * rel[..., None], 0, 1))
    Image.fromarray((img * 255 + 0.5).astype(np.uint8)).save(out)
    print(out)
