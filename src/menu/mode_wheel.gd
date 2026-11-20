class_name ModeWheel
extends Control
## The mode select's carousel, in 3D: the tall ModeCards are panels of a revolving door whose
## hinge stands far right, on a long arm: a card swinging out passes through the camera. The chosen card faces you on the left; the ones before it wait
## behind, swung back into the depth (peeking out toward the hinge). Going back, the front card
## swings toward you and off round to the right while the one behind turns to face front; going
## forward does the reverse. Each card is drawn once into its own SubViewport and shown on a quad
## in a small 3D world of its own (transparent, over the menu). Lays itself out from its size, in
## canvas pixels: at the card plane one world unit is 100 px.
## Left / right (keys, d-pad, stick), the arrows under the card or the mouse wheel over it turn
## it; clicking the front card (or accept) emits confirmed.

signal selected(index: int)
signal confirmed

const _PX := 100.0         # canvas px per world unit at the card plane
const _FOV := 45.0         # wide enough that a card swinging out sweeps right through the camera
const _BEHIND_STEP := 22.0 # degrees each waiting card is swung back
const _GONE_ANGLE := -165.0 # where a card that went past ends up (round to the right, its back to you)
const _TURN_TIME := 0.6
const _LEFT := 112.0       # px, the front card's left edge
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

var index := 0
var _turn := 0.0 # which card faces front, eased toward index
var _tween: Tween
var _cards: Array[ModeCard] = []
var _card_vps: Array[SubViewport] = []
var _arms: Array[Node3D] = []   # one per card, turning about the hinge
var _mats: Array[ShaderMaterial] = []
var _view: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _hinge: Node3D
var _hit: Control # over the front card: clicks and the mouse wheel


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
	_view.add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = _FOV
	_vp.add_child(_cam)
	_hinge = Node3D.new()
	_vp.add_child(_hinge)
	_hit = Control.new()
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.size = ModeCard.SIZE
	_hit.gui_input.connect(_on_hit_input)
	add_child(_hit)
	resized.connect(_layout)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


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
	quad.size = Vector2(cvp.size) / _PX
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var arm := Node3D.new()
	arm.add_child(mi)
	_hinge.add_child(arm)
	_cards.append(card)
	_card_vps.append(cvp)
	_arms.append(arm)
	_mats.append(mat)
	_layout()


## Turns to card i (wrapping round); animate false jumps there.
func select(i: int, animate: bool = true) -> void:
	var n := _cards.size()
	if n == 0: return
	i = posmod(i, n)
	var target := float(i) + roundf((_turn - float(i)) / n) * n # the short way round
	index = i
	for k: int in n:
		_cards[k].set_selected(k == i)
		_card_vps[k].render_target_update_mode = SubViewport.UPDATE_ONCE
	if _tween: _tween.kill()
	if animate:
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_turn, _turn, target, _TURN_TIME)
	else:
		_set_turn(target)
	selected.emit(i)


func step(by: int) -> void:
	select(index + by)


## The front card swings in from the right (when the screen opens).
func swing_in() -> void:
	_set_turn(index - 1.0)
	select(index)


func _set_turn(v: float) -> void:
	_turn = v
	_place()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"): step(-1)
	elif event.is_action_pressed(&"ui_right"): step(1)
	elif event.is_action_pressed(&"ui_accept"): confirmed.emit()
	else: return
	accept_event()


func _on_hit_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if not mb or not mb.pressed: return
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			grab_focus()
			confirmed.emit()
		MOUSE_BUTTON_WHEEL_UP: step(-1)
		MOUSE_BUTTON_WHEEL_DOWN: step(1)
		_: return
	_hit.accept_event()


## Where the front card sits on screen (canvas px).
func front_rect() -> Rect2:
	return Rect2(Vector2(_LEFT, (size.y - ModeCard.SIZE.y) * 0.5), ModeCard.SIZE)


# the camera so that the card plane (z = 0) maps 100 px to a unit, (0, 0) at the top left; the
# hinge out on the right of the screen (the arm long enough that a card swinging out sweeps past
# the camera)
func _layout() -> void:
	if size.x <= 0.0: return
	var d := (size.y / _PX) * 0.5 / tan(deg_to_rad(_FOV) * 0.5)
	_cam.position = Vector3(size.x * 0.5 / _PX, -size.y * 0.5 / _PX, d)
	var r := front_rect()
	var hinge_x := size.x * 0.78
	_hinge.position = Vector3(hinge_x / _PX, -r.get_center().y / _PX, 0.0)
	# each card hangs left of the hinge, its centre this far out
	var reach := (hinge_x - r.get_center().x) / _PX
	for arm: Node3D in _arms: (arm.get_child(0) as Node3D).position = Vector3(-reach, 0.0, 0.0)
	_hit.position = r.position
	_place()
	queue_redraw()


# off = card - turn: 0 faces front; below 0 waits behind, swung back; above 0 has gone round to the right
func _place() -> void:
	var n := _cards.size()
	for i: int in n:
		var off := fposmod(i - _turn + n * 0.5, n) - n * 0.5
		var deg := -off * _BEHIND_STEP if off <= 0.0 else off * _GONE_ANGLE
		_arms[i].rotation_degrees.y = -deg # (+ swings the card's far edge away from you)
		var fade := 1.0 - smoothstep(0.55, 1.0, off) if off > 0.0 else 1.0 - smoothstep(2.0, 2.6, -off)
		_mats[i].set_shader_parameter(&"fade", fade)
		_mats[i].set_shader_parameter(&"dim", lerpf(1.0, 0.45, clampf(-off, 0.0, 1.0)))
		_arms[i].visible = fade > 0.01
		_arms[i].get_child(0).set(&"sorting_offset", -absf(off))


# ember ticks either side of the front card while the carousel has focus
func _draw() -> void:
	var r := front_rect()
	var w := 6.0 if has_focus() else 3.0
	var y := r.get_center().y
	draw_line(Vector2(r.position.x - 40.0, y), Vector2(r.position.x - 14.0, y), UIKit.EMBER, w)
