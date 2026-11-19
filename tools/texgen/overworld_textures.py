#!/usr/bin/env python3
"""
The Overworld's photo textures (M6 art pass), made from ambientCG CC0 sets (2K JPG). Download each
set listed in SETS from https://ambientcg.com/get?file=<id>_2K-JPG.zip, unzip each into its own
folder <src>/<id>/, then run from the project root:
    python3 -I tools/texgen/overworld_textures.py <src>

Writes
  assets/images/terrain/ow_<name>_ah.png   Terrain3D albedo (RGB) + height (A), 1024 px
  assets/images/terrain/ow_<name>_nr.png   Terrain3D normal (RGB, OpenGL: +Y up) + roughness (A)
  assets/images/terrain/macro_noise.png    tiling noise: R, G two unrelated fBm layers, B fine
                                           (the terrain's macro variation and anti-tiling, and the
                                           structures' shader)
  assets/images/overworld/<name>_{color,normal,rough[,metal]}.jpg   structure textures, 2K
Everything Godot imports is VRAM-compressed with mipmaps (the .import files are written once).
References the looks were picked against (Wikimedia Commons): the Pont du Gard (warm honey
limestone, hairline joints, rain streaks; pale limestone outcrops, dry grass and scrub around it),
a random rubble masonry wall, lime-plastered walls on Tinos.
"""

import colorsys
import os
import sys

import numpy as np
from PIL import Image

TERRAIN = "assets/images/terrain"
STRUCT = "assets/images/overworld"

# ground layers: (name, ambientCG id)
GROUND = [("rock", "Rock023"), ("grass", "Grass004"), ("dirt", "Ground079S")]
# structures: (name, ambientCG id, extra maps)
STRUCTURES = [
    ("limestone", "Concrete012", []),       # the aqueduct and ruins: weathered stone, stained honey in the material
    ("rubble", "Rocks001", []),             # towers and pillar runs: random rubble masonry
    ("cliff", "Rock023", []),               # blocks, mesa pillars: the cliffs' layered limestone
    ("metal", "PaintedMetal004", ["Metalness"]),  # launch hubs: chipped paint, recoloured blue
]
SETS = sorted({i for _, i in GROUND} | {i for _, i, _ in STRUCTURES})


def load(src, aid, kind, size=None, mode="RGB"):
    im = Image.open(f"{src}/{aid}/{aid}_2K-JPG_{kind}.jpg").convert(mode)
    if size and im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def write_import(path, normal=False):
    imp = path + ".import"
    if os.path.exists(imp):
        return
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
compress/normal_map={1 if normal else 2}
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


def save(arr, path, mode="RGBA", normal=False, quality=None):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode)
    if quality:
        img.save(path, quality=quality)
    else:
        img.save(path)
    write_import(path, normal)
    print("  ", path)


def recolour_metal(rgb, hue=0.58, sat=0.5, value=0.78):
    """PaintedMetal004 is red paint chipped down to bare metal: turn the paint the hubs' blue (its
    shading and scratches kept, at the hubs' brightness), and the pale pinkish chips (bare metal and
    primer) plain grey."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    v = rgb.max(-1)
    s = np.where(v > 0, (v - rgb.min(-1)) / np.maximum(v, 1e-6), 0)
    paint = np.clip((s - 0.35) / 0.15, 0, 1)[..., None]  # saturated red: paint; pale: chips
    rel = (v / np.median(v[s > 0.5]))[..., None]           # the paint's own shading, ~1 on average
    blue = np.array(colorsys.hsv_to_rgb(hue, sat, value), np.float32)
    grey = (r * 0.3 + g * 0.45 + b * 0.25)[..., None] * np.array([0.95, 0.97, 1.0], np.float32)
    return paint * blue * rel + (1 - paint) * grey


def fbm(size, octaves, seed, base=4):
    """Tiling fBm value noise (each octave a tiling lattice, smoothly interpolated)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = base * 2 ** o
        lat = rng.random((n, n)).astype(np.float32)
        x = np.arange(size) * n / size
        i0 = np.floor(x).astype(int)
        f = x - i0
        f = f * f * (3 - 2 * f)
        i1 = (i0 + 1) % n
        rows = lat[i0][:, i0] * (1 - f)[None, :] + lat[i0][:, i1] * f[None, :]
        rows1 = lat[i1][:, i0] * (1 - f)[None, :] + lat[i1][:, i1] * f[None, :]
        out += amp * (rows * (1 - f)[:, None] + rows1 * f[:, None])
        total += amp
        amp *= 0.5
    out /= total
    return (out - out.min()) / (out.max() - out.min())


def main():
    src = sys.argv[1]
    os.makedirs(TERRAIN, exist_ok=True)
    os.makedirs(STRUCT, exist_ok=True)
    print("ground layers")
    for name, aid in GROUND:
        col = load(src, aid, "Color", 1024)
        disp = load(src, aid, "Displacement", 1024, "L")
        nrm = load(src, aid, "NormalGL", 1024)
        rough = load(src, aid, "Roughness", 1024, "L")
        # heights stretched to the full range: Terrain3D's height blend reads them against each other
        disp = (disp - disp.min()) / max(1e-6, disp.max() - disp.min())
        save(np.dstack([col, disp]), f"{TERRAIN}/ow_{name}_ah.png")
        save(np.dstack([nrm, rough]), f"{TERRAIN}/ow_{name}_nr.png")
    print("macro noise")
    noise = np.dstack([fbm(512, 5, 1), fbm(512, 5, 2), fbm(512, 3, 3, 16), np.ones((512, 512), np.float32)])
    save(noise, f"{TERRAIN}/macro_noise.png")
    print("structures")
    for name, aid, extra in STRUCTURES:
        col = load(src, aid, "Color")
        if name == "metal":
            col = recolour_metal(col)
        save(col, f"{STRUCT}/{name}_color.jpg", "RGB", quality=92)
        save(load(src, aid, "NormalGL"), f"{STRUCT}/{name}_normal.jpg", "RGB", normal=True, quality=95)
        save(load(src, aid, "Roughness", None, "L"), f"{STRUCT}/{name}_rough.jpg", "L", quality=92)
        for kind in extra:
            save(load(src, aid, kind, None, "L"), f"{STRUCT}/{name}_{kind.lower()}.jpg", "L", quality=92)


if __name__ == "__main__":
    main()
