"""
Jungle tree models, built in Blender (headless) and exported as one .glb:
    tools/.blender/blender-5.2.4-linux-x64/blender --background --python tools/blender/trees.py -- assets/models/trees/jungle_trees.glb

Objects (all at a reference height of H metres, base at the origin, +Z up in Blender = +Y in Godot):
  tree_0 .. tree_3  a tapered, slightly bent trunk with flared roots and 3-5 branches, a crown of
                    twig cards (assets/images/foliage/twigs.png, a 2 x 2 atlas) round each branch
                    tip and the top
  crown             a crown alone (for the treehouses' and twins' square gameplay trunks), its
                    underside at the origin
Materials: "bark" (uv: around the trunk x along it, ~3 m per texture tile) and "leaves" (uv into the
twig atlas). Leaf normals point out from the crown's middle so it shades as one rounded mass.
Deterministic (fixed seeds). The trunk's radius: R_BASE at the ground (flare up to 1.4x), tapering to
R_TOP at the top: keep in sync with tools/mapgen/jungle_gen.gd (collision boxes).
"""

import math
import random
import sys

import bmesh
import bpy
from mathutils import Vector

H = 24.0          # reference tree height (m); the map scales each instance to its own height
R_BASE = 1.2      # trunk radius at the ground (before the root flare)
R_TOP = 0.45      # trunk radius at the top
SIDES = 12
RINGS = 16
BARK_TILE = 3.0   # metres of trunk per bark texture tile (both ways)
CARD = 5.2        # twig card length (m)


def mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return m


def tube(verts, faces, uvs, path, radii, sides, u_repeat):
    """A tube along `path` (list of Vector), radius per point; appends to verts/faces/uvs (bark)."""
    base = len(verts)
    length = 0.0
    lengths = [0.0]
    for i in range(1, len(path)):
        length += (path[i] - path[i - 1]).length
        lengths.append(length)
    for i, p in enumerate(path):
        fwd = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = fwd.cross(Vector((0, 1, 0)) if abs(fwd.y) < 0.9 else Vector((1, 0, 0))).normalized()
        up = side.cross(fwd).normalized()
        for s in range(sides + 1):
            a = s / sides * math.tau
            verts.append(p + (side * math.cos(a) + up * math.sin(a)) * radii[i])
    for i in range(len(path) - 1):
        for s in range(sides):
            a = base + i * (sides + 1) + s
            b = a + sides + 1
            # wound so the outside is the front (the other way round, Godot culled the outside
            # and you saw the trunks' insides)
            faces.append(((a, b, b + 1, a + 1), 0))
            for (ii, ss) in ((i, s), (i + 1, s), (i + 1, s + 1), (i, s + 1)):
                uvs.append((ss / sides * u_repeat, lengths[ii] / BARK_TILE))


def cards(verts, faces, uvs, normals_at, rng, center, spread, count, crown_mid):
    """Twig cards round a cluster centre: each a quad, stem end near the centre, pointing outward."""
    for _ in range(count):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 0.6) + 0.35)).normalized()
        start = center + d * rng.uniform(0.0, spread * 0.5)
        tip_dir = (d + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(-0.2, 0.5)))).normalized()
        length = CARD * rng.uniform(0.8, 1.2)
        # the card's width direction: across tip_dir, rolled at random
        across = tip_dir.cross(Vector((0, 0, 1)))
        if across.length < 0.1:
            across = Vector((1, 0, 0))
        across.normalize()
        roll = rng.uniform(-0.8, 0.8)
        normal = across.cross(tip_dir).normalized()
        across = (across * math.cos(roll) + normal * math.sin(roll)).normalized()
        w = length * 0.5
        b = len(verts)
        corners = [start - across * w, start + across * w, start + across * w + tip_dir * length, start - across * w + tip_dir * length]
        verts.extend(corners)
        faces.append(((b, b + 1, b + 2, b + 3), 1))
        q = rng.randrange(4) # which twig in the 2 x 2 atlas (blender uv: v up)
        u0, v0 = (q % 2) * 0.5, 0.5 - (q // 2) * 0.5
        uvs.extend([(u0, v0), (u0 + 0.5, v0), (u0 + 0.5, v0 + 0.5), (u0, v0 + 0.5)])
        for c in corners:
            normals_at.append((b + corners.index(c), (c - crown_mid).normalized()))


def shadow_blobs(name, tips, rng):
    """<name>_shadow: a squashed, lumpy ball (20 faces) per leaf cluster, for distant shadows:
    solid, so the shadow map draws it far cheaper than the alpha-cut cards (the map uses it past
    the distance the cards' own shadows stop at)."""
    bm = bmesh.new()
    for tip in tips:
        part = bmesh.new()
        bmesh.ops.create_icosphere(part, subdivisions=1, radius=1.0) # 20 faces: only ever seen as a soft shadow
        r = rng.uniform(3.6, 4.4)
        for v in part.verts:
            j = rng.uniform(0.85, 1.12)
            v.co = Vector((v.co.x * r * j, v.co.y * r * j, v.co.z * r * 0.6 * j)) + tip + Vector((0, 0, 1.4))
        me = bpy.data.meshes.new("tmp")
        part.to_mesh(me)
        part.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    mesh = bpy.data.meshes.new(name + "_shadow")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat("shadow"))
    obj = bpy.data.objects.new(name + "_shadow", mesh)
    bpy.context.collection.objects.link(obj)


def build(name, seed, trunk=True):
    rng = random.Random(seed)
    verts, faces, uvs, leaf_normals = [], [], [], []
    tips = []
    crown_mid = Vector((0, 0, H * 0.92 if trunk else 3.0))
    if trunk:
        lean = Vector((rng.uniform(-0.015, 0.015), rng.uniform(-0.015, 0.015), 0)) # (collision is a straight box: keep near it)
        bend = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0))
        path, radii = [], []
        for i in range(RINGS + 1):
            t = i / RINGS
            p = Vector((0, 0, t * H)) + lean * (t * H) + bend * math.sin(t * math.pi)
            path.append(p)
            r = R_BASE + (R_TOP - R_BASE) * t
            if t < 0.08:
                r *= 1.0 + 0.4 * (1.0 - t / 0.08) # root flare
            radii.append(r)
        tube(verts, faces, uvs, path, radii, SIDES, 3)
        top = path[-1]
        tips.append(top + Vector((0, 0, 1.0)))
        for k in range(rng.randint(5, 7)):
            t = rng.uniform(0.58, 0.88)
            i = int(t * RINGS)
            start = path[i]
            a = rng.uniform(0, math.tau)
            out = Vector((math.cos(a), math.sin(a), rng.uniform(0.5, 1.1))).normalized()
            blen = rng.uniform(5.5, 8.5)
            bp = [start + out * blen * f + Vector((0, 0, -0.6 * math.sin(f * math.pi))) for f in (0.0, 0.35, 0.7, 1.0)]
            br = [radii[i] * 0.55, radii[i] * 0.4, radii[i] * 0.27, radii[i] * 0.15]
            tube(verts, faces, uvs, bp, br, 6, 1)
            tips.append(bp[-1])
        crown_mid = sum(tips, Vector()) / len(tips)
        for tip in tips:
            cards(verts, faces, uvs, leaf_normals, rng, tip, 5.5, rng.randint(15, 19), crown_mid)
    else:
        for k in range(7):
            a = k / 7 * math.tau + rng.uniform(-0.3, 0.3)
            r = 0.0 if k == 0 else rng.uniform(4.0, 7.0)
            tip = Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(1.5, 3.5)))
            tips.append(tip)
        crown_mid = sum(tips, Vector()) / len(tips)
        for tip in tips:
            cards(verts, faces, uvs, leaf_normals, rng, tip, 5.5, rng.randint(15, 19), crown_mid)

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [f for f, _ in faces])
    mesh.materials.append(mat("bark"))
    mesh.materials.append(mat("leaves"))
    for poly, (_, m) in zip(mesh.polygons, faces):
        poly.material_index = m
    uv = mesh.uv_layers.new(name="UVMap")
    # uvs were appended per face corner in face order: assign them loop by loop
    k = 0
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[k]
            k += 1
    # normals: bark smooth, leaves pointing out of the crown
    vnorm = [None] * len(verts)
    for vi, n in leaf_normals:
        vnorm[vi] = n
    mesh.update()
    loop_normals = []
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            loop_normals.append(tuple(vnorm[vi]) if vnorm[vi] is not None else tuple(mesh.vertices[vi].normal))
    mesh.shade_smooth()
    mesh.normals_split_custom_set(loop_normals)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    shadow_blobs(name, tips, random.Random(seed + 7))
    return obj


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for i in range(4):
        build("tree_%d" % i, 1000 + i * 17)
    build("crown", 5000, trunk=False)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_normals=True, export_materials="EXPORT")
    print("trees exported to", out)


main()
