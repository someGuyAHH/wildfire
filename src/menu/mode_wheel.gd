class_name ModeWheel
extends Control
## The mode select's carousel, in 3D: the tall ModeCards stand round a ring whose axis is behind
## the middle of the screen. The chosen card faces you in front; its neighbours stand either side
## further back, turned mostly toward you, dimmer; the rest wait behind. Changing mode turns the
## ring. Each card is drawn once into its own SubViewport and shown on a quad in a small 3D world of
## its own (transparent, over the menu). Lays itself out from its size, in canvas pixels: at the
## front card's plane one world unit is 100 px.
## Left / right (keys, d-pad, stick), the mouse wheel over the cards, or clicking a side card turn
## it; clicking the front card (or accept) emits confirmed.

signal selected(index: int)
signal confirmed

const _PX := 100.0          # canvas px per world unit at the front card's plane
const _FOV := 40.0
const _FACE := 0.8          # how far a side card turns back toward you (of its place on the ring)
const _RING := 1.05         # ring radius, in front-card widths
const _TURN_TIME := 0.5
const _BACK_COLOR := Color(0.11, 0.095, 0.085)

const _SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D card : source_color, filter_linear_mipmap;
uniform vec3 back_color : source_color;
uniform float fade = 1.0;
uniform float dim = 1.0;
void fragment() {
	vec4 c = texture(card, UV);
	if (!FRONT_FACING) c.rgb = back_color; // its back: plain charcoal
	ALBEDO = c.rgb * dim;
	ALPHA = c.a * fade;
}
"""

## Cards drawn at this size (1: ModeCard.SIZE); front_top: the front card's top edge (px; < 0: centred).
var card_scale := 1.0
var front_top := -1.0
var index := 0
var _turn := 0.0 # which card faces front, eased toward index
var _tween: Tween
var _cards: Array[ModeCard] = []
var _card_vps: Array[SubViewport] = []
var _arms: Array[Node3D] = [] # one per card, turning about the ring's axis
var _mats: Array[ShaderMaterial] = []
var _view: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _axis: Node3D
var _hit: Control      # over the front card: click to go on; the mouse wheel turns
var _hit_side: Array[Control] = [] # over the side cards: click to turn to them
## How many frames asked the 3D ring to be drawn (it is drawn only when something in it changes).
var renders := 0
var _live := true
var _again := 0 # frames still to draw after the last change (the cards' textures and a resized view lag a frame)
var _last_kick := -1


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED # drawn on request only: see request_render
	_view.add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = _FOV
	_vp.add_child(_cam)
	_axis = Node3D.new()
	_vp.add_child(_axis)
	_hit = _hit_area(0)
	_hit_side = [_hit_area(-1), _hit_area(1)]
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)


func _hit_area(side: int) -> Control:
	var h := Control.new()
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	h.gui_input.connect(_on_hit_input.bind(side))
	add_child(h)
	return h


## Adds a card (in order).
func add_card(card: ModeCard) -> void:
	var cvp := SubViewport.new()
	cvp.transparent_bg = true
	cvp.disable_3d = true
	cvp.size = Vector2i(ModeCard.SIZE + Vector2(12.0, 12.0)) # (room for its shadow)
	cvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(cvp)
	cvp.add_child(card)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = _SHADER
	mat.set_shader_parameter(&"card", cvp.get_texture())
	mat.set_shader_parameter(&"back_color", _BACK_COLOR)
	var quad := QuadMesh.new()
	quad.size = Vector2(cvp.size) * card_scale / _PX
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var arm := Node3D.new()
	arm.add_child(mi)
	_axis.add_child(arm)
	_cards.append(card)
	_card_vps.append(cvp)
	_arms.append(arm)
	_mats.append(mat)
	_layout() # (asks for a draw)


## Whether the 3D ring may be drawn at all (off: it keeps showing its last picture, for when it is only
## being moved about, like while the setup screen falls away).
func set_live(on: bool) -> void:
	_live = on
	if on:
		request_render()
	else:
		_again = 0
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Draws the 3D ring now and for the next two frames (a card texture or a resized view lands a frame late).
## Everything that changes the ring calls this; while idle, or hidden, nothing is drawn.
func request_render() -> void:
	if not _live: return
	_again = 2
	set_process(true)
	_kick()


func _kick() -> void:
	var f := Engine.get_process_frames()
	if f == _last_kick or not is_visible_in_tree(): return
	_last_kick = f
	renders += 1
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _process(_delta: float) -> void:
	if _again <= 0:
		set_process(false)
		return
	_again -= 1
	_kick()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		request_render()
	else:
		_again = 0
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Turns to card i (the short way round); animate false jumps there.
func select(i: int, animate: bool = true) -> void:
	var n := _cards.size()
	if n == 0: return
	i = posmod(i, n)
	var target := float(i) + roundf((_turn - float(i)) / n) * n
	index = i
	for k: int in n:
		_cards[k].set_selected(k == i)
		_card_vps[k].render_target_update_mode = SubViewport.UPDATE_ONCE
	if _tween: _tween.kill()
	if animate:
		Sound.ui(&"ui_turn")
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_turn, _turn, target, _TURN_TIME)
	else:
		_set_turn(target)
	queue_redraw()
	request_render()
	selected.emit(i)


func step(by: int) -> void:
	select(index + by)


## Spins in from a card away (when the screen opens).
func swing_in() -> void:
	_set_turn(index - 1.0)
	select(index)


func _set_turn(v: float) -> void:
	_turn = v
	_place()
	request_render()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"): step(-1)
	elif event.is_action_pressed(&"ui_right"): step(1)
	elif event.is_action_pressed(&"ui_accept"): confirmed.emit()
	else: return
	accept_event()


func _on_hit_input(event: InputEvent, side: int) -> void:
	var mb := event as InputEventMouseButton
	if not mb or not mb.pressed: return
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			grab_focus()
			if side == 0: confirmed.emit()
			else: step(side)
		MOUSE_BUTTON_WHEEL_UP: step(-1)
		MOUSE_BUTTON_WHEEL_DOWN: step(1)
		_: return
	accept_event()


## Where the front card sits on screen (canvas px): in the middle.
func front_rect() -> Rect2:
	var sz := ModeCard.SIZE * card_scale
	return Rect2(Vector2((size.x - sz.x) * 0.5, front_top if front_top >= 0.0 else (size.y - sz.y) * 0.5), sz)


# the camera so that the front card's plane (z = 0) maps 100 px to a unit, (0, 0) at the top
# left; the ring's axis behind the front card's middle, a card's width (and a bit) back
func _layout() -> void:
	if size.x <= 0.0: return
	var d := (size.y / _PX) * 0.5 / tan(deg_to_rad(_FOV) * 0.5)
	_cam.position = Vector3(size.x * 0.5 / _PX, -size.y * 0.5 / _PX, d)
	var r := front_rect()
	var radius := r.size.x * _RING / _PX
	_axis.position = Vector3(r.get_center().x / _PX, -r.get_center().y / _PX, -radius)
	# (the quad holds the card plus its shadow margin: shift it so the card itself is centred)
	for arm: Node3D in _arms: (arm.get_child(0) as Node3D).position = Vector3(6.0 * card_scale / _PX, -6.0 * card_scale / _PX, radius)
	_hit.position = r.position
	_hit.size = r.size
	for k: int in 2: # the side cards' rough footprint either side of the front one
		var w := r.size.x * 0.6
		_hit_side[k].size = Vector2(w, r.size.y * 0.8)
		_hit_side[k].position = Vector2(r.position.x - w if k == 0 else r.end.x, r.position.y + r.size.y * 0.1)
	_place()
	queue_redraw()
	request_render()


# off = card - turn, wrapped to -n/2 .. n/2: 0 in front, ±1 either side, the rest behind
func _place() -> void:
	var n := _cards.size()
	if n == 0: return
	var step_deg := 360.0 / n
	for i: int in n:
		var off := fposmod(i - _turn + n * 0.5, n) - n * 0.5
		var deg := off * step_deg
		_arms[i].rotation_degrees.y = deg
		(_arms[i].get_child(0) as Node3D).rotation_degrees.y = -deg * _FACE # turned back toward you
		var a := absf(off)
		_mats[i].set_shader_parameter(&"dim", lerpf(1.0, 0.5, clampf(a, 0.0, 1.0)))
		_mats[i].set_shader_parameter(&"fade", 1.0 - smoothstep(1.2, 1.8, a))
		_arms[i].visible = a < 1.8
		(_arms[i].get_child(0) as GeometryInstance3D).sorting_offset = -a


# under the front card a dot per mode (the chosen one long and ember)
func _draw() -> void:
	var r := front_rect()
	var n := _cards.size()
	var y := r.end.y + 26.0
	var w := 26.0
	var wide := 52.0
	var total := (n - 1) * (w + 8.0) + wide
	var x := r.get_center().x - total * 0.5
	for i: int in n:
		var ww := wide if i == index else w
		draw_rect(Rect2(x, y, ww, 5.0), UIKit.EMBER if i == index else Color(UIKit.TEXT, 0.25))
		x += ww + 8.0
