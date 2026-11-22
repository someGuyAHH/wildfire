#!/usr/bin/env python3
"""
The game icon (icon.png, 1024 x 1024), composited from Godot renders (tools/mapgen/icon_art.gd):
  - the chase: you (teal) sprinting at the viewer, the Torch on fire right behind, cut out of a
    black and a white backdrop pass (premultiplied: the backdrop shows through by white - black,
    so the Torch's additive fire stays light, not a grey smear);
  - behind them the three maps shattered into one: the Overworld's aqueduct, the Inferno's arch and
    the Jungle's temple as shards fanning out from behind the runners, split by cracks burning ember;
  - a wall of fire in bands (the menus' palette, from deep ember to a cream core) rising behind
    them, a low lick of it in front over their feet, embers drifting up, the fire's light on the
    cast (warm rim on their edges), bloom, a vignette, and the menus' ember-edged rounded square.
Deterministic (seeded). Run from the project root, renders from icon_art.gd's OUT:
    python3 tools/texgen/icon.py <renders dir> [preview dir]
"""

import math
import os
import random
import sys
import zlib

import numpy as np
from PIL import Image, ImageDraw

S = 2048                    # working size (the icon is this halved)
OUT = os.environ.get("ICON_OUT", "icon.png")
CAST = "chase3"
# per element seeds (picked from sweeps); ICON_SEEDS="far=7,near=3" overrides for trying others
SEEDS = {"maps": 4417, "far": 1, "near": 11, "front": 3, "embers_far": 4, "embers_near": 5}
SEEDS.update({k: int(v) for k, v in (kv.split("=") for kv in os.environ.get("ICON_SEEDS", "").split(",") if kv)})

CHARCOAL = (0x14, 0x11, 0x0f)
# the fire's bands, outside in: soot red, deep ember, ember, orange, gold, cream
FIRE = [(0x5a, 0x0c, 0x05), (0xc2, 0x26, 0x0f), (0xff, 0x6a, 0x1a), (0xff, 0x96, 0x2a), (0xff, 0xc2, 0x3a), (0xff, 0xf0, 0xc8)]


def c3(rgb):
    return np.array(rgb, dtype=np.float32) / 255.0


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def resize(a, w, h):
    """Float image resize (per channel, via PIL 'F')."""
    if a.ndim == 2:
        return np.asarray(Image.fromarray(np.ascontiguousarray(a, dtype=np.float32), "F").resize((w, h), Image.BICUBIC), dtype=np.float32)
    return np.dstack([resize(a[..., i], w, h) for i in range(a.shape[2])])


def box(a, r, axis):
    if r < 1: return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a, sigma):
    """Gaussian-ish: three box passes each way (at a reduced size for big radii)."""
    if sigma <= 0: return a
    k = 1
    while sigma / k > 24 and a.shape[0] // (k * 2) > 32: k *= 2
    small = resize(a, a.shape[1] // k, a.shape[0] // k) if k > 1 else a
    r = max(1, int(round(math.sqrt(12 * (sigma / k) ** 2 / 3 + 1) / 2)))
    for _ in range(3):
        small = box(box(small, r, 0), r, 1)
    return resize(small, a.shape[1], a.shape[0]) if k > 1 else small


def fbm(rng, w, h, base=4, octaves=6, gain=0.55):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cw, ch = base * 2 ** o, max(2, int(base * 2 ** o * h / w))
        g = np.array([[rng.random() for _ in range(cw + 1)] for _ in range(ch + 1)], np.float32)
        out += resize(g, w, h) * amp
        tot += amp
        amp *= gain
    return out / tot


def sample(img, x, y):
    """Bilinear sample of a 2D field at float pixel coords (clamped)."""
    h, w = img.shape
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0, y0 = x.astype(np.int32), y.astype(np.int32)
    fx, fy = x - x0, y - y0
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def over(dst, rgb, a):
    a = a[..., None]
    return dst * (1 - a) + rgb * a


YY, XX = np.mgrid[0:S, 0:S].astype(np.float32)
U, V = XX / S, YY / S


# ---------------------------------------------------------------- the maps, shattered

def place(plate, scale, at, focus):
    """The plate scaled to `scale` x the canvas, its point `focus` (0..1 of the plate) at `at` (0..1)."""
    n = int(S * scale)
    p = resize(plate, n, n)
    ox, oy = int(at[0] * S - focus[0] * n), int(at[1] * S - focus[1] * n)
    out = np.zeros((S, S, 3), np.float32)
    cover = np.zeros((S, S), np.float32)
    xs, ys = max(0, ox), max(0, oy)
    xe, ye = min(S, ox + n), min(S, oy + n)
    out[ys:ye, xs:xe] = p[ys - oy:ye - oy, xs - ox:xe - ox]
    cover[ys:ye, xs:xe] = 1.0
    return out, cover


def smoke(rng):
    """Soot billowing up off the fire: warm and lit from below, cold and dark up top."""
    n = fbm(rng, S, S, 4, 6, 0.6)
    m = fbm(rng, S, S, 10, 4)
    lit = smooth(0.15, 0.95, V)
    base = c3((26, 18, 16)) * (1 - lit[..., None]) + c3((92, 34, 14)) * lit[..., None]
    return np.clip(base * (0.55 + 0.9 * n[..., None]) + c3((255, 120, 40)) * (np.clip(m - 0.62, 0, 1) * 1.2 * lit)[..., None], 0, 1)


def grade(img, tint, dark, sat):
    lum = img @ np.array([0.299, 0.587, 0.114], np.float32)
    g = lum[..., None] + (img - lum[..., None]) * sat
    return np.clip(g * dark * c3(tint) * 1.15, 0, 1)


def collage(rd, rng):
    ow, ow_c = place(load(f"{rd}/overworld_b.png"), 0.95, (0.20, 0.50), (0.45, 0.55))
    inf, inf_c = place(load(f"{rd}/inferno_b.png"), 0.95, (0.50, 0.36), (0.17, 0.42))
    jg, jg_c = place(load(f"{rd}/jungle_a.png"), 0.95, (0.80, 0.42), (0.32, 0.42))
    # cooler up top-left (the sky), all of it warming toward the fire below
    warm = smooth(0.15, 1.0, V)[..., None]
    ow = grade(ow, (225, 225, 240), 0.8, 0.85) * (1 - warm * 0.35) + warm * 0.35 * c3((150, 60, 25)) * ow.mean(2, keepdims=True) * 2
    inf = grade(inf, (255, 200, 170), 0.85, 1.0)
    jg = grade(jg, (230, 235, 215), 0.78, 0.8) * (1 - warm * 0.35) + warm * 0.35 * c3((150, 60, 25)) * jg.mean(2, keepdims=True) * 2
    # shards fanning out from behind the runners: by angle, with jagged, wandering edges
    cx, cy = 0.5, 0.95
    ang = np.arctan2(U - cx, cy - V)              # 0 straight up, - left, + right
    n1 = fbm(rng, S, S, 3, 6) - 0.5
    n2 = fbm(rng, S, S, 12, 3) - 0.5
    ang = ang + n1 * 0.55 + n2 * 0.12
    cuts = (-0.34, 0.30)                          # radians: Overworld | Inferno | Jungle
    w_edge = 0.006
    m_ow = smooth(cuts[0] + w_edge, cuts[0] - w_edge, ang)
    m_jg = smooth(cuts[1] - w_edge, cuts[1] + w_edge, ang)
    m_in = np.clip(1 - m_ow - m_jg, 0, 1)
    sm = smoke(rng)   # wherever a plate doesn't reach
    ow, inf, jg = (over(sm, p_, c_) for p_, c_ in ((ow, ow_c), (inf, inf_c), (jg, jg_c)))
    bg = ow * m_ow[..., None] + inf * m_in[..., None] + jg * m_jg[..., None]
    # the cracks between, burning: a hot core line and a wider glow, hotter toward the fire
    d = np.minimum(np.abs(ang - cuts[0]), np.abs(ang - cuts[1]))
    r = np.hypot(U - cx, V - cy) + 1e-3
    px = d * r * S                               # roughly the distance in pixels
    core = np.exp(-(px / 3.0) ** 2)
    halo = np.exp(-(px / 26.0) ** 2)
    heat = smooth(1.0, 0.2, r)
    bg = np.clip(bg * (1 - halo[..., None] * 0.5) + halo[..., None] * c3(FIRE[1]) * (0.6 * heat[..., None] + 0.25)
                 + core[..., None] * c3(FIRE[4]) * (0.9 * heat[..., None] + 0.3), 0, 1)
    # the fire's light from below
    glow = np.exp(-(((U - 0.52) / 0.42) ** 2 + ((V - 1.0) / 0.55) ** 2))
    bg = np.clip(bg * (0.55 + 0.45 * (1 - glow[..., None] * 0.6)) + glow[..., None] * c3((255, 90, 25)) * 0.42, 0, 1)
    return bg


# ---------------------------------------------------------------- fire

def flames(rng, base, peak, peak_at, width, tongues, warp, lick, bands=FIRE, soft=1.2):
    """A banded flame wall: a height per column (an envelope with tongues), the field warped so the
    tongues sway and lick; v = 0 at the edge, 1 down in the base. Returns (rgb, alpha)."""
    xs = np.linspace(0, 1, S, dtype=np.float32)
    env = base + (peak - base) * np.exp(-((xs - peak_at) / width) ** 2)
    tng = np.zeros(S, np.float32)
    for _ in range(tongues):
        c, wdt, amp = rng.random(), rng.uniform(0.012, 0.05), rng.uniform(0.3, 1.0)
        tng += amp * np.exp(-((xs - c) / wdt) ** 2)
    env = env * (0.72 + 0.45 * np.clip(tng, 0, 1.4))
    n1 = fbm(rng, S, S, 5, 5) - 0.5
    n2 = fbm(rng, S, S, 9, 4) - 0.5
    hgt = 1 - V
    wx = XX + (n1 * warp * S) * (0.25 + hgt)          # sway more higher up
    wy = YY + n2 * warp * 0.5 * S
    e = sample(np.tile(env, (S, 1)), wx, wy)
    h2 = 1 - wy / S
    v = 1 - h2 / np.maximum(e, 1e-3)
    holes = fbm(rng, S, S, 14, 3)
    v = v - lick * (holes - 0.35) * (1 - np.clip(v, 0, 1)) ** 2
    # band it, with a pixel-and-a-bit of antialiasing on each edge
    v = np.clip(v, -1.0, 1.5)
    gy, gx = np.gradient(v)
    aa = np.clip(np.hypot(gx, gy) * soft, 1e-5, 0.05)
    th = [0.0, 0.10, 0.24, 0.40, 0.58, 0.78]
    rgb = np.zeros((S, S, 3), np.float32)
    rgb[:] = c3(bands[0])
    for t, col in zip(th[1:], bands[1:]):
        rgb = over(rgb, c3(col), np.clip((v - t) / aa + 0.5, 0, 1))
    alpha = np.clip(v / aa + 0.5, 0, 1)
    return rgb, alpha


def embers(rng, n, layer_alpha=1.0):
    img = Image.new("RGB", (S, S), (0, 0, 0))
    dr = ImageDraw.Draw(img)
    for _ in range(n):
        x = rng.gauss(0.52, 0.28) * S
        y = (1 - rng.random() ** 1.6) * S
        size = rng.choice([1.5, 2, 2.5, 3, 4, 5, 7]) * (0.6 + 0.8 * (y / S))
        ln = size * rng.uniform(2.0, 6.0)
        a = math.radians(rng.uniform(-115, -70))  # drifting up, a little to the left
        col = random.choice(FIRE[3:]) if rng.random() < 0.7 else FIRE[2]
        k = layer_alpha * rng.uniform(0.6, 1.0)
        col = tuple(int(c * k) for c in col)
        dr.line((x, y, x + math.cos(a) * ln, y + math.sin(a) * ln), fill=col, width=max(1, int(size)))
        dr.ellipse((x - size * 0.6, y - size * 0.6, x + size * 0.6, y + size * 0.6), fill=col)
    return np.asarray(img, np.float32) / 255.0


def plume(rng, hx, hy, height, width, lean):
    """The Torch's own fire: a banded plume from its head, streaming back (lean, radians from up,
    + to the right) as it runs, tongues splitting off near the tip."""
    ca, sa = math.cos(lean), math.sin(lean)
    dx, dy = XX - hx, YY - hy
    ax = dx * ca + dy * sa
    ay = dx * sa - dy * ca
    t = ay / height
    n1 = fbm(rng, S, S, 7, 5) - 0.5
    n2 = fbm(rng, S, S, 16, 3) - 0.5
    ax = ax + (n1 * 0.9 + n2 * 0.35) * width * (0.2 + np.clip(t, 0, 1) * 1.6)
    w = width * np.clip(1 - t, 0, 1) ** 0.75 * np.sqrt(smooth(-0.45, 0.05, t))   # round at the head, tapering
    v = (1 - np.abs(ax) / np.maximum(w, 1e-3)) * (1 - np.clip(t, 0, 1) ** 1.6)
    v = v - 0.35 * (fbm(rng, S, S, 20, 3) - 0.4) * np.clip(t, 0, 1)
    v = np.minimum(v, np.minimum((1 - t) * 3.0, (t + 0.45) * 3.0))   # nothing past the tip or behind the base
    v = np.clip(v, -1.0, 1.5)                    # (no hard jumps: they'd smear the antialiasing into lines)
    gy, gx = np.gradient(v)
    aa = np.clip(np.hypot(gx, gy) * 1.2, 1e-5, 0.05)
    th = [0.0, 0.08, 0.2, 0.36, 0.55, 0.74]
    rgb = np.zeros((S, S, 3), np.float32)
    rgb[:] = c3(FIRE[0])
    for tt, col in zip(th[1:], FIRE[1:]):
        rgb = over(rgb, c3(col), np.clip((v - tt) / aa + 0.5, 0, 1))
    return rgb, np.clip(v / aa + 0.5, 0, 1)


def torch_head(A):
    """The top of the Torch (the right-hand figure): the solid column gap splits the two."""
    cols = A.sum(0)
    xs = np.where(cols > 0.5)[0]
    mid = (xs.min() + xs.max()) // 2
    lo, hi = mid - (xs.max() - xs.min()) // 5, mid + (xs.max() - xs.min()) // 5
    gap = lo + int(np.argmin(cols[lo:hi]))
    right = A[:, gap:] > 0.5
    ys, xs2 = np.where(right)
    top = ys.min()
    near = xs2[ys < top + 40]
    return gap + int(near.mean()), int(top)


# ---------------------------------------------------------------- the cast

def cast(rd):
    """(premultiplied light, transmission per channel, solid mask) of the cast, at render size."""
    b = load(f"{rd}/{CAST}_black.png")
    w = load(f"{rd}/{CAST}_white.png")
    w0 = np.median(w[:8, :8].reshape(-1, 3), axis=0)   # the white backdrop as tonemapped
    b0 = np.median(b[:8, :8].reshape(-1, 3), axis=0)
    t = np.clip((w - b) / np.maximum(w0 - b0, 1e-3), 0, 1)
    light = np.clip(b - b0 * t, 0, 1)
    solid = np.clip((1 - t.mean(2) - 0.15) / 0.7, 0, 1)
    return light, t, solid


def bbox(mask, thr=0.5):
    ys, xs = np.where(mask > thr)
    return xs.min(), ys.min(), xs.max(), ys.max()


def fit(arr, scale, ox, oy, fill):
    n = int(arr.shape[0] * scale)
    p = resize(arr, n, n)
    shape = (S, S) + arr.shape[2:]
    out = np.full(shape, fill, np.float32)
    xs, ys = max(0, ox), max(0, oy)
    xe, ye = min(S, ox + n), min(S, oy + n)
    out[ys:ye, xs:xe] = p[ys - oy:ye - oy, xs - ox:xe - ox]
    return np.clip(out, 0, 1)


def main():
    rd = sys.argv[1]
    pv = sys.argv[2] if len(sys.argv) > 2 else None
    random.seed(4417)
    seed = lambda k: random.Random(SEEDS.get(k, zlib.crc32(k.encode())))   # each element its own: tuning one moves no other

    img = collage(rd, seed("maps"))
    # the far wall of fire, then a nearer one
    f_rgb, f_a = flames(seed("far"), 0.16, 0.60, 0.58, 0.26, 26, 0.035, 0.9,
                        bands=[(0x3a, 0x08, 0x04), (0x8a, 0x16, 0x08), (0xc2, 0x26, 0x0f), (0xe8, 0x4a, 0x14), (0xff, 0x7a, 0x22), (0xff, 0xa8, 0x40)])
    img = over(img, f_rgb, f_a * 0.92)
    f_rgb, f_a = flames(seed("near"), 0.08, 0.40, 0.42, 0.24, 22, 0.03, 0.8)
    img = over(img, f_rgb, f_a)
    img = np.clip(img + blur(f_rgb * f_a[..., None], 40) * 0.35, 0, 1)   # its heat haze glow
    img = np.clip(img + embers(seed("embers_far"), 260, 0.55) * 0.9, 0, 1)                  # embers far back

    # the cast: the pair (solid parts) scaled so it stands ~78% of the icon tall, feet just past the bottom
    light, t, solid = cast(rd)
    x0, y0, x1, y1 = bbox(solid)
    sc = 0.68 * S / (y1 - y0)
    ox = int(0.50 * S - (x0 + x1) * 0.5 * sc)
    oy = int(0.99 * S - y1 * sc)
    L = fit(light, sc, ox, oy, 0.0)
    T = fit(t, sc, ox, oy, 1.0)
    A = fit(solid, sc, ox, oy, 0.0)
    # lit by the fire: warmer low down and on the side facing it, a hot rim on the edges
    warm = smooth(0.35, 1.0, V)[..., None]
    L = L * (1 - warm * 0.25) + L * warm * c3((255, 150, 90)) * 0.25
    edge = np.clip(A - blur(A, 9), 0, 1) * 2.4
    side = smooth(0.0, 1.0, (blur(A, 30) - np.roll(blur(A, 30), (-14, -10), (0, 1))) * 6 + 0.5)
    rim = np.clip(edge * (0.35 + 0.65 * side), 0, 1)[..., None] * 0.6
    # the Torch's fire, streaming back off its head (behind the head, in front of the wall)
    hx, hy = torch_head(A)
    p_rgb, p_a = None, None
    for dx, dy, hgt, wid, lean in ((0.0, 0.06, 0.30, 0.095, 0.55), (0.006, 0.055, 0.22, 0.08, 0.36),
                                   (0.012, 0.065, 0.18, 0.075, 0.75), (-0.004, 0.055, 0.14, 0.06, 0.22)):
        r_, a_ = plume(seed("plume%.2f" % lean), hx + dx * S, hy + dy * S, hgt * S, wid * S, lean)
        if p_rgb is None: p_rgb, p_a = r_, a_
        else:
            p_rgb = over(p_rgb * p_a[..., None], r_, a_) / np.maximum(np.maximum(p_a, a_), 1e-4)[..., None]
            p_a = np.maximum(p_a, a_)
    img = np.clip(img + blur(p_rgb * p_a[..., None], 50) * 0.5, 0, 1)
    img = over(img, p_rgb, p_a)
    # (a shadow under them first, so the cast doesn't float on the fire)
    sh = blur(np.roll(A, (30, 26), (0, 1)), 24)[..., None] * 0.55
    img = img * (1 - sh)
    img = np.clip(img * T + L, 0, 1)
    img = np.clip(img + rim * c3(FIRE[4]) * 0.85, 0, 1)

    # a low lick of fire in front, over their feet
    f_rgb, f_a = flames(seed("front"), 0.035, 0.12, 0.5, 0.5, 30, 0.02, 1.1)
    img = over(img, f_rgb, f_a)
    img = np.clip(img + embers(seed("embers_near"), 140, 1.0), 0, 1)                        # near embers

    # bloom: the bright parts glow
    hot = np.clip(img - 0.62, 0, 1)
    img = np.clip(img + blur(hot, 10) * 0.9 + blur(hot, 48) * 0.7, 0, 1)
    # vignette
    vg = np.hypot((U - 0.5) / 0.75, (V - 0.48) / 0.8)
    img = img * (1 - smooth(0.45, 1.0, vg) * 0.62)[..., None]

    # the frame: a rounded square, ember-edged (gold at the top to deep ember below), a dark inner line
    rad = 0.19 * S
    margin = 0.035 * S
    qx = np.maximum(np.abs(XX - S / 2 + 0.5) - (S / 2 - margin - rad), 0)
    qy = np.maximum(np.abs(YY - S / 2 + 0.5) - (S / 2 - margin - rad), 0)
    sd = np.hypot(qx, qy) - rad                    # signed distance to the rounded square (<0 inside)
    alpha = np.clip(0.5 - sd, 0, 1)
    edge_col = c3(FIRE[4]) * (1 - V[..., None]) + c3(FIRE[1]) * V[..., None]
    ring = np.clip(0.5 - np.abs(sd + 9) + 9, 0, 1) * np.clip(0.5 - sd, 0, 1)   # 18 px band at the edge
    inner = np.clip(0.5 - np.abs(sd + 21) + 3, 0, 1)                            # 6 px dark line inside it
    img = over(img, c3(CHARCOAL) * 0.6, inner * 0.85)
    img = over(img, edge_col, ring)
    hi = np.clip(0.5 - np.abs(sd + 4) + 1.5, 0, 1) * (1 - V) * 0.6               # a highlight on the top edge
    img = np.clip(img + hi[..., None] * c3(FIRE[5]), 0, 1)
    # outer glow, outside the square
    og = blur(alpha, 18) * (1 - alpha)

    # straight alpha: the square, and the faint ember glow outside it
    ga = og * 0.5 * (1 - alpha)
    tot = np.clip(alpha + ga, 0, 1)
    col = (img * alpha[..., None] + c3(FIRE[2]) * ga[..., None]) / np.maximum(tot, 1e-4)[..., None]
    rgba = np.dstack([col, tot])
    big = Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    big.resize((1024, 1024), Image.LANCZOS).save(OUT)
    print("saved", OUT)
    if pv:
        os.makedirs(pv, exist_ok=True)
        icon = Image.open(OUT)
        for bgc, name in (((30, 30, 34), "dark"), ((236, 236, 240), "light")):
            sheet = Image.new("RGB", (1024 + 256 + 64 + 32 + 16 + 5 * 24, 1024 + 48), bgc)
            x = 24
            for sz in (1024, 256, 64, 32, 16):
                im = icon.resize((sz, sz), Image.LANCZOS)
                sheet.paste(im, (x, 24), im)
                x += sz + 24
            sheet.save(f"{pv}/icon_sheet_{name}.png")


if __name__ == "__main__":
    main()
