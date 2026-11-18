"""
Renders a map piece exported as OBJ (materials named like the game's: bark, wood, foliage, ...)
with the real textures, CPU, no window:
    blender --background --python tools/blender/preview_obj.py -- piece.obj out.png [distance] [height] [look_y]
"""
import math
import os
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
dist = float(args[2]) if len(args) > 2 else 30.0
cam_h = float(args[3]) if len(args) > 3 else 10.0
look_y = float(args[4]) if len(args) > 4 else 10.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=args[0], forward_axis="NEGATIVE_Z", up_axis="Y")
proj = os.getcwd()
TEX = {
    "bark": ("assets/images/foliage/bark012_color.jpg", "assets/images/foliage/bark012_normal.jpg", 1.0, False),
    "wood": ("assets/images/wood/planks012_color.jpg", "assets/images/wood/planks012_normal.jpg", 0.4, False),
    "foliage": ("assets/images/foliage/twigs.png", None, 1.0, True),
}


def make(name, color, normal, scale, alpha):
    m = bpy.data.materials.new(name + "_preview")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    uv = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(uv.outputs["UV"], mp.inputs["Vector"])
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(proj + "/" + color)
    nt.links.new(mp.outputs["Vector"], img.inputs["Vector"])
    nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(img.outputs["Alpha"], bsdf.inputs["Alpha"])
    if normal:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(proj + "/" + normal)
        n.image.colorspace_settings.name = "Non-Color"
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


mats = {k: make(k, *v) for k, v in TEX.items()}
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    for slot in o.material_slots:
        base = slot.material.name.split(".")[0] if slot.material else ""
        if base in mats:
            slot.material = mats[base]
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.collection.objects.link(cam)
cam.location = (0.0, -dist, cam_h)
cam.rotation_euler = (math.atan2(dist, look_y - cam_h) if False else math.radians(90) - math.atan2(cam_h - look_y, dist), 0, 0)
cam.data.lens = 22
bpy.context.scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(50), math.radians(15), math.radians(35))
bpy.context.collection.objects.link(sun)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.62, 0.72, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
bpy.context.scene.world = world
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 24
sc.render.resolution_x = 960
sc.render.resolution_y = 960
sc.render.filepath = args[1]
bpy.ops.render.render(write_still=True)
