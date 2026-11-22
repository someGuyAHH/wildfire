class_name Minimap
extends Control

## A round minimap (top right of the match HUD): the map from above (GameMap.minimap, baked by
## the map generator) centred on you and turned with your view (forward is up), with everyone on
## it: you a teal arrow, Torches a flame, Kindlings off-white dots, the burned-out a faint ring; anyone out of
## range sits on the rim. The storm's edge when it's closing. Clipped to the circle by this
## control's own disc (clip_children).

const RADIUS := 105.0          # px
const RANGE := 85.0            # metres from you to the rim
const YOU := UIKit.TEAL
const TORCH := UIKit.EMBER
const KINDLING := UIKit.TEXT
const OUT := Color(UIKit.MUTED, 0.6)
const STORM := Color(0.75, 0.4, 1.0, 0.9)      # the storm's edge line
const STORM_FILL := Color(0.62, 0.28, 0.95, 0.4) # everything outside the safe circle
const STORM_NEXT := Color(1.0, 1.0, 1.0, 0.45)   # the dashed outline of where it ends up
const _STORM_SHADER := """
shader_type canvas_item;
uniform vec2 centre = vec2(0.0);   // safe circle, minimap px
uniform float radius = 0.0;
uniform vec2 next_centre = vec2(0.0);
uniform float next_radius = 0.0;
uniform vec4 fill : source_color = vec4(0.62, 0.28, 0.95, 0.4);
uniform vec4 edge : source_color = vec4(0.75, 0.4, 1.0, 0.9);
uniform vec4 next_col : source_color = vec4(1.0, 1.0, 1.0, 0.45);
uniform float px_size = 210.0;
void fragment() {
	vec2 p = UV * px_size;
	float d = distance(p, centre) - radius;
	float a = smoothstep(-0.5, 0.5, d);
	vec4 col = vec4(fill.rgb, fill.a * a);
	float e = 1.0 - smoothstep(0.0, 1.0, abs(d) - 1.0);
	col = mix(col, vec4(edge.rgb, edge.a), e * edge.a);
	if (next_radius > 0.0) {
		vec2 q = p - next_centre;
		float nd = abs(length(q) - next_radius);
		float dash = step(0.5, fract(atan(q.y, q.x) * next_radius / 14.0));
		float n = (1.0 - smoothstep(0.5, 1.2, nd)) * dash * next_col.a;
		col = vec4(mix(col.rgb, next_col.rgb, n), max(col.a, n));
	}
	COLOR = col;
}
"""
const BACK := Color(UIKit.CHARCOAL, 0.85)
const _FLAME := 18.0 # px, a Torch's flame

var tag_manager: TagManager
var player: Character
var _disc: Control  # the disc everything on the map is clipped to (clip_children)
var _layer: Control # inside it: the map
var _storm: ColorRect # then the storm's fill (shader), over the map
var _dots: Control  # then the dots over that
var _rim: Control   # over it: the border and the north mark


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * RADIUS * 2.0
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc = _child(self, func() -> void: _disc.draw_circle(Vector2.ONE * RADIUS, RADIUS, BACK))
	_disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_layer = _child(_disc, _draw_map)
	_storm = ColorRect.new()
	_storm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = _STORM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter(&"fill", STORM_FILL)
	mat.set_shader_parameter(&"edge", STORM)
	mat.set_shader_parameter(&"next_col", STORM_NEXT)
	mat.set_shader_parameter(&"px_size", RADIUS * 2.0)
	_storm.material = mat
	_storm.visible = false
	_disc.add_child(_storm)
	_dots = _child(_disc, _draw_dots)
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
	_dots.queue_redraw()
	_rim.queue_redraw()
	_update_storm()


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


func _draw_map() -> void:
	if not is_instance_valid(player): return
	var xf := _xf(_view())
	var map := tag_manager.map if tag_manager else null
	if map and map.minimap and map.minimap_half_extent > 0.0:
		var e := map.minimap_half_extent
		_layer.draw_set_transform_matrix(xf)
		_layer.draw_texture_rect(map.minimap, Rect2(-e, -e, e * 2.0, e * 2.0), false)
		_layer.draw_set_transform_matrix(Transform2D.IDENTITY)


## The safe circle in minimap px: [centre, radius px, next centre, next radius px (0 = none)],
## or an empty array when there's no storm. Drives the fill shader and is what the check reads.
func storm_circle_px(view: Array = []) -> Array:
	if not tag_manager or not tag_manager.storm_active() or not is_instance_valid(player): return []
	var xf := _xf(view if not view.is_empty() else _view())
	var sc := tag_manager.get_storm_center()
	var k := RADIUS / RANGE
	var next: Array = tag_manager.get_storm_target()
	var nc: Vector2 = next[0]
	var nr: float = next[1]
	var shrinking := absf(nr - tag_manager.get_storm_radius()) > 0.5 or nc.distance_to(Vector2(sc.x, sc.z)) > 0.5
	return [xf * Vector2(sc.x, sc.z), tag_manager.get_storm_radius() * k,
			xf * nc, nr * k if shrinking else 0.0]


## Is minimap point p (px) outside the safe circle, i.e. under the purple?
static func in_storm(p: Vector2, circle: Array) -> bool:
	if circle.is_empty(): return false
	var c: Vector2 = circle[0]
	return p.distance_to(c) > float(circle[1])


func _update_storm() -> void:
	var c := storm_circle_px()
	_storm.visible = not c.is_empty()
	if c.is_empty(): return
	var mat := _storm.material as ShaderMaterial
	mat.set_shader_parameter(&"centre", c[0])
	mat.set_shader_parameter(&"radius", c[1])
	mat.set_shader_parameter(&"next_centre", c[2])
	mat.set_shader_parameter(&"next_radius", c[3])


func _draw_dots() -> void:
	if not is_instance_valid(player): return
	var xf := _xf(_view())
	if not tag_manager: return
	var rim := RADIUS - 7.0
	for c: Character in tag_manager.get_participants():
		if not is_instance_valid(c) or c == player: continue
		var p := xf * Vector2(c.global_position.x, c.global_position.z)
		var off := p - Vector2.ONE * RADIUS
		var far := off.length() > rim
		if far: p = Vector2.ONE * RADIUS + off.normalized() * rim
		if tag_manager.is_out(c):
			_dots.draw_arc(p, 4.0, 0.0, TAU, 12, OUT, 1.5)
			continue
		var k := 0.8 if far else 1.0
		if tag_manager.is_iced(c): # frozen solid: an ice-blue square
			_dots.draw_rect(Rect2(p - Vector2.ONE * 5.0 * k, Vector2.ONE * 10.0 * k), tag_manager.rules.ice_color)
			continue
		if tag_manager.is_torch(c): # a flame on a dark disc
			_dots.draw_circle(p, _FLAME * 0.55 * k, Color(UIKit.CHARCOAL, 0.85))
			var sz := Vector2.ONE * _FLAME * k
			_dots.draw_texture_rect(UIKit.ICON_FIRE, Rect2(p - sz * 0.55, sz), false, TORCH)
			continue
		_dots.draw_circle(p, 4.5 * k, KINDLING)
		_dots.draw_arc(p, 4.5 * k, 0.0, TAU, 12, Color(UIKit.CHARCOAL, 0.7), 1.0)
	# you: an arrow pointing up (your view), ringed red while you're a Torch
	var m := Vector2.ONE * RADIUS
	var arrow := PackedVector2Array([m + Vector2(0, -8), m + Vector2(6, 6), m + Vector2(0, 3), m + Vector2(-6, 6)])
	if tag_manager.is_torch(player): _dots.draw_circle(m, 11.0, Color(TORCH, 0.6))
	_dots.draw_colored_polygon(arrow, YOU)
	_dots.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(UIKit.CHARCOAL, 0.8), 1.2)


func _draw_rim() -> void:
	var m := Vector2.ONE * RADIUS
	_rim.draw_arc(m, RADIUS - 2.0, 0.0, TAU, 96, Color(UIKit.CHARCOAL, 0.9), 4.0)
	_rim.draw_arc(m, RADIUS - 2.0, 0.0, TAU, 96, Color(UIKit.TEXT, 0.85), 1.5)
	# north: where world -z is, an ember tick through the rim and an N inside it
	var view := _view()
	var north := (_xf(view).basis_xform(Vector2(0.0, -1.0))).normalized()
	_rim.draw_line(m + north * (RADIUS - 12.0), m + north * (RADIUS + 3.0), UIKit.EMBER, 4.0)
	var n := m + north * (RADIUS - 24.0)
	_rim.draw_string_outline(UIKit.DISPLAY, n + Vector2(-5.0, 7.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, UIKit.CHARCOAL)
	_rim.draw_string(UIKit.DISPLAY, n + Vector2(-5.0, 7.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.TEXT)
