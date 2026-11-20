class_name DashTrail
extends MeshInstance3D
## A streak left behind a dash: a glowing ribbon through the points the runner's chest passed,
## turned to face the camera, tapering and fading out behind, in the character's own colour.
## Records while the character dashes (and a moment after, so the tail eases out), each point
## living `life` seconds. World space (top_level); rebuilt each frame from its points (few dozen).

const _MAT := preload("res://assets/tres/vfx/dash_trail.tres")

## Seconds a point of the streak lasts.
@export var life: float = 0.35
## Width (m) at the runner's end.
@export var width: float = 0.55
## Height (m) of the streak over the character's feet.
@export var height: float = 1.05
## Seconds it keeps recording after the dash ends.
@export var tail_time: float = 0.08

var character: Character
var color := Color(0.42, 0.7, 1.0)
var _points: Array[Vector3] = []
var _times: Array[float] = []
var _clock := 0.0
var _tail := 0.0
var _imesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _imesh
	material_override = _MAT
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if not character: return
	if character.body_mesh: layers = character.body_mesh.layers # your own stays out of your first-person view
	_clock += delta
	var dashing := character.get_state() == Character.ST_DASHING
	_tail = tail_time if dashing else _tail - delta
	if _tail > 0.0 and character.visible:
		var at := character.get_global_transform_interpolated().origin + Vector3.UP * height
		if _points.is_empty() or _points[_points.size() - 1].distance_to(at) > 0.15:
			_points.append(at)
			_times.append(_clock)
	while not _times.is_empty() and _clock - _times[0] > life:
		_points.remove_at(0)
		_times.remove_at(0)
	_rebuild()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	if _points.size() < 2: return
	var cam := get_viewport().get_camera_3d()
	if not cam: return
	var eye := cam.global_position
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _points.size()
	for i: int in n:
		var p := _points[i]
		var along := (_points[mini(i + 1, n - 1)] - _points[maxi(i - 1, 0)]).normalized()
		var side := along.cross(p - eye).normalized()
		var age := clampf((_clock - _times[i]) / life, 0.0, 1.0)
		var t := float(i) / float(n - 1) # 0 at the oldest end, 1 at the runner
		var w := width * 0.5 * t * (1.0 - age * 0.5)
		var c := Color(color, (1.0 - age) * (0.25 + 0.75 * t))
		_imesh.surface_set_color(c)
		_imesh.surface_set_uv(Vector2(t, 0.0))
		_imesh.surface_add_vertex(p + side * w)
		_imesh.surface_set_color(c)
		_imesh.surface_set_uv(Vector2(t, 1.0))
		_imesh.surface_add_vertex(p - side * w)
	_imesh.surface_end()
