"""
The runner: every character's body (player and bots), built in Blender (headless) on Quaternius's
Universal Animation Library rig (CC0, tools/blender/sources/ual/) and exported with its clips:
    tools/.blender/blender-5.2.4-linux-x64/blender --background --python tools/blender/runner.py -- assets/models/characters/runner.glb [preview.png]

Look (owner's pick, 2026-11-20, "A, the runner"): an athletic freerunner in the vector style. Flat
shaded facets, flat colour regions. A sealed helmet with one glowing visor band, a fitted jacket
with a chest panel, tapered joggers, gloves, grippy flat-soled shoes, a small back unit (where the
Torch's fire sits). References: freerunning kit (fitted top, joggers cuffed at the ankle, flat
rubber-soled shoes, thin gloves) and sealed sci-fi helmets with a single visor band; proportions
are the library mannequin's (1.83 m, ~7.5 heads), which every clip is made for.

Built as an articulated figure: each part is bound wholly to one bone (no soft skinning), so the
facets stay crisp in every pose and the joints are covered by balls and overlaps. Material slots
by role, coloured by the game (src/character/runner_body.gd):
  suit    the jacket, sleeves, shoe uppers (light; tinted per role)
  dark    joggers, gloves, under layers
  accent  chest panel, stripes, cuffs, crest (the role colour: Torch red, Kindling grey...)
  visor   the helmet's band (emissive)
  sole    shoe soles

Clips: from UAL1 as they are (same rig): Idle_Loop, Jog_Fwd_Loop, Sprint_Loop, Jump_Start,
Jump_Loop, Jump_Land, Roll, Hit_Head, Hit_Chest. From UAL2 (another rig, the same mannequin)
retargeted bone by bone: Slide_Start, Slide_Loop, Slide_Exit, NinjaJump_Start,
NinjaJump_Idle_Loop, NinjaJump_Land. Made here from those: Dash (a sprint stride, leant hard into
it), Slam (the ninja jump's airborne tuck, pitched to look down), Dizzy_Loop (UAL1's walk, twice
over, with a swaying, slumped, arms-out stagger layered on: plays as long as you're dizzy),
Frozen_Loop (the idle with a flinch held over it and a fine shiver: frozen by a tag or a bump).

Blender is Z up and the rig faces -Y; in glTF / Godot (Y up) that's facing +Z, so the game turns
the model half round to face the character's forward (-Z).
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
UAL1 = os.path.join(HERE, "sources", "ual", "ual1_standard.glb")
UAL2 = os.path.join(HERE, "sources", "ual", "ual2_standard.glb")
KEEP_UAL1 = ["Walk_Loop", "Idle_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Jump_Start", "Jump_Loop", "Jump_Land", "Roll", "Hit_Head", "Hit_Chest", "A_TPose"]
FROM_UAL2 = ["Slide_Start", "Slide_Loop", "Slide_Exit", "NinjaJump_Start", "NinjaJump_Idle_Loop", "NinjaJump_Land"]
# UAL2's (Unreal-style) bone -> UAL1's (Rigify-style)
BONE_MAP = {"pelvis": "DEF-hips", "spine_01": "DEF-spine.001", "spine_02": "DEF-spine.002", "spine_03": "DEF-spine.003",
            "neck_01": "DEF-neck", "Head": "DEF-head"}
for s, S in (("l", "L"), ("r", "R")):
    BONE_MAP.update({f"clavicle_{s}": f"DEF-shoulder.{S}", f"upperarm_{s}": f"DEF-upper_arm.{S}",
                     f"lowerarm_{s}": f"DEF-forearm.{S}", f"hand_{s}": f"DEF-hand.{S}", f"thigh_{s}": f"DEF-thigh.{S}",
                     f"calf_{s}": f"DEF-shin.{S}", f"foot_{s}": f"DEF-foot.{S}", f"ball_{s}": f"DEF-toe.{S}"})
PREVIEW_COL = {"suit": (0.86, 0.87, 0.9), "dark": (0.17, 0.18, 0.21), "accent": (0.3, 0.62, 1.0),
               "visor": (0.35, 0.92, 1.0), "sole": (0.93, 0.9, 0.82)}


# ---- shapes (bmesh, rest pose: T-pose, facing -Y, Z up) ------------------------------------------

def _bm_box(center, size, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal(Vector((*size, 1.0))), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def _ring(w, d, chamfer, z, y0=0.0):
    """A chamfered rectangle (octagon) at height z: half-width w (x), half-depth d (y)."""
    c = chamfer
    return [Vector(p) for p in ((w - c, -d, z), (w, -d + c, z), (w, d - c, z), (w - c, d, z),
                                (-w + c, d, z), (-w, d - c, z), (-w, -d + c, z), (-w + c, -d, z))]


def loft(sections, y0=0.0):
    """A faceted body through chamfered sections [(z, half_w, half_d), ...], capped."""
    bm = bmesh.new()
    rings = []
    for z, w, d in sections:
        rings.append([bm.verts.new(p + Vector((0, y0, 0))) for p in _ring(w, d, min(w, d) * 0.38, z)])
    for a, b in zip(rings, rings[1:]):
        for i in range(8):
            j = (i + 1) % 8
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def tube(a, b, r1, r2, sides=7, rot=0.0):
    """A faceted tapered prism from a to b (radius r1 at a, r2 at b), capped."""
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r1, radius2=r2, depth=(b - a).length)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=Matrix.Rotation(rot, 3, "Z"))
    q = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
    bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=q.to_matrix())
    bmesh.ops.translate(bm, vec=(a + b) * 0.5, verts=bm.verts)
    return bm


def ball(c, r, sx=1.0, sy=1.0, sz=1.0, seg=8, rings=5):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal(Vector((sx, sy, sz, 1.0))), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    return bm


def band(center, rx, ry, z0, z1, a0, a1, out=0.012, steps=8):
    """A curved band round an ellipse (rx, ry) between angles a0..a1 (0 = facing -Y), z0..z1,
    standing `out` proud of it: the visor."""
    bm = bmesh.new()
    cols = []
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * k / steps
        dirv = Vector((math.sin(a), -math.cos(a), 0))
        col = []
        for z in (z0, z1):
            for o in (0.0, out):
                col.append(bm.verts.new(Vector(center) + Vector((dirv.x * (rx + o), dirv.y * (ry + o), z))))
        cols.append(col) # in-low, out-low, in-high, out-high
    for a, b in zip(cols, cols[1:]):
        bm.faces.new((a[1], b[1], b[3], a[3])) # front
        bm.faces.new((a[3], b[3], b[2], a[2])) # top
        bm.faces.new((a[0], b[0], b[1], a[1])) # bottom
    for c in (cols[0], cols[-1]):
        bm.faces.new((c[0], c[1], c[3], c[2]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ---- the body ------------------------------------------------------------------------------------

def parts():
    """[(bmesh, role, bone)]: the runner in the rig's rest pose."""
    P = []
    add = lambda bm, role, bone: P.append((bm, role, bone))
    # head: helmet, visor band, crest, ear pods
    add(ball((0, 0.004, 1.69), 0.118, 1.0, 1.06, 1.12, seg=10, rings=7), "suit", "DEF-head")
    add(band((0, 0.004, 0.0), 0.119, 0.126, 1.663, 1.712, -1.25, 1.25), "visor", "DEF-head")
    add(_bm_box((0, 0.0, 1.818), (0.034, 0.17, 0.018), 0.006), "accent", "DEF-head")
    for s in (-1, 1):
        add(tube((s * 0.108, 0.01, 1.68), (s * 0.132, 0.01, 1.68), 0.036, 0.03, sides=8), "dark", "DEF-head")
    # neck and collar
    add(tube((0, 0.008, 1.47), (0, -0.002, 1.6), 0.06, 0.055), "dark", "DEF-neck")
    add(loft([(1.455, 0.118, 0.102), (1.5, 0.098, 0.086), (1.545, 0.078, 0.07)]), "suit", "DEF-spine.003")
    # torso: pelvis, belt, abdomen, chest (overlapping so a bend doesn't open a gap)
    add(loft([(0.835, 0.165, 0.105), (0.92, 0.172, 0.112), (1.0, 0.158, 0.104)]), "dark", "DEF-hips")
    add(loft([(0.975, 0.164, 0.11), (1.025, 0.164, 0.11)]), "dark", "DEF-hips")
    add(loft([(0.99, 0.152, 0.1), (1.1, 0.158, 0.106), (1.2, 0.168, 0.112)]), "suit", "DEF-spine.001")
    add(loft([(1.17, 0.17, 0.114), (1.25, 0.185, 0.122), (1.33, 0.196, 0.126)]), "suit", "DEF-spine.002")
    add(loft([(1.31, 0.196, 0.126), (1.41, 0.205, 0.12), (1.48, 0.16, 0.095)]), "suit", "DEF-spine.003")
    add(_bm_box((0, -0.129, 1.37), (0.15, 0.012, 0.11), 0.004), "accent", "DEF-spine.003")   # chest panel
    add(_bm_box((0, -0.121, 1.12), (0.012, 0.008, 0.26), 0.0), "dark", "DEF-spine.001")      # zip seam
    add(_bm_box((0, 0.155, 1.33), (0.2, 0.07, 0.24), 0.02), "dark", "DEF-spine.003")         # back unit
    add(_bm_box((0, 0.192, 1.33), (0.05, 0.01, 0.18), 0.003), "accent", "DEF-spine.003")     # its ember slot
    for s in (-1, 1):
        S = "L" if s > 0 else "R"
        # arm: shoulder cap, sleeve, elbow, forearm with a cuff, glove and thumb
        add(ball((s * 0.205, 0.03, 1.445), 0.072, 1.0, 1.0, 0.9), "suit", f"DEF-shoulder.{S}")
        add(tube((s * 0.21, 0.065, 1.441), (s * 0.47, 0.07, 1.441), 0.06, 0.049), "suit", f"DEF-upper_arm.{S}")
        add(ball((s * 0.466, 0.07, 1.441), 0.047), "dark", f"DEF-forearm.{S}")
        add(tube((s * 0.47, 0.07, 1.441), (s * 0.705, 0.065, 1.441), 0.049, 0.041), "suit", f"DEF-forearm.{S}")
        add(tube((s * 0.66, 0.066, 1.441), (s * 0.72, 0.065, 1.441), 0.047, 0.045), "accent", f"DEF-forearm.{S}")
        add(_bm_box((s * 0.805, 0.065, 1.438), (0.15, 0.085, 0.042), 0.012), "dark", f"DEF-hand.{S}")
        add(_bm_box((s * 0.775, 0.0, 1.432), (0.06, 0.04, 0.032), 0.008), "dark", f"DEF-hand.{S}")
        # leg: thigh with a side stripe, knee pad, shin, ankle cuff
        add(tube((s * 0.089, 0.0, 0.95), (s * 0.089, 0.0, 0.525), 0.088, 0.063, sides=8), "dark", f"DEF-thigh.{S}")
        add(_bm_box((s * 0.165, 0.0, 0.74), (0.012, 0.03, 0.34), 0.0), "accent", f"DEF-thigh.{S}")
        add(ball((s * 0.089, 0.002, 0.53), 0.062), "dark", f"DEF-shin.{S}")
        add(_bm_box((s * 0.089, -0.058, 0.52), (0.085, 0.028, 0.1), 0.01), "suit", f"DEF-shin.{S}")
        add(tube((s * 0.089, 0.002, 0.53), (s * 0.089, 0.03, 0.15), 0.063, 0.047, sides=8), "dark", f"DEF-shin.{S}")
        add(tube((s * 0.089, 0.028, 0.2), (s * 0.089, 0.034, 0.12), 0.05, 0.05, sides=8), "accent", f"DEF-shin.{S}")
        # shoe: upper, toe box, soles, side stripe
        add(_bm_box((s * 0.089, -0.03, 0.075), (0.108, 0.2, 0.095), 0.02), "suit", f"DEF-foot.{S}")
        add(_bm_box((s * 0.089, -0.195, 0.055), (0.1, 0.15, 0.06), 0.018), "suit", f"DEF-toe.{S}")
        add(_bm_box((s * 0.089, -0.03, 0.016), (0.114, 0.21, 0.032), 0.008), "sole", f"DEF-foot.{S}")
        add(_bm_box((s * 0.089, -0.195, 0.014), (0.106, 0.16, 0.028), 0.008), "sole", f"DEF-toe.{S}")
        add(_bm_box((s * 0.144, -0.04, 0.07), (0.006, 0.14, 0.022), 0.0), "accent", f"DEF-foot.{S}")
    return P


def build_body(rig):
    roles = ["suit", "dark", "accent", "visor", "sole"]
    objs = []
    for i, (bm, role, bone) in enumerate(parts()):
        me = bpy.data.meshes.new(f"part{i}")
        bm.to_mesh(me)
        bm.free()
        for r in roles:
            me.materials.append(bpy.data.materials.get(r) or bpy.data.materials.new(r))
        for p in me.polygons:
            p.material_index = roles.index(role)
            p.use_smooth = False # flat facets: the vector look
        o = bpy.data.objects.new(f"part{i}", me)
        bpy.context.collection.objects.link(o)
        o.vertex_groups.new(name=bone).add(range(len(me.vertices)), 1.0, "REPLACE")
        objs.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "Runner"
    body.data.name = "Runner"
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return body


# ---- clips ---------------------------------------------------------------------------------------

def _world_rot(arm, bone):
    return (arm.matrix_world @ arm.pose.bones[bone].matrix).to_quaternion()


def retarget(src, dst, names):
    """Copy src's actions onto dst bone by bone: each target bone takes its source bone's world
    rotation (times the fixed offset between the two bones, measured with both rigs in the same
    pose: their A_TPose clips), the hips its world position. Same mannequin, so positions carry."""
    order = [b.name for b in dst.data.bones if b.name in BONE_MAP.values()] # parents before children
    inv_map = {v: k for k, v in BONE_MAP.items()}
    sc = bpy.context.scene

    def pose(arm, action, frame):
        arm.animation_data.action = action
        sc.frame_set(int(frame))

    tp_src = bpy.data.actions[src["tpose"]]
    tp_dst = bpy.data.actions["A_TPose"]
    pose(src["arm"], tp_src, tp_src.frame_range[0])
    pose(dst, tp_dst, tp_dst.frame_range[0])
    offset = {b: _world_rot(src["arm"], inv_map[b]).inverted() @ _world_rot(dst, b) for b in order}
    for name in names:
        act = bpy.data.actions[src["actions"][name]]
        new = bpy.data.actions.new(name)
        new.use_fake_user = True
        dst.animation_data.action = new
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        for f in range(f0, f1 + 1):
            pose(src["arm"], act, f)
            dst.animation_data.action = new
            for b in order:
                pb = dst.pose.bones[b]
                world = (src["arm"].matrix_world @ src["arm"].pose.bones[inv_map[b]].matrix)
                rot = world.to_quaternion() @ offset[b]
                cur = dst.matrix_world @ pb.matrix
                loc = world.to_translation() if b == "DEF-hips" else cur.to_translation()
                pb.matrix = dst.matrix_world.inverted() @ Matrix.LocRotScale(loc, rot, Vector((1, 1, 1)))
                bpy.context.view_layer.update()
            for b in order:
                pb = dst.pose.bones[b]
                pb.keyframe_insert("rotation_quaternion", frame=f - f0)
                if b == "DEF-hips":
                    pb.keyframe_insert("location", frame=f - f0)
        print(f"  retargeted {name}: {f1 - f0 + 1} frames")


def derived_clip(rig, name, base, frame, turns, frames=2):
    """A held pose: `base` at `frame`, then each (bone, world axis, degrees) in turns applied about
    the bone's head in world space (parents first). Keyed over `frames` frames (a loop)."""
    sc = bpy.context.scene
    rig.animation_data.action = bpy.data.actions[base]
    sc.frame_set(frame)
    bpy.context.view_layer.update()
    mats = {pb.name: pb.matrix.copy() for pb in rig.pose.bones}
    new = bpy.data.actions.new(name)
    new.use_fake_user = True
    rig.animation_data.action = new
    for pb in rig.pose.bones:
        pb.matrix = mats[pb.name]
        bpy.context.view_layer.update()
    for bone, axis, deg in turns:
        pb = rig.pose.bones[bone]
        head = pb.matrix.to_translation()
        r = Matrix.Translation(head) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-head)
        pb.matrix = r @ pb.matrix
        bpy.context.view_layer.update()
    for f in range(frames):
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    print(f"  made {name} from {base}@{frame}")


def wobble_clip(rig, name, base, cycles, holds, waves):
    """A loop made from `base` played `cycles` times, with turns layered on top in world space about
    each bone's head (parents first): `holds` (bone, axis, degrees) all the way through, `waves`
    (bone, axis, degrees, waves per loop, phase 0..1) as sines. Whole waves per loop and whole
    cycles of the base, so the last frame meets the first."""
    sc = bpy.context.scene
    act = bpy.data.actions[base]
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    length = f1 - f0
    total = length * cycles
    new = bpy.data.actions.new(name)
    new.use_fake_user = True
    order = [b.name for b in rig.data.bones] # parents before children
    for f in range(total + 1):
        rig.animation_data.action = act
        sc.frame_set(f0 + f % length)
        bpy.context.view_layer.update()
        mats = {pb.name: pb.matrix.copy() for pb in rig.pose.bones}
        # posed with no action attached (an attached one would re-apply its own keys on every
        # update and the turns would pile up), keyed into the new one after
        rig.animation_data.action = None
        for b in order:
            rig.pose.bones[b].matrix = mats[b]
            bpy.context.view_layer.update()
        t = f / total
        turns = list(holds) + [(b, ax, deg * math.sin(math.tau * (k * t + ph))) for b, ax, deg, k, ph in waves]
        turns.sort(key=lambda tr: order.index(tr[0]))
        for bone, axis, deg in turns:
            pb = rig.pose.bones[bone]
            head = pb.matrix.to_translation()
            r = Matrix.Translation(head) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-head)
            pb.matrix = r @ pb.matrix
            bpy.context.view_layer.update()
        rig.animation_data.action = new
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    print(f"  made {name} from {base} x{cycles}: {total + 1} frames")


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    out = args[0]
    preview = args[1] if len(args) > 1 else None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = 30

    # UAL2 first (its actions get renamed so UAL1's same-named ones don't clash)
    bpy.ops.import_scene.gltf(filepath=UAL2)
    arm2 = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    arm2.name = "UAL2"
    src = {"arm": arm2, "actions": {}}
    for a in list(bpy.data.actions):
        src["actions"][a.name] = "ual2_" + a.name
        a.name = "ual2_" + a.name
    src["tpose"] = "ual2_A_TPose"
    if not arm2.animation_data:
        arm2.animation_data_create()
    ual2_objs = [o for o in bpy.data.objects]

    bpy.ops.import_scene.gltf(filepath=UAL1)
    rig = bpy.data.objects["Rig"]
    if not rig.animation_data:
        rig.animation_data_create()
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o not in ual2_objs:
            bpy.data.objects.remove(o) # the library's mannequin and its preview ball
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"

    retarget(src, rig, FROM_UAL2)
    # (a positive turn about X pitches the figure forward: it faces -Y)
    derived_clip(rig, "Dash", "Sprint_Loop", 4, [("DEF-hips", "X", 26), ("DEF-spine.002", "X", 8), ("DEF-head", "X", -18)])
    derived_clip(rig, "Slam", "NinjaJump_Idle_Loop", 0, [("DEF-hips", "X", 22), ("DEF-head", "X", 12)])
    # dizzy: a stumbling walk, the upper body swaying side to side over two steps-pairs (rolls
    # about Y: the figure faces -Y), the head lagging the sway and nodding, a forward slump, arms
    # held out for balance and flailing a little. The hips stay put so the feet stay planted.
    wobble_clip(rig, "Dizzy_Loop", "Walk_Loop", 2,
                holds=[("DEF-spine.001", "X", 7), ("DEF-upper_arm.L", "Y", -30), ("DEF-upper_arm.R", "Y", 30)],
                waves=[("DEF-spine.001", "Y", 9, 1, 0.0), ("DEF-spine.003", "Y", 4, 1, 0.1),
                       ("DEF-head", "Y", 10, 1, 0.22), ("DEF-head", "X", 5, 3, 0.0), ("DEF-hips", "Z", 5, 1, 0.35),
                       ("DEF-upper_arm.L", "Y", 10, 2, 0.0), ("DEF-upper_arm.R", "Y", 10, 2, 0.5),
                       ("DEF-forearm.L", "X", 12, 3, 0.1), ("DEF-forearm.R", "X", 12, 3, 0.6)])
    # frozen (set alight, bumped): a flinch, held: hunched, head down, arms up guarding the face,
    # knees a little bent, and a fine shiver through it (stuck, not paused mid-stride)
    wobble_clip(rig, "Frozen_Loop", "Idle_Loop", 1,
                holds=[("DEF-spine.001", "X", 14), ("DEF-head", "X", 18), ("DEF-thigh.L", "X", -10), ("DEF-thigh.R", "X", -10),
                       ("DEF-shin.L", "X", 18), ("DEF-shin.R", "X", 18), ("DEF-upper_arm.L", "X", -65), ("DEF-upper_arm.R", "X", -65),
                       ("DEF-forearm.L", "X", -70), ("DEF-forearm.R", "X", -70)],
                waves=[("DEF-spine.003", "Y", 1.2, 15, 0.0), ("DEF-head", "X", 1.5, 17, 0.3),
                       ("DEF-upper_arm.L", "X", 2.0, 13, 0.1), ("DEF-upper_arm.R", "X", 2.0, 13, 0.6)])

    # drop everything that isn't kept
    for o in ual2_objs:
        bpy.data.objects.remove(o)
    keep = set(KEEP_UAL1 + FROM_UAL2 + ["Dash", "Slam", "Dizzy_Loop", "Frozen_Loop"]) - {"Walk_Loop"}
    for a in list(bpy.data.actions):
        if a.name not in keep:
            bpy.data.actions.remove(a)
        else:
            a.use_fake_user = True
    # the clips keyed from frame 0 (UAL1's start at 0 too)
    rig.animation_data.action = bpy.data.actions["Idle_Loop"]
    body = build_body(rig)
    print("body: %d verts, %d faces" % (len(body.data.vertices), len(body.data.polygons)))

    if preview:
        render_preview(rig, body, preview)
    bpy.data.actions.remove(bpy.data.actions["A_TPose"])
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    body.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True, export_apply=False,
                              export_yup=True)
    print("runner exported to", out, sorted(a.name for a in bpy.data.actions))


def render_preview(rig, body, path):
    """A row of poses (rest, idle, sprint, jump, slide, dash, slam), front three-quarter, flat colours."""
    for m in body.data.materials:
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*PREVIEW_COL[m.name], 1)
        b.inputs["Roughness"].default_value = 0.7
        if m.name == "visor":
            b.inputs["Emission Color"].default_value = (*PREVIEW_COL["visor"], 1)
            b.inputs["Emission Strength"].default_value = 3.0
    poses = [("A_TPose", 0), ("Idle_Loop", 10), ("Sprint_Loop", 4), ("Jump_Loop", 10), ("Slide_Loop", 10), ("Dash", 0), ("Slam", 0)]
    if os.environ.get("POSES"): # e.g. POSES="Roll:0,Roll:5" to look through a clip
        poses = [(p.split(":")[0], int(p.split(":")[1])) for p in os.environ["POSES"].split(",")]
    sc = bpy.context.scene
    copies = []
    for i, (act, f) in enumerate(poses):
        rig.animation_data.action = bpy.data.actions[act]
        sc.frame_set(f)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(body.evaluated_get(dg))
        o = bpy.data.objects.new(f"pose_{act}", me)
        bpy.context.collection.objects.link(o)
        o.matrix_world = body.matrix_world.copy()
        o.location.x += (i - (len(poses) - 1) * 0.5) * 1.25
        copies.append(o)
    body.hide_render = True
    bpy.ops.mesh.primitive_plane_add(size=30)
    fl = bpy.context.object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.44, 0.4, 1)
    fl.data.materials.append(fm)
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(-30)))
    bpy.context.object.data.energy = 3.5
    bpy.ops.object.camera_add(location=(2.4, -9.0, 1.7), rotation=(math.radians(86), 0, math.radians(14)))
    cam = bpy.context.object
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 9.4
    sc.camera = cam
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.65, 0.72, 1)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.render.resolution_x, sc.render.resolution_y = 1800, 520
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in copies: # the same poses side on (facing left)
        x = o.location.x
        o.rotation_euler.z = math.radians(-90)
        o.location.x = x
    sc.render.filepath = path.replace(".png", "_side.png")
    bpy.ops.render.render(write_still=True)
    for o in copies:
        bpy.data.objects.remove(o)
    body.hide_render = False
    print("preview", path)


if __name__ == "__main__":
    main()
