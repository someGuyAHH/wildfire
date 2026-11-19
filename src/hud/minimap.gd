class_name Minimap
extends Control

## A round minimap (top right of the match HUD): the map from above (GameMap.minimap, baked by
## the map generator) centred on you and turned with your view (forward is up), with everyone on
## it: you a blue arrow, Torches red, Kindlings grey, the burned-out a faint ring; anyone out of
## range sits on the rim. The storm's edge when it's closing. Clipped to the circle by this
## control's own disc (clip_children).

const RADIUS := 105.0          # px
const RANGE := 85.0            # metres from you to the rim
const YOU := Color(0.3, 0.62, 1.0)
const TORCH := Color(1.0, 0.27, 0.15)
const KINDLING := Color(0.78, 0.78, 0.78)
const OUT := Color(0.55, 0.55, 0.55, 0.6)
const STORM := Color(0.75, 0.4, 1.0, 0.9)
const BACK := Color(0.07, 0.07, 0.08, 0.85)

var tag_manager: TagManager
var player: Character
var _disc: Control  # the disc everything on the map is clipped to (clip_children)
var _layer: Control # inside it: the map, the storm, the dots
var _rim: Control   # over it: the border and the north mark


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * RADIUS * 2.0
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc = _child(self, func() -> void: _disc.draw_circle(Vector2.ONE * RADIUS, RADIUS, BACK))
	_disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_layer = _child(_disc, _draw_layer)
	_rim = _child(self, _draw_rim)


func _child(parent: Control, drawer: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(drawer)
	parent.add_child(c)
	return c


func _process(_delta: float) -> void:
	_layer.queue_redraw()
	_rim.queue_redraw()


## Where you're looking from, and which way: (centre xz, forward xz unit).
func _view() -> Array:
	var centre := player.global_position if is_instance_valid(player) else Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	var fwd := Vector2(0.0, -1.0)
	if cam:
		var f := -cam.global_basis.z
		if Vector2(f.x, f.z).length() > 0.01: fwd = Vector2(f.x, f.z).normalized()
		if tag_manager and is_instance_valid(player) and tag_manager.is_out(player): centre = cam.global_position
	return [Vector2(centre.x, centre.z), fwd]


## World xz -> minimap px (forward up, you in the middle).
func _xf(view: Array) -> Transform2D:
	var c: Vector2 = view[0]
	var f: Vector2 = view[1]
	var right := Vector2(-f.y, f.x)
	var s := RADIUS / RANGE
	var x_axis := Vector2(right.x, -f.x) * s
	var y_axis := Vector2(right.y, -f.y) * s
	return Transform2D(x_axis, y_axis, Vector2.ONE * RADIUS - (x_axis * c.x + y_axis * c.y))


func _draw_layer() -> void:
	if not is_instance_valid(player): return
	var view := _view()
	var xf := _xf(view)
	var map := tag_manager.map if tag_manager else null
	if map and map.minimap and map.minimap_half_extent > 0.0:
		var e := map.minimap_half_extent
		_layer.draw_set_transform_matrix(xf)
		_layer.draw_texture_rect(map.minimap, Rect2(-e, -e, e * 2.0, e * 2.0), false)
		_layer.draw_set_transform_matrix(Transform2D.IDENTITY)
	if tag_manager and tag_manager.storm_active():
		var sc := tag_manager.get_storm_center()
		var r := tag_manager.get_storm_radius()
		_layer.draw_set_transform_matrix(xf)
		_layer.draw_arc(Vector2(sc.x, sc.z), r, 0.0, TAU, 96, STORM, 2.5 * RANGE / RADIUS)
		_layer.draw_set_transform_matrix(Transform2D.IDENTITY)
	if not tag_manager: return
	var rim := RADIUS - 7.0
	for c: Character in tag_manager.get_participants():
		if not is_instance_valid(c) or c == player: continue
		var p := xf * Vector2(c.global_position.x, c.global_position.z)
		var off := p - Vector2.ONE * RADIUS
		var far := off.length() > rim
		if far: p = Vector2.ONE * RADIUS + off.normalized() * rim
		if tag_manager.is_out(c):
			_layer.draw_arc(p, 4.0, 0.0, TAU, 12, OUT, 1.5)
			continue
		var torch := tag_manager.is_torch(c)
		_layer.draw_circle(p, (5.5 if torch else 4.5) * (0.8 if far else 1.0), TORCH if torch else KINDLING)
		_layer.draw_arc(p, (5.5 if torch else 4.5) * (0.8 if far else 1.0), 0.0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)
	# you: an arrow pointing up (your view), ringed red while you're a Torch
	var m := Vector2.ONE * RADIUS
	var arrow := PackedVector2Array([m + Vector2(0, -8), m + Vector2(6, 6), m + Vector2(0, 3), m + Vector2(-6, 6)])
	if tag_manager.is_torch(player): _layer.draw_circle(m, 10.0, Color(TORCH, 0.55))
	_layer.draw_colored_polygon(arrow, YOU)
	_layer.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.7), 1.2)


func _draw_rim() -> void:
	var m := Vector2.ONE * RADIUS
	_rim.draw_arc(m, RADIUS - 1.0, 0.0, TAU, 96, Color(1.0, 0.52, 0.1, 0.9), 2.5)
	# north: where world -z is, on the rim
	var view := _view()
	var north := (_xf(view).basis_xform(Vector2(0.0, -1.0))).normalized()
	var n := m + north * (RADIUS - 1.0)
	_rim.draw_circle(n, 9.0, Color(0.1, 0.1, 0.1, 0.9))
	_rim.draw_string(ThemeDB.fallback_font, n + Vector2(-5.0, 5.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
