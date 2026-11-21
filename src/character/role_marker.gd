"""
The floating marker over a character's head: a small flat-shaded pyramid pointing down, spinning
and bobbing. Its colour is the character's role (the Torch: fire orange and glowing, drawn through
walls; everyone else: their own colour, hidden by walls). Kept about the same size on screen at any
distance. One shared mesh and two shared materials (colour is a per-instance shader parameter),
and no per-frame allocation.
"""

class_name RoleMarker
extends MeshInstance3D

const _SHADER := preload("res://assets/gdshaders/role_marker.gdshader")
const _SHADER_XRAY := preload("res://assets/gdshaders/role_marker_xray.gdshader")

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial
static var _mat_xray: ShaderMaterial

var config: MarkerConfig
var _t := 0.0
var _pop := 0.0
var _torch := false
var _color := Color.WHITE


func _init() -> void:
	name = "RoleMarker"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh = _shared_mesh()
	material_override = _shared_mat()
	extra_cull_margin = 4.0 # the scale grows with distance: never cull it by its small box


func setup(cfg: MarkerConfig, color: Color) -> void:
	config = cfg
	_shared_mat().set_shader_parameter(&"self_light", cfg.self_light)
	_t = randf() * TAU # every marker its own spin and bob phase
	_apply(color, false, false)


## Changes the role: the Torch is orange, glowing and through walls. A change of role pops.
func set_role(color: Color, torch: bool) -> void:
	_apply(color, torch, torch != _torch)


func is_torch() -> bool:
	return _torch


func get_color() -> Color:
	return _color


func _apply(color: Color, torch: bool, pop: bool) -> void:
	_torch = torch
	_color = color
	set_instance_shader_parameter(&"tint", Vector3(color.r, color.g, color.b))
	set_instance_shader_parameter(&"glow", config.torch_glow if torch else 0.0)
	material_override = _shared_mat_xray() if torch else _shared_mat()
	if pop: _pop = 1.0


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam or not visible or not config: return
	_t += delta
	_pop = maxf(_pop - delta / maxf(config.pop_time, 0.01), 0.0)
	var dist := cam.global_position.distance_to(global_position)
	var s := clampf(dist / config.ref_distance, config.min_scale, config.max_scale) * config.size
	s *= 1.0 + config.pop_scale * _pop * _pop
	scale = Vector3(s, s, s)
	position.y = config.height + sin(_t * config.bob_speed) * config.bob_amount
	rotation.y = _t * config.spin_speed


static func _shared_mat() -> ShaderMaterial:
	if not _mat:
		_mat = ShaderMaterial.new()
		_mat.shader = _SHADER
	return _mat


static func _shared_mat_xray() -> ShaderMaterial:
	if not _mat_xray:
		_mat_xray = ShaderMaterial.new()
		_mat_xray.shader = _SHADER_XRAY
		_mat_xray.render_priority = 10 # last of the opaque pass, so walls don't draw over it
	return _mat_xray


# unit inverted pyramid: tip at the origin pointing down, a triangular top 1 wide and 1 tall,
# flat faces (own vertices per face, so each facet shades on its own)
static func _shared_mesh() -> ArrayMesh:
	if _mesh: return _mesh
	var tip := Vector3.ZERO
	var r := 0.5
	var top: Array[Vector3] = []
	for i: int in 3:
		var a := TAU * i / 3.0
		top.append(Vector3(cos(a) * r, 1.0, sin(a) * r))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 3:
		st.add_vertex(tip)
		st.add_vertex(top[i])
		st.add_vertex(top[(i + 1) % 3])
	st.add_vertex(top[0]) # the lid
	st.add_vertex(top[2])
	st.add_vertex(top[1])
	st.generate_normals()
	_mesh = st.commit()
	return _mesh
