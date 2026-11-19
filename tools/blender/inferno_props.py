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
  crag                a basalt pillar, unit size (scaled to each island's box): columnar ridges,
                      top edges broken
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
        me = bpy.data.meshes.new("tmp")
        part.to_mesh(me)
        part.free()
        for p in me.polygons:
            p.material_index = idx
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def finish(self):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
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


def platform(name, half):
    """A hanging platform 2*half square, 1 m thick (origin at the centre: z -0.5 .. 0.5)."""
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
    for cx, cy in ((-1, 1), (1, -1)):
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


def crag():
    """A basalt pillar at unit size (origin at the centre, -0.5 .. 0.5 each way; the map scales it
    to each island's box): packed hexagonal columns (columnar jointing, like the Giant's Causeway)
    filling the square footprint, every top at the same height (you land on it: the box's top),
    the rim columns poking out a little past the square by different amounts, and their top edges
    chamfered so the joints read from the side and from above."""
    rng = random.Random(41)
    p = Piece("crag")
    r = 0.15 # hex circumradius (unit space)
    dx, dy = r * math.sqrt(3), r * 1.5
    for j in range(-4, 5):
        for i in range(-4, 5):
            cx = i * dx + (dx * 0.5 if j % 2 else 0.0)
            cy = j * dy
            if abs(cx) > 0.5 + r * 0.3 or abs(cy) > 0.5 + r * 0.3:
                continue
            rim = abs(cx) > 0.5 - r or abs(cy) > 0.5 - r
            rr = r * (rng.uniform(1.0, 1.12) if rim else 1.0)
            col = prism((cx, cy, -0.5), rr, rr, 1.0, 6, math.pi / 6 + rng.uniform(-0.05, 0.05))
            top_edges = [e for e in col.edges if e.verts[0].co.z > 0.499 and e.verts[1].co.z > 0.499]
            bmesh.ops.bevel(col, geom=top_edges, offset=r * 0.18, segments=1, affect="EDGES", clamp_overlap=True)
            p.add(col, "crag")
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
    chain()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_normals=True, export_materials="EXPORT",
                              export_apply=True)
    print("inferno props exported to", out, [o.name for o in bpy.data.objects])


main()
