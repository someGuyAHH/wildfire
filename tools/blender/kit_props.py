"""
The shared obstacle kits' pieces (tools/mapgen/lib/map_kits.gd: ruins, pillars, stilts, kickers,
tower, blocks, vaults, hub), used by the Overworld and the Jungle, built in Blender (headless):
    tools/.blender/blender-5.2.4-linux-x64/blender --background --python tools/blender/kit_props.py -- assets/models/kits/kit_props.glb

The kits' boxes come in random sizes, and posts are stretched down to the terrain when placed,
so every piece is built to be fitted by the generator (MapKit.look, MapGen._emit_boxes):
  "top"  origin at the box's top, centred; the piece reaches far down (the rest is buried), and
         is stretched across (x, z) to the box: walls, pillars, legs, the tower, blocks, the hub
  "fit"  origin at the centre, stretched to the box: decks, ledges, the lintel
  "tile" origin at the centre, one segment of a run, repeated along the box (z) and stretched a
         little to fit: plank walks, ramps, kickers
Each piece's reference size (what "stretched to the box" divides by) is in REF in map_kits.gd.
Material slots by the kits' roles: stone, rock, ruin, wood, ramp, hub. Blender is Z up; Godot
(x, y, z) = Blender (x, z, -y): a piece long along Godot z is long along Blender y.
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inferno_props import Piece, box, cut_corner, extrude, prism  # noqa: E402


def ruin_wall(name, h, width, length=8.0, down=12.0):
    """A broken wall h tall above ground (top origin), width x length: a coping stone along the
    top, the body a touch inset, quoins up both ends (alternating long and short), a string
    course half way, its top corners knocked off at the ends."""
    rng = random.Random(len(name) * 13 + int(h * 10))
    p = Piece(name)
    bottom = -(h + down)
    p.add(box((0, 0, (bottom - 0.22) * 0.5), (width * 0.92, length * 0.96, -bottom - 0.22)), "stone")
    cop = box((0, 0, -0.11), (width, length * 0.94, 0.22), 0.04)
    for sy in (-1, 1): # knocked-off corners at the coping's ends
        if rng.random() < 0.7:
            cut_corner(cop, (0, sy * length * 0.47, -0.02), (rng.uniform(-0.3, 0.3), sy * 0.8, 0.6))
    p.add(cop, "stone")
    if h > 2.0: # a string course half way up
        p.add(box((0, 0, -h * 0.5), (width * 1.01, length * 0.93, 0.18), 0.02), "stone") # (short of the quoins' ends)
    z = -0.22
    k = 0
    while z > bottom: # quoins up both ends
        hh = rng.uniform(0.45, 0.65)
        for sy in (-1, 1):
            long = (k + (1 if sy > 0 else 0)) % 2 == 0
            l = 0.9 if long else 0.55
            p.add(box((0, sy * (length * 0.48 - l * 0.5), z - hh * 0.5), (width * 0.98, l, hh - 0.04), 0.03), "stone")
        z -= hh
        k += 1
    return p.finish()


def lintel():
    """The chimney's lintel, 6 x 1 x 8 (fit): a big beam stone, chamfered, a keystone in the middle."""
    p = Piece("lintel")
    p.add(box((0, 0, 0), (6.0, 8.0, 1.0), 0.08), "stone")
    p.add(box((0, 0, -0.05), (1.2, 8.04, 1.08), 0.04), "stone")
    return p.finish()


def ruin_pillar():
    """A pillar 2.6 square (top origin), any height: a square abacus and a flared capital at the
    top, an octagonal shaft of drums (each chamfered: the joints read) reaching far down."""
    p = Piece("ruin_pillar")
    p.add(box((0, 0, -0.15), (2.6, 2.6, 0.3), 0.04), "ruin")
    p.add(prism((0, 0, -0.75), 1.05, 1.28, 0.45, 8, math.pi / 8, 0.02), "ruin")
    z = -0.75
    rng = random.Random(7)
    while z > -45.0:
        hh = rng.uniform(1.1, 1.6)
        p.add(prism((0, 0, z - hh), 1.1, 1.1, hh - 0.02, 8, math.pi / 8 + rng.uniform(-0.03, 0.03), 0.05), "ruin")
        z -= hh
    return p.finish()


def stilt_deck():
    """A stilt platform, 9 x 1 x 9 (fit): plank boards across, a rim beam round it, two joists and
    knee braces underneath out to the legs (at +-3.8)."""
    p = Piece("stilt_deck")
    n = 10
    for i in range(n): # boards (top at 0.5)
        y = -4.5 + (i + 0.5) * 0.9
        p.add(box((0, y, 0.38), (8.9, 0.86, 0.24), 0.02), "wood")
    for k in range(4): # rim beams
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-d.y, d.x, 0))
        l = 9.0 if abs(d.x) > 0.5 else 8.4 # (two run between the other two: no overlapping corners)
        size = (abs(along.x) * l + abs(d.x) * 0.3, abs(along.y) * l + abs(d.y) * 0.3, 0.5 if abs(d.x) > 0.5 else 0.48)
        p.add(box(d * 4.35 + Vector((0, 0, 0.0)), size, 0.03), "wood")
    for x in (-3.8, 3.8): # joists
        p.add(box((x, 0, -0.15), (0.4, 8.4, 0.5), 0.03), "wood")
    for cx in (-3.8, 3.8):
        for cy in (-3.8, 3.8): # knee braces, leg to joist, under the deck
            b = box((0, 0, 0), (0.22, 0.22, 2.0), 0.02)
            bmesh.ops.rotate(b, verts=b.verts, cent=Vector(), matrix=Matrix.Rotation(math.radians(40) * (1 if cy > 0 else -1), 3, "X"))
            bmesh.ops.translate(b, vec=Vector((cx, cy * 0.78, -1.15)), verts=b.verts)
            p.add(b, "wood")
    return p.finish()


def stilt_leg():
    """A stilt leg 0.8 square (top origin), reaching far down: a chamfered post, iron-strapped
    collars every 3 m."""
    p = Piece("stilt_leg")
    p.add(box((0, 0, -15.0), (0.7, 0.7, 30.0), 0.06), "wood")
    for z in range(1, 10):
        p.add(box((0, 0, -z * 3.0), (0.8, 0.8, 0.2), 0.02), "wood")
    return p.finish()


def plank_run(name, width, thick, role, seg=2.0, boards=4, rails=False):
    """One segment of a plank walk / ramp, width x thick x seg (tile): boards across on two
    stringers, (rails: an edge board up each side)."""
    p = Piece(name)
    for i in range(boards):
        y = -seg * 0.5 + (i + 0.5) * seg / boards
        p.add(box((0, y, thick * 0.5 - 0.1), (width - (0.34 if rails else 0.0), seg / boards - 0.05, 0.2), 0.02), role)
    for x in (-width * 0.36, width * 0.36):
        p.add(box((x, 0, -0.1), (0.24, seg, thick - 0.2), 0.02), role)
    if rails:
        for x in (-width * 0.5 + 0.08, width * 0.5 - 0.08):
            p.add(box((x, 0, thick * 0.5 - 0.05), (0.16, seg, 0.3), 0.02), role)
    return p.finish()


def kicker_trestle():
    """The support under a kicker's lip, 6 wide x 1 deep (top origin), any height: two posts, a
    cap beam, X braces between."""
    p = Piece("kicker_trestle")
    p.add(box((0, 0, -0.15), (6.0, 1.0, 0.3), 0.03), "ramp")
    for x in (-2.7, 2.7):
        p.add(box((x, 0, -5.0), (0.3, 0.3, 10.0), 0.02), "ramp")
    for sgn in (-1, 1):
        b = box((0, 0, 0), (0.18, 0.12, 6.0), 0.02)
        bmesh.ops.rotate(b, verts=b.verts, cent=Vector(), matrix=Matrix.Rotation(math.radians(64) * sgn, 3, "Y"))
        bmesh.ops.translate(b, vec=Vector((0, 0, -1.6)), verts=b.verts)
        p.add(b, "ramp")
    return p.finish()


def kicker_block():
    """The quarter ramp's deck, 6 x 5 (top origin), any height: a boarded timber box, posts at the
    corners, a plank top."""
    p = Piece("kicker_block")
    p.add(box((0, 0, -6.2), (5.7, 4.7, 12.0)), "ramp")
    for i in range(5):
        p.add(box((0, -2.5 + (i + 0.5) * 1.0, -0.1), (6.0, 0.95, 0.2), 0.02), "ramp")
    for cx in (-2.85, 2.85):
        for cy in (-2.35, 2.35):
            p.add(box((cx, cy, -6.21), (0.3, 0.3, 12.0), 0.02), "ramp")
    for z in (-1.4, -3.0):
        for k in range(4): # boarding bands
            a = k * math.pi / 2
            d = Vector((math.cos(a), math.sin(a), 0))
            along = Vector((-d.y, d.x, 0))
            ext = 2.9 if abs(d.x) > 0.5 else 2.4
            size = (abs(along.x) * 5.4 + abs(d.x) * 0.1, abs(along.y) * 4.4 + abs(d.y) * 0.1, 0.25)
            p.add(box(d * ext + Vector((0, 0, z)), size, 0.01), "ramp")
    return p.finish()


def tower_core():
    """A climbing tower's core, 8 x 8 (top origin), any height (reaches far down): the body a touch
    inset, quoins up all four corners, string courses every 6 m, arrow slits, a corbelled band
    under the flat top (pads land up there)."""
    p = Piece("tower_core")
    p.add(box((0, 0, -20.8), (7.8, 7.8, 40.0)), "ruin")
    rng = random.Random(3)
    z = -0.82
    k = 0
    while z > -40.0:
        hh = rng.uniform(0.7, 1.0)
        for cx in (-1, 1):
            for cy in (-1, 1):
                long = (k + (1 if cx * cy > 0 else 0)) % 2 == 0
                lx, ly = (1.4, 0.9) if long else (0.9, 1.4)
                p.add(box((cx * (4.0 - lx * 0.5), cy * (4.0 - ly * 0.5), z - hh * 0.5), (lx, ly, hh - 0.05), 0.03), "ruin")
        z -= hh
        k += 1
    for z in range(1, 7): # string courses
        p.add(box((0, 0, -z * 6.0), (8.04, 8.04, 0.25), 0.02), "ruin") # (2 cm proud of the quoins)
    p.add(box((0, 0, -0.4), (8.0, 8.0, 0.8), 0.04), "ruin") # corbelled band under the top
    for z in range(1, 6): # arrow slits: dark recesses (the inset body is the back; frames stand out)
        for k in range(4):
            a = k * math.pi / 2
            d = Vector((math.cos(a), math.sin(a), 0))
            along = Vector((-d.y, d.x, 0))
            size = (abs(along.x) * 0.5 + abs(d.x) * 0.08, abs(along.y) * 0.5 + abs(d.y) * 0.08, 1.6)
            p.add(box(d * 3.92 + along * (1.2 if k % 2 else -1.2) + Vector((0, 0, -z * 6.0 + 3.0)), size, 0.01), "rock")
    return p.finish()


def tower_ledge():
    """A climbing ledge, 2.8 x 0.6 x 10.8 (fit): a slab with its outer edge chamfered, corbels
    underneath every 2 m."""
    p = Piece("tower_ledge")
    slab = box((0, 0, 0), (2.8, 10.8, 0.6), 0.05)
    cut_corner(slab, (1.4, 0, -0.3), (0.7, 0, -0.7))
    p.add(slab, "ruin")
    for k in range(5):
        y = -4.4 + k * 2.2
        c = box((-0.6, y, -0.6), (1.6, 0.5, 0.6), 0.03)
        cut_corner(c, (0.2, y, -0.9), (0.7, 0, -0.7))
        p.add(c, "ruin")
    return p.finish()


def rock_block(name, seed):
    """A fallen block of rock, 4 x 4 (top origin), any height: a squat mass with its vertical
    edges sheared off at random and a chamfer round the top (a good flat top stays to land on),
    reaching far down."""
    rng = random.Random(seed)
    p = Piece(name)
    bm = box((0, 0, -6.0), (4.0, 4.0, 12.0))
    for cx in (-1, 1):
        for cy in (-1, 1):
            cut = rng.uniform(0.35, 0.8)
            cut_corner(bm, (cx * (2.0 - cut), cy * 2.0, 0), (cx * rng.uniform(0.6, 1.4), cy, 0))
    for k in range(4): # top edges: chamfers of different sizes
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        c = rng.uniform(0.15, 0.4)
        cut_corner(bm, d * (2.0 - c) + Vector((0, 0, 0)), d * 0.7 + Vector((0, 0, 0.7)))
    for _ in range(2): # a face or two sheared a little off vertical
        a = rng.uniform(0, math.tau)
        d = Vector((math.cos(a), math.sin(a), 0))
        cut_corner(bm, d * 1.85 + Vector((0, 0, -3.0)), d + Vector((0, 0, rng.uniform(0.05, 0.15))))
    p.add(bm, "rock")
    return p.finish()


def low_wall():
    """A vault wall, 14 long x 0.8 thick (top origin), any height: a body of stones in courses
    (raised blocks on an inset core), a rounded coping, piers at the ends."""
    rng = random.Random(11)
    p = Piece("low_wall")
    p.add(box((0, 0, -3.2), (13.6, 0.68, 6.0)), "stone")
    p.add(box((0, 0, -0.1), (13.4, 0.8, 0.2), 0.06), "stone")
    z = -0.2
    k = 0
    while z > -6.0: # coursed stones, staggered
        hh = rng.uniform(0.32, 0.42)
        x = -6.8 + (0.4 if k % 2 else 0.0)
        while x < 6.6:
            l = min(rng.uniform(0.7, 1.3), 6.6 - x)
            p.add(box((x + l * 0.5, 0, z - hh * 0.5), (l - 0.05, 0.76, hh - 0.04), 0.03), "stone")
            x += l
        z -= hh
        k += 1
    for sx in (-1, 1):
        p.add(box((sx * 6.8, 0, -3.0 + 0.05), (0.4, 0.8, 6.1), 0.03), "stone")
    return p.finish()


def hub_disc():
    """A launch hub, 14 x 14 (top origin), any height: a platform with a bevelled rim, a round
    launch plate inset in the middle (flush), corner plates, panel ribs down the sides."""
    p = Piece("hub_disc")
    p.add(box((0, 0, -3.25), (13.6, 13.6, 6.0)), "hub")
    rim = box((0, 0, -0.22), (14.0, 14.0, 0.4), 0.12) # (2 cm under the plates: no faces in one plane)
    p.add(rim, "hub")
    p.add(prism((0, 0, -0.38), 5.2, 5.2, 0.4, 24), "rock")   # the launch plate (dark), flush
    p.add(prism((0, 0, -0.37), 4.4, 4.4, 0.4, 24), "hub")
    for cx in (-5.9, 5.9):
        for cy in (-5.9, 5.9):
            p.add(box((cx, cy, -0.19), (1.6, 1.6, 0.4), 0.05), "rock")
    for k in range(4): # ribs down the sides
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-d.y, d.x, 0))
        for f in (-0.33, 0.0, 0.33):
            size = (abs(along.x) * 0.3 + abs(d.x) * 0.2, abs(along.y) * 0.3 + abs(d.y) * 0.2, 6.0)
            p.add(box(d * 6.9 + along * f * 14.0 + Vector((0, 0, -3.0)), size, 0.02), "hub")
    return p.finish()


def hub_ramp():
    """One segment of a hub's ramp, 5 x 0.6 x 2 (tile): a frame with cross slats (a grating)."""
    p = Piece("hub_ramp")
    for x in (-2.35, 2.35):
        p.add(box((x, 0, 0), (0.3, 2.0, 0.6), 0.03), "hub")
    for i in range(5):
        p.add(box((0, -1.0 + (i + 0.5) * 0.4, 0.2), (4.4, 0.22, 0.2), 0.02), "hub")
    p.add(box((0, 0, -0.1), (4.4, 2.0, 0.2)), "rock")
    return p.finish()


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for h in (1.2, 2.6, 4.5, 6.5):
        ruin_wall("ruin_wall_%d" % int(h * 10), h, 1.0)
    ruin_wall("ruin_wall_tall", 9.5, 1.2)
    lintel()
    ruin_pillar()
    stilt_deck()
    stilt_leg()
    plank_run("plank_walk", 2.4, 0.6, "wood")
    plank_run("plank_ramp", 3.0, 0.8, "wood", rails=True)
    plank_run("kicker_deck", 6.0, 0.7, "ramp", boards=5, rails=True)
    kicker_trestle()
    kicker_block()
    tower_core()
    tower_ledge()
    for i in range(3):
        rock_block("rock_block_%d" % i, 100 + i * 17)
    low_wall()
    hub_disc()
    hub_ramp()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_normals=True, export_materials="EXPORT", export_apply=True)
    print("kit props exported to", out, [o.name for o in bpy.data.objects])


main()
