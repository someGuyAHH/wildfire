"""
The Overworld's and the Jungle's landmark pieces (the aqueduct, the mesa's pillars; the temple, its
grand stair, the chutes, the log bridges), built in Blender (headless), one .glb per map (each uses
its own map's roles):
    blender --background --python tools/blender/landmark_props.py -- overworld assets/models/landmarks/overworld_landmarks.glb
    blender --background --python tools/blender/landmark_props.py -- jungle assets/models/landmarks/jungle_landmarks.glb

As with the kits (tools/blender/kit_props.py), each gameplay box keeps its collision and these are
fitted to it by the generator (MapKit.look: "fit" / "top" / "tile"); decorations with no box of
their own (arches, cornices, friezes, door frames) are placed as look-only models. Wall
decorations: origin on the face at its top or bottom edge as noted, standing out toward Godot +z
(Blender -y). Godot (x, y, z) = Blender (x, z, -y).
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inferno_props import Piece, box, cut_corner, extrude, prism, slab_poly  # noqa: E402


# ---- the Overworld ------------------------------------------------------------------------------

def aqueduct_pier():
    """A pier 3 (x) by 4 (z), top origin (the deck's underside), reaching far down: chamfered
    corners, an impost band where the arches spring (5.3 m down), a set-off course every 6 m."""
    p = Piece("aqueduct_pier")
    p.add(box((0, 0, -20.42), (2.84, 3.84, 40.0), 0.1), "stone") # (top under the cap: no faces in one plane)
    p.add(box((0, 0, -0.2), (3.0, 4.0, 0.4), 0.04), "stone")
    p.add(box((0, 0, -5.5), (3.0, 4.0, 0.4), 0.04), "stone")       # the impost (the arches spring at -5.3)
    for z in (-10.5, -16.5, -22.5, -28.5):
        p.add(box((0, 0, z), (3.0, 4.0, 0.3), 0.03), "stone")
    return p.finish()


def aqueduct_arch():
    """The arch between two piers (span 9 between their faces), origin at mid-span on the deck's
    underside, the span along x: a semicircular ring of voussoirs (inner radius 4.5, 0.8 deep)
    springing from the piers' imposts 5.3 m down, its crown just meeting the deck, the keystone
    proud; the spandrels (between the ring, the piers and the deck) filled. 3.6 deep (inside the
    piers' 4)."""
    p = Piece("aqueduct_arch")
    r_in, r_out = 4.5, 5.3
    spring = -r_out
    n = 13
    for k in range(n): # voussoirs, each a wedge of the ring, a hair apart
        a0 = math.pi * k / n + 0.004
        a1 = math.pi * (k + 1) / n - 0.004
        pts = [(math.cos(a0) * r_in, spring + math.sin(a0) * r_in), (math.cos(a0) * r_out, spring + math.sin(a0) * r_out),
               (math.cos(a1) * r_out, spring + math.sin(a1) * r_out), (math.cos(a1) * r_in, spring + math.sin(a1) * r_in)]
        depth = 3.8 if k == n // 2 else 3.6
        p.add(slab_poly(pts, depth * 0.5, -depth * 0.5), "stone")
    # a spandrel: from the pier face (x = 4.5) along the deck to the crown, back down the ring
    a_pier = math.acos(4.5 / r_out)
    arc = [(math.cos(a) * r_out, spring + math.sin(a) * r_out) for a in
           [math.pi * 0.5 - (math.pi * 0.5 - a_pier) * k / 8 for k in range(9)]] # crown -> pier
    right = [(0.0, 0.0), (4.5, 0.0)] + arc[::-1][:-1] # (4.5, 0), down to the ring at the pier, up it to the crown
    right = [(0.0, 0.0), (4.5, 0.0), (4.5, arc[-1][1])] + arc[::-1][1:-1]
    for sx in (1, -1):
        outline = [(sx * x, z) for x, z in right]
        p.add(slab_poly(outline, 1.7, -1.7), "stone")
    return p.finish()


def aqueduct_deck():
    """A deck span 12 x 1 x 5 (fit): the slab, a cornice standing out along both long sides
    under the parapets, dentils under it."""
    p = Piece("aqueduct_deck")
    p.add(box((0, 0, 0.0), (12.0, 5.0, 1.0), 0.03), "stone")
    for sy in (-1, 1):
        p.add(box((0, sy * 2.6, 0.05), (12.0, 0.25, 0.4), 0.03), "stone")
        for k in range(12):
            p.add(box((-5.5 + k, sy * 2.55, -0.25), (0.4, 0.15, 0.2)), "stone")
    return p.finish()


def aqueduct_parapet():
    """A parapet 12 x 0.6 x 0.5 (fit): a row of coping stones, each its own length, a hair apart."""
    rng = random.Random(5)
    p = Piece("aqueduct_parapet")
    x = -6.0
    while x < 5.99:
        l = min(rng.uniform(1.2, 2.0), 6.0 - x)
        if 6.0 - (x + l) < 0.6:
            l = 6.0 - x
        p.add(box((x + l * 0.5, 0, 0), (l - 0.04, 0.5, 0.6), 0.05), "stone")
        x += l
    return p.finish()


def fallen_slab():
    """A segment of a collapsed deck slab, 5 x 0.8 x 3 (tile): split by a crack across it, the two
    halves a little out of line, edges chipped."""
    rng = random.Random(9)
    p = Piece("fallen_slab")
    a = box((0, 0.76, 0), (5.0, 1.46, 0.8), 0.05)
    cut_corner(a, (2.5, 1.49, 0.4), (0.7, 0.4, 0.6))
    p.add(a, "stone")
    b = box((0.05, -0.72, -0.03), (4.9, 1.5, 0.74), 0.05)
    cut_corner(b, (-2.45, -1.47, 0.37), (-0.6, -0.5, 0.6))
    p.add(b, "stone")
    return p.finish()


def mesa_pillar():
    """A rock pillar on the mesa, 3 x 3 (top origin), reaching far down: eroded layers of rock,
    each a slab of its own width and a little off-centre (a hoodoo), the top layer whole."""
    rng = random.Random(21)
    p = Piece("mesa_pillar")
    z = 0.0
    first = True
    while z > -24.0:
        t = rng.uniform(0.8, 1.6)
        w = 3.0 if first else rng.uniform(2.3, 2.95)
        d = 3.0 if first else rng.uniform(2.3, 2.95)
        ox = 0.0 if first else rng.uniform(-0.2, 0.2)
        oy = 0.0 if first else rng.uniform(-0.2, 0.2)
        layer = box((ox, oy, z - t * 0.5), (w, d, t - 0.06), 0.12)
        if not first:
            cut_corner(layer, (ox + w * 0.5, oy + d * 0.5, z), (rng.uniform(0.4, 1), rng.uniform(0.4, 1), rng.uniform(-0.3, 0.3)))
        p.add(layer, "rock")
        z -= t
        first = False
    return p.finish()


# ---- the Jungle ---------------------------------------------------------------------------------

def temple_cornice(length=4.0):
    """A tier's cornice, `length` long (stretched to fit), origin on the tier's face at its top edge:
    a projecting band 0.6 tall out 0.35, a step under it."""
    p = Piece("temple_cornice")
    p.add(box((0, -0.175, -0.3), (length, 0.35, 0.6), 0.04), "temple")
    p.add(box((0, -0.1, -0.75), (length, 0.2, 0.3), 0.02), "temple")
    return p.finish()


def temple_frieze(length=4.0):
    """A carved frieze band, `length` long, origin on the face at the band's top (it hangs under the
    cornice): square glyph panels, each a raised frame round a stepped motif."""
    p = Piece("temple_frieze")
    n = int(round(length / 1.0))
    w = length / n
    for k in range(n):
        x = -length * 0.5 + (k + 0.5) * w
        p.add(box((x, -0.04, -0.95), (w - 0.1, 0.08, 1.1), 0.02), "stone")         # the panel
        p.add(box((x, -0.1, -0.95), (w * 0.55, 0.06, 0.12), 0.01), "temple")       # the motif: a stepped cross
        p.add(box((x, -0.1, -0.95), (0.12, 0.06, 0.6), 0.01), "temple")
        p.add(box((x, -0.12, -0.95), (0.3, 0.05, 0.3), 0.01), "temple")
    return p.finish()


def temple_door(w=6.0, h=4.5):
    """A doorway's frame on the face, origin at the threshold's middle: jambs, and over the opening
    a stepped corbel-arch relief (each course standing out a little further), a glyph lintel."""
    p = Piece("temple_door")
    for sx in (-1, 1):
        p.add(box((sx * (w * 0.5 + 0.4), -0.15, h * 0.5), (0.8, 0.3, h), 0.03), "stone")
    for k in range(4): # corbel steps above the lintel line, narrowing
        cw = w + 1.6 - k * 1.2
        p.add(box((0, -0.1 - k * 0.04, h + 0.25 + k * 0.5), (cw, 0.2 + k * 0.08, 0.48), 0.02), "temple")
    p.add(box((0, -0.25, h + 0.25), (w * 0.5, 0.1, 0.4), 0.01), "stone")
    return p.finish()


def temple_pillar():
    """A summit pillar 2 x 7 x 2 (fit): a base, a shaft with sunk panels, a capital block."""
    p = Piece("temple_pillar")
    p.add(box((0, 0, -3.2), (2.0, 2.0, 0.6), 0.04), "temple")
    p.add(box((0, 0, 0.0), (1.8, 1.8, 5.8), 0.03), "temple")
    for k in range(4):
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-d.y, d.x, 0))
        size = (abs(along.x) * 1.0 + abs(d.x) * 0.06, abs(along.y) * 1.0 + abs(d.y) * 0.06, 4.6)
        p.add(box(d * 0.92, size, 0.01), "stone")
    p.add(box((0, 0, 3.2), (2.0, 2.0, 0.6), 0.04), "temple")
    return p.finish()


def temple_roof():
    """The summit roof, 38.4 x 1 x 38.4 (fit): the slab, a carved edge band round it."""
    p = Piece("temple_roof")
    p.add(box((0, 0, 0.1), (37.8, 37.8, 0.8), 0.03), "temple")
    for k in range(4):
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-d.y, d.x, 0))
        size = (abs(along.x) * 38.4 + abs(d.x) * 0.3, abs(along.y) * 38.4 + abs(d.y) * 0.3, 1.0)
        p.add(box(d * 19.05, size, 0.04), "stone")
    return p.finish()


def hall_pillar():
    """A great pillar in the hall, 2.5 x 12.5 x 2.5 (fit): a stepped base, a shaft carved in
    stacked bands, a capital spreading to full width."""
    p = Piece("hall_pillar")
    p.add(box((0, 0, -5.95), (2.5, 2.5, 0.6), 0.04), "temple")
    p.add(box((0, 0, -5.5), (2.3, 2.3, 0.3), 0.03), "temple")
    z = -5.35
    k = 0
    while z < 4.9:
        hh = 1.1
        w = 2.1 if k % 2 == 0 else 2.2
        p.add(box((0, 0, z + hh * 0.5), (w, w, hh - 0.05), 0.04), "temple" if k % 2 == 0 else "stone")
        z += hh
        k += 1
    p.add(prism((0, 0, 4.9), 1.2, 1.5, 0.75, 4, math.pi / 4), "temple")
    p.add(box((0, 0, 5.95), (2.5, 2.5, 0.6), 0.04), "temple")
    return p.finish()


def temple_ledge():
    """A shaft ledge 6 x 0.6 x 2.4 (fit): a slab, a moulded edge, two corbels under it."""
    p = Piece("temple_ledge")
    s = box((0, 0, 0), (6.0, 2.4, 0.6), 0.05)
    cut_corner(s, (0, -1.2, -0.3), (0, -0.7, -0.7))
    p.add(s, "stone")
    for x in (-1.8, 1.8):
        c = box((x, 0.2, -0.6), (0.5, 1.6, 0.6), 0.03)
        cut_corner(c, (x, -0.6, -0.9), (0, -0.7, -0.7))
        p.add(c, "stone")
    return p.finish()


def grand_stair(rise=28.0, run=45.8, width=10.0, deep=14.0, steps=4):
    """One segment of the temple's grand stair (tile along the ramp: the ramp box is tilted, its
    local z up the slope): `steps` steps cut just under the slope (the collision), level treads,
    risers; a stone balustrade (alfarda) flush with the slope along each side; the body down to
    the box's underside. Built for the ramp's own angle (rise over run)."""
    th = math.atan2(rise, run)
    r = 0.3
    t = r / math.tan(th)
    d = math.hypot(r, t)
    seg = steps * d
    u = (math.cos(th), math.sin(th))   # up the slope (horizontal, vertical) in world terms
    n = (-math.sin(th), math.cos(th))  # the slope's normal
    loc = lambda hx, vy: (hx * u[0] + vy * u[1], hx * n[0] + vy * n[1]) # world -> (along, normal)
    prof = []
    for k in range(steps):
        x0, y0 = k * t, k * r
        prof.append(loc(x0, y0))             # nosing (on the slope)
        prof.append(loc(x0 + t, y0))         # back of the tread
    prof.append(loc(steps * t, steps * r))   # the next nosing
    # recentre along the segment and down onto the box's top face (local y = deep / 2)
    prof = [(s - seg * 0.5, y + deep * 0.5) for s, y in prof]
    prof = prof + [(seg * 0.5, -deep * 0.5), (-seg * 0.5, -deep * 0.5)]
    # (s, y) in the slab's frame: Godot z = s, y = y; Blender y = -s, z = y; extrude across x
    def body(x0, x1, outline, role):
        bm = extrude([(-s, y) for s, y in outline][::-1], x0, x1)
        for v in bm.verts:
            ox, oy, oz = v.co.x, v.co.y, v.co.z
            v.co = Vector((oz, ox, oy))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        p.add(bm, role)
    p = Piece("grand_stair")
    body(-width * 0.5 + 1.0, width * 0.5 - 1.0, prof, "temple")
    rail = [(-seg * 0.5, deep * 0.5), (seg * 0.5, deep * 0.5), (seg * 0.5, -deep * 0.5), (-seg * 0.5, -deep * 0.5)]
    for x0 in (-width * 0.5, width * 0.5 - 1.0):
        body(x0, x0 + 1.0, rail, "stone")
    return p.finish(), seg


def jungle_brazier():
    """The temple's braziers (the Jungle has no iron): a stone pedestal with a carved band, a
    stone bowl, embers heaped in it. Origin at the floor."""
    p = Piece("brazier")
    t = math.pi / 8
    p.add(prism((0, 0, 0), 0.66, 0.6, 0.22, 8, t, 0.02), "stone")
    p.add(prism((0, 0, 0.22), 0.42, 0.38, 2.5, 8, t), "stone")
    p.add(prism((0, 0, 1.4), 0.46, 0.46, 0.2, 8, t, 0.01), "temple")
    p.add(prism((0, 0, 2.72), 0.4, 0.66, 0.28, 8, t, 0.02), "stone")
    p.add(prism((0, 0, 3.0), 0.62, 0.95, 0.46, 8, t), "temple")
    p.add(prism((0, 0, 3.3), 0.8, 0.25, 0.42, 8, t + 0.2), "ember")
    return p.finish()


def chute(width=4.0, thick=0.8, seg=2.0):
    """A segment of a slide chute (tile): smooth boards along it (you slide down these), on cross
    bearers."""
    p = Piece("chute")
    for k in range(5):
        x = -width * 0.5 + (k + 0.5) * width / 5
        p.add(box((x, 0, thick * 0.5 - 0.1), (width / 5 - 0.03, seg, 0.2), 0.02), "wood")
    p.add(box((0, 0, -0.15), (width, 0.4, thick - 0.3), 0.02), "wood")
    return p.finish()


def chute_rail(seg=2.0):
    """A segment of a chute's side wall, 0.5 x 1.6 (tile): boards on edge, a cap."""
    p = Piece("chute_rail")
    for k in range(3):
        p.add(box((0, 0, -0.8 + 0.27 + k * 0.5), (0.4, seg, 0.46), 0.02), "wood")
    p.add(box((0, 0, 0.72), (0.5, seg, 0.16), 0.03), "wood")
    return p.finish()


def log_bridge(seg=2.0):
    """A segment of a log bridge, 2.2 x 1.0 (tile): two logs side by side, their tops hewn flat
    (you walk on them), a lashing round both now and then."""
    p = Piece("log_bridge")
    for x in (-0.55, 0.55):
        log = prism((x, 0, -0.5), 0.55, 0.55, 1.0, 10)
        bmesh.ops.rotate(log, verts=log.verts, cent=Vector((x, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
        bmesh.ops.scale(log, vec=Vector((1.0, seg / 1.0, 1.0)), verts=log.verts)
        cut_corner(log, (x, 0, 0.42), (0, 0, 1)) # hewn flat on top
        p.add(log, "bark")
    return p.finish()


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    which, out = args[0], args[1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if which == "overworld":
        aqueduct_pier()
        aqueduct_arch()
        aqueduct_deck()
        aqueduct_parapet()
        fallen_slab()
        mesa_pillar()
    else:
        temple_cornice()
        temple_frieze()
        temple_door()
        temple_pillar()
        temple_roof()
        hall_pillar()
        temple_ledge()
        _, seg = grand_stair()
        print("grand stair segment: %.4f m" % seg)
        jungle_brazier()
        chute()
        chute_rail()
        log_bridge()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_normals=True, export_materials="EXPORT", export_apply=True)
    print("landmark props exported to", out, [o.name for o in bpy.data.objects])


main()
