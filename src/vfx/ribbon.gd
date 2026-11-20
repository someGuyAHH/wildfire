class_name Ribbon
extends MeshInstance3D
## A streak through the points something passed lately: a strip turned to face the camera, widest
## at the live end and tapering and fading back along it, each point living `life` seconds. One
## solid strip whatever the speed (particles dropped once a frame break into beads). Subclasses say
## where the live end is (_sample, null while not recording). Optionally a brighter, narrower core
## strip down the middle. World space (top_level); rebuilt every frame from its few dozen points.

## Seconds a point lasts.
@export var life: float = 0.35
## Width (m) at the live end.
@export var width: float = 0.55
## A new point once the live end has moved this far (m).
@export var min_step: float = 0.15
## Width share (0..1) of a brighter core strip down the middle; 0: none.
@export var core: float = 0.0

## One colour all along, fading back (when there's no gradient).
var color := Color.WHITE
## Colour along the ribbon instead: offset 0 the oldest end, 1 the live end (alpha multiplies).
var gradient: Gradient
var _points: Array[Vector3] = []
var _times: Array[float] = []
var _clock := 0.0
var _imesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_transform = Transform3D.IDENTITY


## Where the live end is now, or null while not recording.
func _sample() -> Variant:
	return null


func _process(delta: float) -> void:
	_clock += delta
	var head: Variant = _sample()
	if head != null:
		if _points.is_empty() or _points[_points.size() - 1].distance_to(head) > min_step:
			_points.append(head)
			_times.append(_clock)
	while not _times.is_empty() and _clock - _times[0] > life:
		_points.remove_at(0)
		_times.remove_at(0)
	_imesh.clear_surfaces()
	var pts := _points.duplicate()
	var times := _times.duplicate()
	if head != null and not pts.is_empty() and pts[pts.size() - 1].distance_to(head) > 0.01:
		pts.append(head) # the live end, right where it is now (not yet a kept point)
		times.append(_clock)
	if pts.size() < 2: return
	_strip(pts, times, 1.0, 0.0)
	if core > 0.0: _strip(pts, times, core, 1.0)


## One strip: `share` of the full width, `bright` 0..1 how far its colour goes toward white (and
## toward opaque): the core.
func _strip(pts: Array, times: Array, share: float, bright: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam: return
	var eye := cam.global_position
	var n := pts.size()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in n:
		var p: Vector3 = pts[i]
		var along: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := along.cross(p - eye).normalized()
		var age := clampf((_clock - times[i]) / life, 0.0, 1.0)
		var t := float(i) / float(n - 1) # 0 at the oldest end, 1 at the live end
		var w := width * share * 0.5 * t * (1.0 - age * 0.5)
		var c := gradient.sample(t) if gradient else Color(color, 0.25 + 0.75 * t)
		c.a *= 1.0 - age
		if bright > 0.0:
			c = Color(c.lerp(Color.WHITE, 0.55 * bright), minf(c.a * (1.0 + bright), 1.0))
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p + side * w)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p - side * w)
	_imesh.surface_end()
