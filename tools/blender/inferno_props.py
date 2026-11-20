"""
The Inferno's modelled pieces, built in Blender (headless) and exported as one .glb:
    tools/.blender/blender-5.2.4-linux-x64/blender --background --python tools/blender/inferno_props.py -- assets/models/inferno/inferno_props.glb

Each piece stands in for one (or a few) of the map's gameplay boxes, which stay as invisible
collision (tools/mapgen/inferno_gen.gd): so every piece is built to its box's exact size, origin
at the box's centre (braziers: at the floor point), nothing standing proud of the box where a
player would feel the difference. Flat-shaded facets and bevels for the vector look; no uvs: the
map's world_vector materials project their patterns in world space. Material slots are named by
the map's roles (stone, ash, brim, iron, gold, ember, charwood, crag) and the generator gives
each the map's material for that role.

Blender is Z up; glTF (and Godot) Y up: Godot (x, y, z) = Blender (x, z, -y). Pieces long along
Godot z are long along Blender y here.

  tomb_a, tomb_b      3 x 1.4 x 6 sarcophagi: plinth, body, moulding, lid with a cross; b's lid
                      slid aside and a corner broken off
  pew                 14 x 1 x 0.8: seat, backrest, carved ends (backrest on Godot -z: the pews
                      face the altar, +z)
  brazier             pedestal (1 x 3 x 1) + bowl (1.8 wide at 3-3.5 m) + embers; origin at the floor
  column_6, column_8  1.5 m square, 6 / 8 m tall gothic clustered piers (catwalks, galleries)
  column_9w           3 m square, 9 m tall (the column pairs)
  platform_4/5/7      hanging platforms (half size 4 / 5 / 7, 1 m thick): stone deck in an iron
                      band, beams under, chain rings on two corners
  crag                a basalt pillar, unit size (scaled to each island's box): the square split
                      into 7-9 irregular columns, nothing outside the box
  coffin              the cathedral's altar coffin on a bier (6 x 1.5 x 3, long along x)
  chain               1.2 m of chain (4 links), origin at the bottom, along +Y in Godot
Deterministic (fixed seeds).
"""

import math
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROLES = ["stone", "ash", "brim", "iron", "gold", "ember", "charwood", "crag"]


def material(name):
    return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def metric_uvs(bm):
    """UVs in metres, laid along the part's own length (its longest side; up a post): materials
    that read a pattern from UVs (wood: its grain, boards) follow each board whichever way the
    piece is turned. Top and bottom faces: u along the length, v across; side faces: u along the
    length (or across, on its end faces), v up; a part longest upright (posts, legs): u up its
    sides."""
    uvl = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    if not bm.verts:
        return
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
    d = hi - lo
    upright = d.z > max(d.x, d.y)
    along_x = d.x >= d.y
    for f in bm.faces:
        n = f.normal
        top = abs(n.z) >= max(abs(n.x), abs(n.y))
        end = (abs(n.x) > abs(n.y)) == along_x # a face looking along the length
        for loop in f.loops:
            c = loop.vert.co
            a, b = (c.x, c.y) if along_x else (c.y, c.x)
            if upright and not top:
                uv = (c.z, b if not end else a)
            elif top:
                uv = (a, b)
            elif end:
                uv = (b, c.z)
            else:
                uv = (a, c.z)
            loop[uvl].uv = uv


class Piece:
    """Parts (each a bmesh with a role) merged into one object."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.roles = []

    def add(self, part, role):
        if role not in self.roles:
            self.roles.append(role)
        idx = self.roles.index(role)
        metric_uvs(part)
        me = bpy.data.meshes.new("tmp")
        part.to_mesh(me)
        part.free()
        for p in me.polygons:
            p.material_index = idx
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def finish(self):
        # (no welding of touching vertices: separate parts that meet at a corner got welded into
        # flipped faces, black flickering spots)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for r in self.roles:
            me.materials.append(material(r))
        for p in me.polygons:
            p.use_smooth = False # flat facets: the vector look
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(obj)
        return obj


def box(center, size, bevel=0.0, segments=1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0))), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES", clamp_overlap=True)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def prism(center, r_bottom, r_top, height, sides=8, rot=0.0, bevel=0.0):
    """A prism / frustum along z, its bottom at center.z."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r_bottom, radius2=r_top, depth=height)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=Matrix.Rotation(rot, 3, "Z"))
    if bevel > 0:
        rims = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-4]
        bmesh.ops.bevel(bm, geom=rims, offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
    bmesh.ops.translate(bm, vec=Vector(center) + Vector((0, 0, height * 0.5)), verts=bm.verts)
    return bm


def cut_corner(bm, point, normal):
    """Knock a corner off along a plane (keeps the side the normal points away from), refills."""
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(point), plane_no=Vector(normal).normalized(), clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    return bm


# ---- the pieces ---------------------------------------------------------------------------------

def tomb(name, broken):
    """3 x 1.4 x 6 (origin at the centre: z -0.7 .. 0.7)."""
    rng = random.Random(len(name) * 7 + (3 if broken else 0))
    p = Piece(name)
    p.add(box((0, 0, -0.575), (3.0, 6.0, 0.25), 0.05), "stone")       # plinth
    p.add(box((0, 0, -0.06), (2.6, 5.6, 0.8), 0.03), "ash")           # body
    p.add(box((0, 0, 0.33), (2.76, 5.76, 0.1), 0.03), "stone")        # moulding under the lid
    # panels sunk into the body's long sides: a row of three recesses each side (raised frames)
    for sx in (-1, 1):
        for k in (-1, 0, 1):
            p.add(box((sx * 1.31, k * 1.75, -0.08), (0.04, 1.3, 0.5), 0.01), "stone")
    lid = box((0, 0, 0.55), (2.95, 5.95, 0.3), 0.07)
    if broken:
        cut_corner(lid, (1.1, 2.6, 0.55), (1, 0.8, 0.35))
        bmesh.ops.rotate(lid, verts=lid.verts, cent=Vector((0, 0, 0.55)), matrix=Matrix.Rotation(math.radians(5), 3, "Z"))
        bmesh.ops.translate(lid, vec=Vector((0.12, -0.3, 0)), verts=lid.verts)
        # the broken-off piece lying against the plinth
        chunk = box((1.75, 2.4, -0.55), (0.45, 0.6, 0.25), 0.05)
        bmesh.ops.rotate(chunk, verts=chunk.verts, cent=Vector((1.75, 2.4, -0.55)), matrix=Matrix.Rotation(0.5, 3, "Z") @ Matrix.Rotation(0.3, 3, "X"))
        p.add(chunk, "stone")
    p.add(lid, "stone")
    # the cross on the lid (2 cm proud: you land on the lid, not on the cross)
    cx, cy = (0.12, -0.3) if broken else (0.0, 0.0)
    p.add(box((cx, cy - 0.2, 0.71), (0.24, 3.4, 0.03), 0.01), "gold" if not broken else "stone")
    p.add(box((cx, cy + 0.65, 0.715), (1.5, 0.24, 0.04), 0.01), "gold" if not broken else "stone") # (a hair higher: no flicker)
    return p.finish()


def pew():
    """14 x 1 x 0.8 (origin at the centre: z -0.5 .. 0.5); backrest on Blender +y (Godot -z)."""
    p = Piece("pew")
    p.add(box((0, -0.08, -0.03), (13.6, 0.5, 0.08), 0.015), "charwood")          # seat (0.47 m up)
    p.add(box((0, 0.33, 0.2), (13.6, 0.07, 0.5), 0.012), "charwood")             # backrest
    p.add(box((0, 0.31, 0.47), (13.7, 0.12, 0.06), 0.015), "charwood")           # its top rail
    p.add(box((0, -0.3, -0.38), (13.4, 0.06, 0.06), 0.01), "charwood")           # foot bar
    for x in (-6.9, 0.0, 6.9):
        end = box((x, 0.0, 0.0), (0.12 if x else 0.16, 0.8, 1.0), 0.02)
        # the ends' fronts sweep down: cut the front top corner off at a slant
        cut_corner(end, (x, -0.4, 0.2), (0, -0.6, 0.8))
        p.add(end, "charwood")
        if x: # a carved finial on the outer ends
            p.add(prism((x, 0.3, 0.5), 0.07, 0.0, 0.18, 4, math.pi / 4), "charwood")
    return p.finish()


def brazier():
    """Origin at the floor point. Pedestal 1 x 3 x 1, bowl 1.8 wide at 3 .. 3.5 m (turned 45
    degrees like its collision box), embers heaped in it."""
    p = Piece("brazier")
    t = math.pi / 8
    p.add(prism((0, 0, 0), 0.66, 0.6, 0.22, 8, t, 0.02), "stone")            # foot
    p.add(prism((0, 0, 0.22), 0.5, 0.5, 0.16, 8, t, 0.02), "stone")          # torus-ish step
    p.add(prism((0, 0, 0.38), 0.42, 0.38, 2.34, 8, t), "stone")             # shaft (tapering)
    for z in (0.95, 1.95):
        p.add(prism((0, 0, z), 0.46, 0.46, 0.1, 8, t, 0.01), "iron")         # iron bands
    p.add(prism((0, 0, 2.72), 0.4, 0.66, 0.28, 8, t, 0.02), "stone")         # capital
    p.add(prism((0, 0, 3.0), 0.62, 0.98, 0.46, 8, t), "iron")                # the bowl
    p.add(prism((0, 0, 3.44), 1.0, 1.0, 0.07, 8, t, 0.01), "iron")           # its rim
    p.add(prism((0, 0, 3.3), 0.82, 0.25, 0.42, 8, t + 0.2), "ember")         # the embers, heaped
    for k in range(4): # bowl handles / spikes on the rim
        a = k * math.pi / 2 + math.pi / 4
        p.add(prism((math.cos(a) * 0.98, math.sin(a) * 0.98, 3.5), 0.06, 0.0, 0.26, 4), "iron")
    return p.finish()


def column(name, w, h):
    """A gothic clustered pier w x h x w (origin at the centre): square plinth, an octagonal core
    with four colonettes, a flared capital, a square abacus at full width."""
    p = Piece(name)
    z0 = -h * 0.5
    plinth_h, base_h, cap_h, aba_h = 0.22 * w, 0.12 * w, 0.24 * w, 0.12 * w
    p.add(box((0, 0, z0 + plinth_h * 0.5), (w, w, plinth_h), 0.03 * w), "stone")
    p.add(prism((0, 0, z0 + plinth_h), 0.47 * w, 0.43 * w, base_h, 8, math.pi / 8, 0.01 * w), "stone")
    shaft0 = z0 + plinth_h + base_h
    shaft_h = h - plinth_h - base_h - cap_h - aba_h
    p.add(prism((0, 0, shaft0), 0.36 * w, 0.36 * w, shaft_h, 8, math.pi / 8), "stone")
    for k in range(4):
        a = k * math.pi / 2
        p.add(prism((math.cos(a) * 0.33 * w, math.sin(a) * 0.33 * w, shaft0), 0.1 * w, 0.1 * w, shaft_h, 6), "stone")
    p.add(prism((0, 0, shaft0 + shaft_h), 0.42 * w, 0.62 * w, cap_h, 8, math.pi / 8), "stone")
    p.add(box((0, 0, h * 0.5 - aba_h * 0.5), (w, w, aba_h), 0.02 * w), "stone")
    return p.finish()


def platform(name, half, rings=True):
    """A hanging platform 2*half square, 1 m thick (origin at the centre: z -0.5 .. 0.5).
    rings=False: a platform on a column (the pit's), no chain rings."""
    p = Piece(name)
    s = half * 2.0
    p.add(box((0, 0, 0.18), (s - 0.1, s - 0.1, 0.64), 0.06), "brim")        # deck (top at 0.5)
    for k in range(4): # the iron band round it
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-d.y, d.x, 0))
        size = (abs(along.x) * s + abs(d.x) * 0.12, abs(along.y) * s + abs(d.y) * 0.12, 0.55)
        p.add(box(d * (half - 0.04) + Vector((0, 0, 0.1)), size, 0.02), "iron")
    for a in (0.0, math.pi / 2): # two beams crossing underneath, hanging below the box
        b = box((0, 0, -0.42), (s - 0.6, 0.45, 0.5), 0.03)
        bmesh.ops.rotate(b, verts=b.verts, cent=Vector((0, 0, -0.42)), matrix=Matrix.Rotation(a, 3, "Z"))
        p.add(b, "iron")
    # chain rings where the two chains hang (Godot corners (-1,-1), (1,1): Blender y flipped)
    for cx, cy in (((-1, 1), (1, -1)) if rings else ()):
        ring = bmesh.new()
        bmesh.ops.create_cone(ring, cap_ends=True, segments=6, radius1=0.22, radius2=0.22, depth=0.08)
        bmesh.ops.rotate(ring, verts=ring.verts, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
        bmesh.ops.translate(ring, vec=Vector((cx * (half - 0.6), cy * (half - 0.6), 0.62)), verts=ring.verts)
        p.add(ring, "iron")
    # rivets along the band's top
    for k in range(4):
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-d.y, d.x, 0))
        n = max(2, int(s / 1.4))
        for i in range(n):
            f = (i + 0.5) / n - 0.5
            p.add(prism(d * (half + 0.03) + along * f * s + Vector((0, 0, 0.18)), 0.07, 0.05, 0.04, 6), "iron")
    return p.finish()


def _clip(poly, a, b):
    """The part of a 2D polygon on a's side of the bisector of a and b."""
    m = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
    n = (b[0] - a[0], b[1] - a[1])
    side = lambda p: (p[0] - m[0]) * n[0] + (p[1] - m[1]) * n[1]
    out = []
    for i, p in enumerate(poly):
        q = poly[(i + 1) % len(poly)]
        sp, sq = side(p), side(q)
        if sp <= 0:
            out.append(p)
        if (sp <= 0) != (sq <= 0):
            t = sp / (sp - sq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def extrude(outline, z0, z1, bevel=0.0):
    """A 2D outline (counter-clockwise, Blender x, y) as a solid from z0 to z1, its top edges
    chamfered."""
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, z0)) for x, y in outline]
    face = bm.faces.new(verts)
    if face.normal.z > 0:
        face.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    top = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, z1 - z0)), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        rim = [e for e in bm.edges if all(abs(v.co.z - z1) < 1e-5 for v in e.verts)]
        bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
    return bm


def crag():
    """A basalt pillar at unit size (origin at the centre, -0.5 .. 0.5 each way; the map stretches
    it to each island's box). The box's own square split into 7-9 irregular columns (a Voronoi
    of it, columnar jointing) so nothing pokes out of the collision and no edge is left with
    nothing under it; each column a hair inset (the dark joints show), its top edges chamfered,
    every top at the box's top (you land on it), a core filling the joints from below."""
    rng = random.Random(41)
    p = Piece("crag")
    sites = []
    while len(sites) < rng.randint(7, 9):
        q = (rng.uniform(-0.42, 0.42), rng.uniform(-0.42, 0.42))
        if all((q[0] - o[0]) ** 2 + (q[1] - o[1]) ** 2 > 0.26 ** 2 for o in sites):
            sites.append(q)
    square = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
    for i, a in enumerate(sites):
        cell = square
        for j, b in enumerate(sites):
            if i != j:
                cell = _clip(cell, a, b)
        cx = sum(v[0] for v in cell) / len(cell)
        cy = sum(v[1] for v in cell) / len(cell)
        # each column pulled in its own amount (up to ~4% of the island: the outline steps in and
        # out down every side, columnar basalt; never out past the box), and a joint all round
        k = rng.uniform(0.9, 0.985)
        cell = [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in cell]
        p.add(extrude(cell, -0.5, 0.5, rng.uniform(0.015, 0.035)), "crag")
    # a solid core inside the cluster, a hair under the tops: the joints read as dark cracks from
    # above instead of slots down to the lava (inside every column's outer face: k >= 0.9)
    p.add(box((0, 0, -0.003), (0.86, 0.86, 0.994)), "crag")
    return p.finish()


def coffin():
    """The cathedral's altar coffin, in the 6 x 1.5 x 3 box (long along x; origin at the centre,
    z -0.75 .. 0.75): a stone bier filling the footprint, a six-sided coffin on it (narrow head,
    wide shoulders, tapering foot) in charred wood with a gold band and handles, a raised panel
    on the lid with a gold cross, a candle at each corner of the bier."""
    p = Piece("coffin")
    p.add(box((0, 0, -0.6), (6.0, 3.0, 0.3), 0.05), "stone")                    # the bier
    p.add(box((0, 0, -0.43), (5.7, 2.7, 0.06), 0.02), "stone")                  # its moulding
    outline = [(2.7, -0.7), (1.55, -1.1), (-2.7, -0.62), (-2.7, 0.62), (1.55, 1.1), (2.7, 0.7)]
    outline = outline[::-1] # counter-clockwise
    grow = lambda o, k: [(x * k, y * k) for x, y in o]
    p.add(extrude(outline, -0.4, 0.36, 0.02), "charwood")                       # the box
    p.add(extrude(grow(outline, 1.025), 0.3, 0.38, 0.01), "gold")              # gold band under the lid
    p.add(extrude(grow(outline, 1.04), 0.38, 0.56, 0.05), "charwood")           # the lid
    p.add(extrude(grow(outline, 0.82), 0.56, 0.7, 0.03), "charwood")            # its raised panel
    p.add(box((0.15, 0, 0.715), (2.6, 0.2, 0.03), 0.008), "gold")               # the cross, long arm
    p.add(box((0.85, 0, 0.72), (0.2, 1.1, 0.04), 0.008), "gold")                # and short (a hair higher)
    for x in (-1.6, -0.2, 1.2): # handles, three a side
        for sy in (-1, 1):
            w = 0.62 + (x + 2.7) / 4.25 * 0.48 # the side's half width there
            p.add(box((x, sy * (w + 0.06), -0.05), (0.42, 0.05, 0.06), 0.01), "gold")
            for dx in (-0.18, 0.18):
                p.add(box((x + dx, sy * (w + 0.03), -0.05), (0.05, 0.07, 0.06)), "gold")
    for cx, cy in ((2.75, 1.25), (2.75, -1.25), (-2.75, 1.25), (-2.75, -1.25)):
        p.add(prism((cx, cy, -0.45), 0.11, 0.11, 0.05, 8), "gold")              # candle dish
        p.add(prism((cx, cy, -0.4), 0.07, 0.065, 0.42, 8), "ash")                # the candle
        p.add(prism((cx, cy, 0.02), 0.035, 0.0, 0.12, 6), "ember")               # its flame
    return p.finish()


def chain():
    """1.2 m of chain: 4 links (each 0.3 m pitch), alternating 90 degrees; origin at the bottom,
    along Blender +z (Godot +y)."""
    p = Piece("chain")
    for k in range(4):
        link = bmesh.new()
        # a link: a flat octagon ring, stretched long
        outer = bmesh.ops.create_circle(link, cap_ends=False, segments=8, radius=0.09)["verts"]
        bmesh.ops.scale(link, vec=Vector((1.0, 1.9, 1.0)), verts=link.verts)
        ext = bmesh.ops.extrude_edge_only(link, edges=list(link.edges))
        verts = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.scale(link, vec=Vector((0.6, 0.8, 1.0)), verts=verts)
        ext2 = bmesh.ops.extrude_face_region(link, geom=list(link.faces))
        verts2 = [v for v in ext2["geom"] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.translate(link, vec=Vector((0, 0, 0.04)), verts=verts2)
        bmesh.ops.recalc_face_normals(link, faces=link.faces)
        bmesh.ops.translate(link, vec=Vector((0, 0, -0.02)), verts=link.verts)
        # stand it up: long axis along z, every other one turned 90 degrees about z
        bmesh.ops.rotate(link, verts=link.verts, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
        if k % 2:
            bmesh.ops.rotate(link, verts=link.verts, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, "Z"))
        bmesh.ops.translate(link, vec=Vector((0, 0, 0.15 + k * 0.3)), verts=link.verts)
        p.add(link, "iron")
    return p.finish()


# ---- wall dressing and fittings --------------------------------------------------------------
# Wall pieces: origin on the wall's face at floor level (y 0), centred along it; they stand out
# from the face toward Godot +z (Blender -y). Shallow on the inside faces (players run and slide
# along those walls; the pieces have no collision), deeper outside where no one touches them.

def slab_poly(outline_xz, y0, y1, bevel=0.0):
    """A 2D outline in the Blender x-z plane (a wall's face), thickened from y0 to y1 (y0 > y1:
    standing out toward -y)."""
    bm = extrude([(x, z) for x, z in outline_xz], 0.0, abs(y1 - y0), bevel)
    # extrude() builds along +z: turn it so the outline's second axis is z and depth runs along -y
    bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, vec=Vector((0, y0, 0)), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def pilaster(name, h):
    """An inside-face pilaster h tall: a base, a flat shaft with a sunk groove, a capital. Stands
    out at most 0.22 m."""
    p = Piece(name)
    p.add(box((0, -0.11, 0.4), (1.9, 0.22, 0.8), 0.04), "stone")
    p.add(box((0, -0.06, h * 0.5), (1.4, 0.12, h - 1.4), 0.02), "stone")
    for x in (-0.35, 0.35): # two raised fillets up the shaft (the groove between them reads)
        p.add(box((x, -0.13, h * 0.5), (0.22, 0.06, h - 1.6), 0.01), "stone")
    p.add(box((0, -0.12, h - 0.45), (1.8, 0.24, 0.5), 0.03), "stone")
    p.add(box((0, -0.11, h - 0.1), (2.0, 0.22, 0.2), 0.02), "stone")
    return p.finish()


def buttress(name, bottom, top):
    """An outside-face buttress from bottom to top (y), stepping in twice, each step capped with a
    sloped weathering."""
    p = Piece(name)
    steps = [(2.6, 1.8, bottom, bottom + (top - bottom) * 0.45), (2.1, 1.2, None, bottom + (top - bottom) * 0.78), (1.6, 0.6, None, top)]
    z = bottom
    for w, d, _, z1 in steps:
        p.add(box((0, -d * 0.5, (z + z1) * 0.5), (w, d, z1 - z), 0.03), "stone")
        cap = box((0, -d * 0.5, z1 + 0.2), (w + 0.1, d + 0.05, 0.4), 0.03)
        cut_corner(cap, (0, -d - 0.05, z1 + 0.05), (0, -0.7, 0.7)) # sloped: rain runs off it
        p.add(cap, "stone")
        z = z1 + 0.4
    return p.finish()


def cornice(name, length=4.0):
    """A cornice band `length` long (scaled to fit): three stepped mouldings, 1.2 m tall, out 0.5 m."""
    p = Piece(name)
    for z0, z1, d in ((0.0, 0.5, 0.2), (0.5, 0.9, 0.35), (0.9, 1.2, 0.5)):
        p.add(box((0, -d * 0.5, (z0 + z1) * 0.5), (length, d, z1 - z0), 0.02), "stone")
    for k in range(int(length / 1.0)): # dentils under the top step
        p.add(box((-length * 0.5 + 0.5 + k, -0.42, 0.82), (0.35, 0.14, 0.16)), "stone")
    return p.finish()


def base_course(name, length=4.0):
    """A plinth band along a wall's foot, `length` long: 0.9 m tall, out 0.15, its top chamfered."""
    p = Piece(name)
    b = box((0, -0.075, 0.45), (length, 0.15, 0.9))
    cut_corner(b, (0, -0.15, 0.82), (0, -0.6, 0.8))
    p.add(b, "stone")
    return p.finish()


def door_arch(name, w=12.0, h=12.0, depth=0.3):
    """A pointed gothic arch round a w x h doorway (whose top is square: the wall's lintel): jambs
    up both sides, an arch band springing from them (two arcs, apex ~10 m over the lintel), a
    keystone, and the tympanum between lintel and arch in the gilded trim."""
    p = Piece(name)
    jw = 0.8
    span = w + jw * 2.0 # outer span
    R = span * 0.8
    def side(radius):
        pts = []
        cx = -span * 0.5 + R
        for k in range(11):
            # from the springer (angle pi) up toward the apex where x = 0
            amax = math.acos(-cx / radius) # the angle at which this arc reaches x = 0 (the apex)
            a = math.pi - (math.pi - amax) * k / 10
            pts.append((cx + math.cos(a) * radius, h + math.sin(a) * radius))
        return pts
    outer = side(R)
    inner = side(R - jw)
    band_l = outer + inner[::-1]
    band_r = [(-x, z) for x, z in band_l][::-1]
    p.add(slab_poly(band_l, 0.0, -depth, 0.03), "stone")
    p.add(slab_poly(band_r, 0.0, -depth, 0.03), "stone")
    for sx in (-1, 1): # jambs
        p.add(box((sx * (w * 0.5 + jw * 0.5), -depth * 0.5, h * 0.5), (jw, depth, h), 0.03), "stone")
        p.add(box((sx * (w * 0.5 + jw * 0.5), -depth * 0.6, h - 0.3), (jw + 0.2, depth * 1.2, 0.6), 0.03), "stone") # impost
    apex = outer[-1][1]
    p.add(box((0, -depth * 0.6, apex - 0.6), (1.0, depth * 1.2, 1.4), 0.04), "stone") # keystone
    tymp = [(-w * 0.5, h)] + [(x, max(z, h)) for x, z in inner[1:]] + [(-x, max(z, h)) for x, z in inner[1:][::-1]] + [(w * 0.5, h)]
    p.add(slab_poly(tymp, 0.0, -0.06), "brim")
    return p.finish()


def corbel(name):
    """A bracket under a gallery: origin on the wall face at the slab's underside; 1 m wide, out
    1.5 m, 1.5 m deep down, its underside a quarter-round in three facets."""
    p = Piece(name)
    prof = [(0.0, 0.0), (-1.5, 0.0), (-1.45, -0.35), (-1.15, -0.85), (-0.6, -1.3), (0.0, -1.5)] # (out, down)
    bm = extrude([(y, z) for y, z in prof], -0.5, 0.5, 0.02)
    # outline is in x-y of extrude(): map its x -> Blender y, its y -> Blender z, its z -> Blender x
    for v in bm.verts:
        ox, oy, oz = v.co.x, v.co.y, v.co.z
        v.co = Vector((oz, ox, oy))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.add(bm, "stone")
    return p.finish()


def balustrade(name, length=2.0):
    """A parapet segment, the rails' 0.6 x 1.1 box `length` long (origin at the centre, along Godot
    z = Blender -y): base, handrail, three turned balusters. Tiled along each rail."""
    p = Piece(name)
    p.add(box((0, 0, -0.46), (0.6, length, 0.18), 0.03), "iron")
    p.add(box((0, 0, 0.48), (0.6, length, 0.14), 0.04), "iron")
    for k in range(3):
        y = -length * 0.5 + length * (k + 0.5) / 3
        p.add(prism((0, y, -0.37), 0.13, 0.17, 0.22, 8, math.pi / 8), "iron")
        p.add(prism((0, y, -0.15), 0.17, 0.09, 0.3, 8, math.pi / 8), "iron")
        p.add(prism((0, y, 0.15), 0.09, 0.14, 0.26, 8, math.pi / 8), "iron")
    return p.finish()


def bridge_post():
    """A chain bridge's post, 0.3 x 2.5 x 0.3 (origin at the centre): a flanged foot, a square
    shaft, a ring for the chain, a spiked finial."""
    p = Piece("bridge_post")
    p.add(box((0, 0, -1.15), (0.42, 0.42, 0.2), 0.03), "iron")
    p.add(box((0, 0, 0.0), (0.24, 0.24, 2.3), 0.02), "iron")
    p.add(prism((0, 0, 1.05), 0.2, 0.2, 0.12, 8), "iron")
    p.add(prism((0, 0, 1.17), 0.12, 0.0, 0.4, 4, math.pi / 4), "iron")
    return p.finish()


def altar():
    """The apse altar, 12 x 2 x 6 (origin at the centre): a plinth, a body of blind gothic panels
    on the long sides, an overhanging mensa slab; a gilded cross and candlesticks at the back."""
    p = Piece("altar")
    p.add(box((0, 0, -0.85), (12.0, 6.0, 0.3), 0.04), "stone")
    p.add(box((0, 0, -0.05), (11.2, 5.2, 1.3), 0.03), "stone")
    for sy in (-1, 1):
        for k in range(5):
            x = -4.4 + k * 2.2
            p.add(box((x, sy * 2.62, -0.05), (1.6, 0.06, 1.0), 0.01), "brim")
    p.add(box((0, 0, 0.85), (12.0, 6.0, 0.3), 0.06), "stone")
    # the cross and candles at the back (Godot +z: toward the apse wall; Blender -y)
    p.add(box((0, -2.2, 1.6), (0.18, 0.18, 1.2), 0.02), "gold")
    p.add(box((0, -2.2, 1.85), (0.8, 0.16, 0.16), 0.02), "gold")
    for x in (-4.5, -2.5, 2.5, 4.5):
        p.add(prism((x, -2.3, 1.0), 0.16, 0.08, 0.1, 8), "gold")
        p.add(prism((x, -2.3, 1.1), 0.05, 0.05, 0.5, 8), "gold")
        p.add(prism((x, -2.3, 1.6), 0.07, 0.06, 0.3, 8), "ash")
        p.add(prism((x, -2.3, 1.9), 0.035, 0.0, 0.12, 6), "ember")
    return p.finish()


def reliquary():
    """The hidden room's prize, 0.9 x 1 x 0.9 (origin at the centre): a little gilded house, a
    pitched roof, a cross on the ridge."""
    p = Piece("reliquary")
    p.add(box((0, 0, -0.43), (0.9, 0.9, 0.14), 0.02), "gold")
    p.add(box((0, 0, -0.1), (0.72, 0.72, 0.52), 0.015), "gold")
    roof = [(-0.42, 0.0), (0.42, 0.0), (0.0, 0.3)][::-1]
    bm = extrude(roof, -0.4, 0.4, 0.01)
    for v in bm.verts: v.co = Vector((v.co.x, v.co.z, v.co.y + 0.16))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    p.add(bm, "gold")
    # the cross: one cross-shaped solid (two overlapping bars flickered where they cross)
    cross = [(-0.02, 0.42), (0.02, 0.42), (0.02, 0.51), (0.06, 0.51), (0.06, 0.55), (0.02, 0.55), (0.02, 0.58),
             (-0.02, 0.58), (-0.02, 0.55), (-0.06, 0.55), (-0.06, 0.51), (-0.02, 0.51)]
    p.add(slab_poly(cross, 0.02, -0.02), "gold")
    return p.finish()


def pedestal(name, w, h):
    """A moulded pedestal w x h x w (origin at the centre): base, a waisted die, a cap."""
    p = Piece(name)
    p.add(box((0, 0, -h * 0.5 + h * 0.08), (w, w, h * 0.16), 0.03), "stone")
    p.add(box((0, 0, -h * 0.5 + h * 0.2), (w * 0.9, w * 0.9, h * 0.08), 0.02), "stone")
    p.add(box((0, 0, 0.0), (w * 0.8, w * 0.8, h * 0.6), 0.03), "stone")
    for k in range(4): # a sunk panel on each face (a raised frame)
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-d.y, d.x, 0))
        size = (abs(along.x) * w * 0.55 + abs(d.x) * 0.04, abs(along.y) * w * 0.55 + abs(d.y) * 0.04, h * 0.4)
        p.add(box(d * w * 0.41, size, 0.01), "brim" if w > 4 else "stone")
    p.add(box((0, 0, h * 0.5 - h * 0.2), (w * 0.9, w * 0.9, h * 0.08), 0.02), "stone")
    p.add(box((0, 0, h * 0.5 - h * 0.08), (w, w, h * 0.16), 0.03), "stone")
    return p.finish()


def dais():
    """The crypt's dais, 14 x 3 x 14 (origin at the centre), in ash stone: a base course, a blind
    arcade of panels round the sides, a lip at the top edge, low corner posts."""
    p = Piece("dais")
    p.add(box((0, 0, -1.3), (14.0, 14.0, 0.4), 0.04), "ash")
    p.add(box((0, 0, 0.0), (13.6, 13.6, 2.2), 0.03), "ash")
    for k in range(4):
        a = k * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-d.y, d.x, 0))
        for i in range(5):
            f = (i - 2) * 2.5
            size = (abs(along.x) * 1.8 + abs(d.x) * 0.06, abs(along.y) * 1.8 + abs(d.y) * 0.06, 1.5)
            p.add(box(d * 6.82 + along * f + Vector((0, 0, -0.1)), size, 0.01), "stone")
    p.add(box((0, 0, 1.35), (14.0, 14.0, 0.3), 0.05), "ash")
    for cx in (-6.62, 6.62):
        for cy in (-6.62, 6.62): # 2 cm proud of the lip and base all round, and over the top:
            # faces in one plane with theirs flickered
            p.add(box((cx, cy, 0.02), (0.84, 0.84, 3.04), 0.04), "stone")
    return p.finish()


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tomb("tomb_a", False)
    tomb("tomb_b", True)
    pew()
    brazier()
    column("column_6", 1.5, 6.0)
    column("column_8", 1.5, 8.0)
    column("column_9w", 3.0, 9.0)
    for h in (4, 5, 7):
        platform("platform_%d" % h, float(h))
    crag()
    coffin()
    chain()
    # the rest of the Inferno (walls, fittings, the pit)
    pilaster("pilaster_30", 30.0)
    buttress("buttress", -16.0, 26.0)
    cornice("cornice")
    base_course("base_course")
    door_arch("door_arch")
    corbel("corbel")
    balustrade("balustrade")
    bridge_post()
    altar()
    reliquary()
    pedestal("plinth", 9.0, 7.0)
    pedestal("prize_plinth", 2.0, 1.5)
    dais()
    column("spire_column", 8.0, 34.9)
    column("pit_column", 2.0, 22.9)
    platform("platform_6r", 6.0, rings=False)
    platform("platform_9r", 9.0, rings=False)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_normals=True, export_materials="EXPORT",
                              export_apply=True)
    print("inferno props exported to", out, [o.name for o in bpy.data.objects])


if __name__ == "__main__": # (tools/blender/kit_props.py imports the helpers)
    main()
