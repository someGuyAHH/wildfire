@tool
extends Node3D

# greybox movement gym, built from code so every obstacle has exact, labelled numbers.
# runs in the editor too (tool), but the generated nodes aren't owned so they never get saved.

const _GRID_SHADER := preload("res://assets/gdshaders/greybox_grid.gdshader")
const _JUMP_PAD    := preload("res://scn/props/jump_pad.tscn")
const _SPEED_STRIP := preload("res://scn/props/speed_strip.tscn")

# palette
const _C_GROUND := Color(0.42, 0.43, 0.46)
const _C_RAMP   := Color(0.86, 0.56, 0.26)
const _C_STAIRS := Color(0.36, 0.56, 0.86)
const _C_WALL   := Color(0.82, 0.36, 0.32)
const _C_TUNNEL := Color(0.36, 0.72, 0.46)
const _C_SHAFT  := Color(0.58, 0.42, 0.82)
const _C_PILLAR := Color(0.6, 0.6, 0.64)
const _C_HILL   := Color(0.78, 0.74, 0.4)

@export var ground_size: float = 420.0
@export var pillar_seed: int = 1337

var _root: Node3D
var _materials: Dictionary[Color, ShaderMaterial] = {}


func _ready() -> void:
	_build()


## Throws away the generated geometry and builds it again.
func rebuild() -> void:
	_build()


func _build() -> void:
	if _root: _root.free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	_materials.clear()

	_box(Vector3(0, -1, 0), Vector3(ground_size, 2, ground_size), _C_GROUND)
	_build_stairs()
	_build_ramps()
	_build_vault_walls()
	_build_slide_tunnel()
	_build_wall_shaft()
	_build_pillar_field()
	_build_pads()
	_build_speed_track()
	_build_slide_hill()


#region zones

# auto-step should eat the first three, the last one needs a jump
func _build_stairs() -> void:
	var heights: Array[float] = [0.25, 0.4, 0.5, 0.7]
	var x := -20.0
	for h: float in heights:
		for i: int in 8:
			var top := h * (i + 1)
			_box(Vector3(x, top * 0.5, -20.0 - (i + 0.5)), Vector3(6, top, 1), _C_STAIRS)
		_box(Vector3(x, h * 4.0, -32.0), Vector3(6, h * 8.0, 8), _C_STAIRS)
		_label(Vector3(x, 1.5, -17.0), "step %.2f m" % h)
		x -= 10.0
	_label(Vector3(-35, 4.0, -14.0), "STAIRS")


# 50 and 60 are walls on purpose (floor_max_angle is 50)
func _build_ramps() -> void:
	var x := 20.0
	for angle: float in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]:
		var top := _ramp(Vector3(x, 0, -20), 0.0, 8.0, 22.0, angle, _C_RAMP)
		_box(Vector3(x, top.y * 0.5, top.z - 4.0), Vector3(8, top.y, 8), _C_RAMP)
		_label(Vector3(x, 1.5, -17.0), "%d°" % int(angle))
		x += 12.0
	_label(Vector3(50, 4.0, -14.0), "RAMPS")


# jump + hold jump into the wall to vault; 2.0 and 3.0 are past vault_height
func _build_vault_walls() -> void:
	var x := -20.0
	for h: float in [0.9, 1.2, 1.5, 2.0, 3.0]:
		_box(Vector3(x, h * 0.5, 28), Vector3(6, h, 4), _C_WALL)
		_label(Vector3(x, h + 1.0, 25.5), "%.1f m" % h)
		x -= 10.0
	_label(Vector3(-40, 5.0, 22.0), "VAULT WALLS")


# 1.3 m ceiling: standing (1.8) won't fit, sliding (1.0) will
func _build_slide_tunnel() -> void:
	var length := 30.0
	var cx := 35.0
	_box(Vector3(cx, 1.5, 25.5), Vector3(length, 3, 1), _C_TUNNEL)
	_box(Vector3(cx, 1.5, 30.5), Vector3(length, 3, 1), _C_TUNNEL)
	_box(Vector3(cx, 1.8, 28), Vector3(length, 1, 6), _C_TUNNEL)
	_label(Vector3(cx - length * 0.5 - 2.0, 3.0, 28), "SLIDE TUNNEL 1.3 m")


# bounce between the thin wall and the tower to get on top.
# 3 wall-jumps + the first jump gets you ~5-6 m, so the tower is 5 m.
func _build_wall_shaft() -> void:
	_box(Vector3(0, 2.5, 66), Vector3(16, 5, 12), _C_SHAFT)
	_box(Vector3(0, 12, 54.5), Vector3(16, 24, 1), _C_SHAFT)
	_label(Vector3(-11, 3.0, 57), "WALL-JUMP SHAFT (tower 5 m)")


func _build_pillar_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = pillar_seed
	var center := Vector3(95, 0, 70)
	for i: int in 45:
		var p := center + Vector3(rng.randf_range(-35, 35), 0, rng.randf_range(-35, 35))
		var w := rng.randf_range(1.5, 4.0)
		var h := rng.randf_range(3.0, 18.0)
		_box(Vector3(p.x, h * 0.5, p.z), Vector3(w, h, w), _C_PILLAR)
	_label(center + Vector3(0, 21, 0), "PILLARS")


func _build_pads() -> void:
	# straight up onto a 8 m ledge
	_box(Vector3(-25, 4, 84), Vector3(12, 8, 12), _C_WALL)
	_pad(Vector3(-25, 0, 72), Vector3.ZERO, 0.0, true, 9.5)
	_label(Vector3(-25, 2.5, 72), "PAD up")
	# angled launcher across the map
	_pad(Vector3(-45, 0, 72), Vector3(0, 16, -26), PI, false)
	_label(Vector3(-45, 2.5, 72), "LAUNCHER")


func _build_speed_track() -> void:
	var z := -100.0
	for i: int in 5:
		var strip := _SPEED_STRIP.instantiate() as Node3D
		strip.position = Vector3(5.0 + i * 10.0, 0, z)
		strip.rotation.y = -PI * 0.5
		_root.add_child(strip)
	_ramp(Vector3(52, 0, z), -PI * 0.5, 8.0, 14.0, 25.0, _C_RAMP)
	_label(Vector3(0, 2.5, z), "SPEED STRIP -> RAMP")


# long 15° hill, take the big pad up and slide down
func _build_slide_hill() -> void:
	var top := _ramp(Vector3(-110, 0, -60), 0.0, 14.0, 90.0, 15.0, _C_HILL)
	_box(Vector3(-110, top.y * 0.5, top.z - 6.0), Vector3(14, top.y, 12), _C_HILL)
	_pad(Vector3(-123, 0, top.z - 6.0), Vector3(6, 0, 0), 0.0, true, top.y + 3.5)
	_label(Vector3(-124, 2.5, top.z - 6.0), "PAD to hill top")
	_label(Vector3(-110, 2.5, -55), "SLIDE HILL 15°")

#endregion


#region builders

func _box(pos: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation = rot
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(mi)
	body.add_child(cs)
	_root.add_child(body)
	return body


## Ramp rising away from `start` (ground level) along local -Z rotated by yaw.
## Returns the world position of the top edge's center.
func _ramp(start: Vector3, yaw: float, width: float, length: float, angle_deg: float, color: Color) -> Vector3:
	var a := deg_to_rad(angle_deg)
	var thick := 1.0
	# center so the top surface's near edge sits exactly on the ground at `start`
	var local := Vector3(0, length * 0.5 * sin(a) - thick * 0.5 * cos(a),
						-(thick * 0.5 * sin(a) + length * 0.5 * cos(a)))
	_box(start + local.rotated(Vector3.UP, yaw), Vector3(width, thick, length), color, Vector3(a, yaw, 0))
	var top_local := Vector3(0, length * sin(a), -length * cos(a))
	return start + top_local.rotated(Vector3.UP, yaw)


## height > 0 makes the pad gravity-proof (peaks that high whatever gravity is tuned to).
func _pad(pos: Vector3, launch: Vector3, yaw: float, keep_horizontal: bool, height: float = 0.0) -> void:
	var pad := _JUMP_PAD.instantiate() as Node3D
	pad.position = pos
	pad.rotation.y = yaw
	pad.set(&"launch_velocity", launch)
	pad.set(&"keep_horizontal", keep_horizontal)
	pad.set(&"launch_height", height)
	_root.add_child(pad)


func _label(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.font_size = 96
	l.pixel_size = 0.012
	l.outline_size = 18
	l.modulate = Color(1, 1, 1)
	_root.add_child(l)


func _mat(color: Color) -> ShaderMaterial:
	if _materials.has(color): return _materials[color]
	var m := ShaderMaterial.new()
	m.shader = _GRID_SHADER
	m.set_shader_parameter(&"base_color", color)
	m.set_shader_parameter(&"line_color", color.darkened(0.55))
	_materials[color] = m
	return m

#endregion
