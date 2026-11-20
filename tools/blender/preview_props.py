"""
Renders every piece of a props .glb in a row, flat role colours, CPU (Cycles), no window:
    blender --background --python tools/blender/preview_props.py -- props.glb out.png
For checking shapes before the map uses them (the game's own materials aren't applied).
"""
import math
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
COL = {"stone": (0.42, 0.36, 0.33), "ash": (0.5, 0.49, 0.47), "brim": (0.62, 0.48, 0.24), "iron": (0.2, 0.2, 0.23),
       "gold": (0.85, 0.66, 0.22), "ember": (1.0, 0.35, 0.05), "charwood": (0.3, 0.2, 0.14), "crag": (0.22, 0.18, 0.17),
       "wood": (0.55, 0.42, 0.3), "ramp": (0.86, 0.56, 0.26), "hub": (0.42, 0.62, 0.82), "rock": (0.55, 0.52, 0.48), "ruin": (0.62, 0.58, 0.66),
       "temple": (0.66, 0.64, 0.52), "bark": (0.42, 0.31, 0.21)}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
for m in bpy.data.materials:
    role = m.name.split(".")[0]
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf and role in COL:
        bsdf.inputs["Base Color"].default_value = (*COL[role], 1)
        bsdf.inputs["Roughness"].default_value = 0.7
        if role == "ember":
            bsdf.inputs["Emission Color"].default_value = (1, 0.4, 0.1, 1)
            bsdf.inputs["Emission Strength"].default_value = 4.0
objs = sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: o.name)
for o in objs:
    o.parent = None
    o.location = (0, 0, 0)
    if o.name == "crag":
        o.scale = (6, 6, 8) # an island-ish size
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(35)))
bpy.context.object.data.energy = 3.5
bpy.ops.object.camera_add()
cam = bpy.context.object
cam.data.lens = 50
sc = bpy.context.scene
sc.camera = cam
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.7, 1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 16
sc.render.resolution_x, sc.render.resolution_y = 560, 420
out = args[1].rsplit(".", 1)[0]
for o in objs:
    for q in objs: q.hide_render = q is not o
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    lo.z = max(lo.z, hi.z - 8.0) # pieces reaching far down (buried in the game): frame the top
    mid = (lo + hi) * 0.5
    r = (hi - lo).length * 0.5
    cam.location = mid + Vector((0.75, -1.0, 0.65)).normalized() * r * 3.4
    cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = "%s_%s.png" % (out, o.name)
    bpy.ops.render.render(write_still=True)
