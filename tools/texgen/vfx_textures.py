"""
Textures for effects, drawn in the game's vector style (flat tones, crisp shapes, soft only at
the very edge):
    python3 tools/texgen/vfx_textures.py

  assets/images/vfx/smoke_puff.png  a lumpy cloud puff: a body of overlapping round lobes, a
                                    lighter top (lit from above), a darker underside; greyscale,
                                    tinted by the particles' colour ramp. Alpha: the silhouette,
                                    a couple of pixels soft.
Deterministic (fixed seed).
"""

import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = "assets/images/vfx"
SIZE = 128
SS = 4 # supersampled, then shrunk: clean edges


def _lobes(rng, cx, cy, r, n):
    """n round lobes around (cx, cy) making a cloud about r across."""
    out = [(cx, cy + r * 0.1, r * 0.55)]
    for k in range(n):
        a = k / n * math.tau + rng.uniform(-0.3, 0.3)
        d = r * rng.uniform(0.5, 0.66)
        out.append((cx + math.cos(a) * d, cy + math.sin(a) * d * 0.85, r * rng.uniform(0.26, 0.38)))
    return out


def _mask(lobes, size, dx=0.0, dy=0.0, grow=0.0):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    for x, y, r in lobes:
        r = r + grow
        d.ellipse((x + dx - r, y + dy - r, x + dx + r, y + dy + r), fill=255)
    return m


def smoke_puff():
    rng = random.Random(7)
    s = SIZE * SS
    c = s / 2
    lobes = _lobes(rng, c, c, s * 0.36, 8)
    body = _mask(lobes, s)
    # tones: underside 0.55, body 0.75, the top lit 0.95 (the body's silhouette shifted down and
    # cut away leaves the lit top rim; shifted up, the shaded underside)
    lit = ImageChops.subtract(body, _mask(lobes, s, 0, s * 0.07))
    shade = ImageChops.subtract(body, _mask(lobes, s, 0, -s * 0.09))
    tone = Image.new("L", (s, s), int(0.75 * 255))
    tone.paste(int(0.55 * 255), mask=shade)
    tone.paste(int(0.95 * 255), mask=lit)
    img = Image.merge("RGBA", (tone, tone, tone, body))
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    a = img.getchannel("A").filter(ImageFilter.GaussianBlur(1.2)) # soft at the very edge only
    img.putalpha(a)
    os.makedirs(OUT, exist_ok=True)
    img.save(f"{OUT}/smoke_puff.png")
    print("wrote", f"{OUT}/smoke_puff.png")


if __name__ == "__main__":
    smoke_puff()
