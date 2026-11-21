class_name MenuModal
extends Control
## "Are you sure?" over a menu: the screen dims and a slab flips up in the middle with a title, a
## line of text and a row of slab buttons. Left / right pick, accept presses, Esc / B (or a click on
## the dim) cancels. Works while the game is paused.

signal closed

const _WIDTH := 640.0
const _FLIP_TIME := 0.32

var _dim: ColorRect
var _panel: Control
var _title: Label
var _text: Label
var _row: HBoxContainer
var _buttons: Array[FireButton] = []
var _cancel: Callable
var _refocus: Control # had the focus before the dialog opened


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	z_index = 50
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.025, 0.02, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(func() -> void: UIKit.draw_slab(_panel, Vector2.ZERO, _panel.size.x, _panel.size.y, 16.0, false, 0.0))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.position = Vector2(40.0, 36.0)
	box.custom_minimum_size.x = _WIDTH - 80.0
	box.add_theme_constant_override(&"separation", 12)
	box.resized.connect(func() -> void: _panel.size = Vector2(_WIDTH, box.size.y + 72.0); _center())
	_panel.add_child(box)
	_title = UIKit.label("", 44, UIKit.TEXT, UIKit.DISPLAY)
	_title.theme_type_variation = &""
	box.add_child(_title)
	_text = UIKit.label("", 20, UIKit.MUTED)
	_text.theme_type_variation = &""
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)
	box.add_child(UIKit.gap(16.0))
	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 16)
	box.add_child(_row)
	resized.connect(_center)


## Opens it. buttons: [[label, Callable], ...], the first gets the focus; cancel runs on Esc / a
## click outside (it should do what the safe button does).
func ask(title: String, text: String, buttons: Array, cancel: Callable) -> void:
	_title.text = title
	_text.text = text
	_cancel = cancel
	for b: FireButton in _buttons: b.queue_free()
	_buttons.clear()
	for spec: Array in buttons:
		var b := FireButton.new()
		b.text = spec[0]
		b.text_size = 26
		b.centered = true
		b.custom_minimum_size = Vector2(0.0, 60.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_choose.bind(spec[1] as Callable))
		_row.add_child(b)
		_buttons.append(b)
	var n := _buttons.size()
	for i: int in n: # left / right walk the row and stop at its ends; Tab goes round it, never behind
		var b := _buttons[i]
		b.focus_next = b.get_path_to(_buttons[(i + 1) % n])
		b.focus_previous = b.get_path_to(_buttons[(i - 1 + n) % n])
		b.focus_neighbor_left = b.get_path_to(_buttons[maxi(i - 1, 0)])
		b.focus_neighbor_right = b.get_path_to(_buttons[mini(i + 1, _buttons.size() - 1)])
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
	_refocus = get_viewport().gui_get_focus_owner()
	visible = true
	Sound.ui(&"ui_open")
	_buttons[0].grab_focus.call_deferred()
	# flips up into place
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(1.0, 0.15)
	_panel.modulate.a = 0.0
	_dim.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, ^"scale", Vector2.ONE, _FLIP_TIME)
	tw.tween_property(_panel, ^"modulate:a", 1.0, _FLIP_TIME * 0.5)
	tw.tween_property(_dim, ^"modulate:a", 1.0, _FLIP_TIME * 0.6)


func is_open() -> bool:
	return visible


func _center() -> void:
	_panel.position = (size - _panel.size) * 0.5
	_panel.pivot_offset = _panel.size * 0.5


func _choose(then: Callable) -> void:
	_close()
	then.call()


func _close() -> void:
	visible = false
	Sound.ui(&"ui_close")
	if is_instance_valid(_refocus) and _refocus.is_visible_in_tree(): _refocus.grab_focus()
	closed.emit()


func _input(event: InputEvent) -> void:
	# while open, nothing behind it hears Esc first
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		_choose(_cancel)


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT: _choose(_cancel)
