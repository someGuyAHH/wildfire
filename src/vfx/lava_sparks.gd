class_name LavaSparks
extends Node3D
## Sparks spitting off the lava sea: glowing specks flung up out of vents, arcing and falling
## back, scattered over the open lava (spread thin over the whole sea they vanished). At load it
## casts a grid of rays down to the lava and puts a vent at a random spot in each cell open to the sky (none under the halls and causeways, where nobody would
## see them); each one only drawn within `view_range`. GPU particles: a few hundred specks cost
## next to nothing.

const _DOT := preload("res://assets/tres/vfx/soft_dot.tres")

## Height of the lava's surface (world).
@export var lava_y: float = -14.0
## How far out from this node to look for open lava (m).
@export var radius: float = 240.0
## Spacing of the emitters (m): each covers a square this wide.
@export var spacing: float = 36.0
## Emitters further than this from the camera aren't drawn (m).
@export var view_range: float = 160.0

var _process_mat: ParticleProcessMaterial
var _draw: QuadMesh


## Off while a map generator places this (so its emitters aren't saved into the map and built
## again on top at load); the generator turns it back on before saving.
@export var build := true


func _ready() -> void:
	if not build: return
	_build_materials()
	_place.call_deferred()


func _place() -> void:
	await get_tree().physics_frame # (the map's collision is in the world by now)
	var space := get_world_3d().direct_space_state
	var count := 0
	var steps := int(radius / spacing)
	for ix: int in range(-steps, steps + 1):
		for iz: int in range(-steps, steps + 1):
			var jitter := Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.35, 0.35)) * spacing
			var p := global_position + Vector3(ix * spacing, 0.0, iz * spacing) + jitter
			if Vector2(p.x, p.z).length() > radius: continue
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, lava_y + 120.0, p.z), Vector3(p.x, lava_y - 1.0, p.z), 1)
			var hit := space.intersect_ray(q)
			if hit and (hit.position as Vector3).y > lava_y + 0.5: continue # something over the lava here
			_emitter(Vector3(p.x, lava_y + 0.2, p.z))
			count += 1
	set_meta(&"emitters", count)


func _emitter(at: Vector3) -> void:
	var e := GPUParticles3D.new()
	e.amount = 34
	e.lifetime = 2.6
	e.randomness = 0.6
	e.local_coords = false
	e.process_material = _process_mat
	e.draw_pass_1 = _draw
	e.visibility_range_end = view_range
	e.visibility_range_end_margin = 20.0
	e.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	e.visibility_aabb = AABB(Vector3(-10.0, -1.0, -10.0), Vector3(20.0, 16.0, 20.0))
	add_child(e)
	e.global_position = at


func _build_materials() -> void:
	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(1.5, 0.1, 1.5) # a vent
	_process_mat.direction = Vector3.UP
	_process_mat.spread = 28.0
	# up to ~12 m: they only show above the lava, against the darker walls and sky (over the near
	# white-hot lava itself they vanish)
	_process_mat.initial_velocity_min = 6.0
	_process_mat.initial_velocity_max = 15.0
	_process_mat.gravity = Vector3(0.0, -9.0, 0.0)
	_process_mat.damping_min = 0.3
	_process_mat.damping_max = 1.0
	_process_mat.scale_min = 0.5
	_process_mat.scale_max = 1.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	_process_mat.scale_curve = shrink_tex
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.75, 1.0])
	# white-hot at first (orange on the orange lava vanished), cooling through yellow and red
	ramp.colors = PackedColorArray([Color(1.0, 1.0, 0.9, 1.0), Color(1.0, 0.75, 0.25, 1.0), Color(1.0, 0.3, 0.05, 0.9), Color(0.5, 0.06, 0.02, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	_process_mat.color_ramp = ramp_tex
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _DOT
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_draw = QuadMesh.new()
	_draw.size = Vector2(0.7, 0.7)
	_draw.material = mat
