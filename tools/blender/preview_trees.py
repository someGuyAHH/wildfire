"""
Renders a look at the tree models with their real textures (CPU, no window):
    tools/.blender/blender-5.2.4-linux-x64/blender --background --python tools/blender/preview_trees.py -- assets/models/trees/jungle_trees.glb out.png
"""
import math
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
root = "//../../"


def tex_mat(name, color, alpha=False, normal=None):
    old = bpy.data.materials.get(name) # the import's own: rename it out of the way
    if old: old.name = name + "_imported"
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF") or nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.get("Material Output") or nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(bpy.path.abspath(color))
    nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(img.outputs["Alpha"], bsdf.inputs["Alpha"])
    if alpha:
        m.blend_method = "CLIP" if hasattr(m, "blend_method") else None
    if normal:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(bpy.path.abspath(normal))
        n.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])


import os
proj = os.getcwd()
tex_mat("bark", proj + "/assets/images/foliage/bark012_color.jpg", normal=proj + "/assets/images/foliage/bark012_normal.jpg")
tex_mat("leaves", proj + "/assets/images/foliage/twigs.png", alpha=True)
for o in bpy.data.objects: # the export's placeholder materials, slot 0 bark, slot 1 leaves
    if o.type == "MESH":
        for slot in o.material_slots:
            slot.material = bpy.data.materials["leaves" if slot.material and slot.material.name.startswith("leaves_imported") else "bark"]
# line them up
objs = [o for o in bpy.data.objects if o.type == "MESH"]
objs.sort(key=lambda o: o.name)
for i, o in enumerate(objs):
    o.location.x = (i - (len(objs) - 1) / 2) * 16.0
    if o.name.startswith("crown"):
        o.location.z = 12.0
ground = bpy.data.meshes.new("g")
ground.from_pydata([(-80, -40, 0), (80, -40, 0), (80, 60, 0), (-80, 60, 0)], [], [(0, 1, 2, 3)])
gob = bpy.data.objects.new("ground", ground)
bpy.context.collection.objects.link(gob)
gm = bpy.data.materials.new("groundmat")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.35, 0.2, 1)
ground.materials.append(gm)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.collection.objects.link(cam)
cam.location = (0, -62, 14)
cam.rotation_euler = (math.radians(84), 0, 0)
cam.data.lens = 24
bpy.context.scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
bpy.context.collection.objects.link(sun)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.6, 0.75, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
bpy.context.scene.world = world
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 24
sc.render.resolution_x = 1280
sc.render.resolution_y = 640
sc.render.filepath = args[1]
bpy.ops.render.render(write_still=True)
