class_name WaterfallSpray
extends Node3D
## Spray where a waterfall lands: soft white mist billowing up and drifting off, and droplets flung
## out in arcs and falling back. Put at the fall's splash point (the generator knows it); only
## drawn within `view_range`. GPU particles.

const _DOT := preload("res://assets/tres/vfx/soft_dot.tres")

## Not drawn further than this from the camera (m).
@export var view_range: float = 140.0
## Size of the splash (m across), how wide the fall hits the pool.
@export var width: float = 7.0


## Off while a map generator places this (see LavaSparks.build).
@export var build := true


func _ready() -> void:
	if not build: return
	add_child(_mist())
	add_child(_drops())


func _mist() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.55, 0.3, 2.0)
	pm.direction = Vector3(0.0, 1.0, 0.4)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0.0, 0.25, 0.0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.scale_curve = _curve([Vector2(0.0, 0.4), Vector2(1.0, 1.0)])
	pm.color_ramp = _ramp([0.0, 0.2, 1.0], [Color(0.95, 0.98, 1.0, 0.0), Color(0.95, 0.98, 1.0, 0.6), Color(0.88, 0.94, 1.0, 0.0)])
	return _emitter(pm, 44, 2.8, 3.6, false)


func _drops() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.45, 0.1, 1.0)
	pm.direction = Vector3(0.0, 1.0, 0.5)
	pm.spread = 50.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([0.0, 0.7, 1.0], [Color(1.0, 1.0, 1.0, 0.9), Color(0.9, 0.96, 1.0, 0.7), Color(0.9, 0.96, 1.0, 0.0)])
	return _emitter(pm, 80, 1.1, 0.2, true)


func _emitter(pm: ParticleProcessMaterial, amount: int, life: float, size: float, bright: bool) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.amount = amount
	e.lifetime = life
	e.randomness = 0.5
	e.local_coords = false
	e.process_material = pm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if bright: mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _DOT
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	e.draw_pass_1 = quad
	e.visibility_range_end = view_range
	e.visibility_range_end_margin = 20.0
	e.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	e.visibility_aabb = AABB(Vector3(-width, -2.0, -width), Vector3(width * 2.0, 10.0, width * 2.0))
	return e


static func _curve(points: Array[Vector2]) -> CurveTexture:
	var c := Curve.new()
	for p: Vector2 in points: c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
