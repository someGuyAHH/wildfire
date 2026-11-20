"""
The giant inflatable soccer ball (the Overworld's crater), built in Blender (headless):
    tools/.blender/blender-5.2.4-linux-x64/blender --background --python tools/blender/ball.py -- assets/models/props/soccer_ball.glb [preview.png]

A truncated icosahedron (12 pentagons, 20 hexagons: the classic ball's panels), radius 1 (the
scene scales it). Each panel is puffed like an inflatable: poked at its middle and pushed out to
the sphere, its rim held a little in, a sunk seam strip between panels. Flat-shaded facets for the
vector look. Material slots: white (hexagons), black (pentagons), seam.
"""

import math
import sys

import bmesh
import bpy
from mathutils import Vector

R_MID = 1.0     # a panel's middle
R_RIM = 0.988   # its edge
R_SEAM = 0.972  # the seam between panels
SEAM = 0.035    # seam strip width (inset)


def build():
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0) # an icosahedron
    # cut every corner a third of the way down its edges: pentagons where the corners were
    bmesh.ops.bevel(bm, geom=list(bm.verts), offset=100.0 / 3.0, offset_type="PERCENT", affect="VERTICES", segments=1)
    bm.faces.ensure_lookup_table()
    for v in bm.verts:
        v.co = v.co.normalized() * R_SEAM
    panels = list(bm.faces)
    # the seam: each panel inset, the strips between them are the seam
    res = bmesh.ops.inset_individual(bm, faces=panels, thickness=SEAM, depth=0.0, use_even_offset=True)
    seam_faces = set(res["faces"])
    for f in panels:
        for v in f.verts:
            v.co = v.co.normalized() * R_RIM
    # puff: a vertex in each panel's middle, out at the sphere, and a ring halfway to it
    out = bmesh.ops.poke(bm, faces=panels)
    for v in out["verts"]:
        v.co = v.co.normalized() * R_MID
    kind = {}
    # classify the poked triangles: each has the middle vert; its panel was a pentagon if the middle
    # vert has 5 triangles round it
    for f in bm.faces:
        if f in seam_faces:
            kind[f] = 2
            continue
        mid = [v for v in f.verts if abs(v.co.length - R_MID) < 1e-4]
        kind[f] = 1 if mid and len(mid[0].link_faces) == 5 else 0
    me = bpy.data.meshes.new("SoccerBall")
    bm.to_mesh(me)
    bm.free()
    for name in ("white", "black", "seam"):
        me.materials.append(bpy.data.materials.get(name) or bpy.data.materials.new(name))
    # (to_mesh keeps face order: kinds by index)
    order = list(kind.values())
    for p, k in zip(me.polygons, order):
        p.material_index = k
        p.use_smooth = False
    o = bpy.data.objects.new("SoccerBall", me)
    bpy.context.collection.objects.link(o)
    return o


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    o = build()
    print("ball: %d faces, %d white / %d black panels' triangles" % (
        len(o.data.polygons), sum(1 for p in o.data.polygons if p.material_index == 0),
        sum(1 for p in o.data.polygons if p.material_index == 1)))
    if len(args) > 1:
        cols = {"white": (0.92, 0.92, 0.9), "black": (0.1, 0.1, 0.12), "seam": (0.45, 0.45, 0.48)}
        for m in o.data.materials:
            m.use_nodes = True
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*cols[m.name], 1)
        bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(30)))
        bpy.ops.object.camera_add(location=(2.6, -3.2, 1.6))
        cam = bpy.context.object
        cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc = bpy.context.scene
        sc.camera = cam
        sc.world = bpy.data.worlds.new("w")
        sc.world.use_nodes = True
        sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.65, 0.72, 1)
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 24
        sc.render.resolution_x = sc.render.resolution_y = 600
        sc.render.filepath = args[1]
        bpy.ops.render.render(write_still=True)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=args[0], export_format="GLB", use_selection=True, export_yup=True)
    print("ball exported to", args[0])


if __name__ == "__main__":
    main()
