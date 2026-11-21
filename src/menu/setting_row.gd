class_name SettingRow
extends Control
## One setting in the settings screen: its name on the left and its control on the right, either
## a choice ("‹ Medium ›" over a pip per option) or a slider (track, fill, a little slab for a
## thumb, the number). Focused (keys, pad or the mouse over it) the row lightens with an
## ember bar at its left, and left / right change it; the mouse clicks the arrows or pips, or drags the
## slider. Writes to STG straight away (saved as it goes).

const H := 60.0
const _CTRL_W := 300.0 # the control's width, at the row's right

var label := ""
var key: StringName
var options := PackedStringArray() # a choice (the setting stores the index), or empty: a slider
var lo := 0.0
var hi := 1.0
var step_size := 0.1
var fmt := "%.2f"
var _drag := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, H)
	for s: Signal in [focus_entered, focus_exited]: s.connect(queue_redraw)
	mouse_entered.connect(func() -> void: if not has_focus(): grab_focus())


## A choice between options (stored as the index).
static func choice(label_: String, key_: StringName, options_: PackedStringArray) -> SettingRow:
	var r := SettingRow.new()
	r.label = label_
	r.key = key_
	r.options = options_
	return r


## A slider from lo to hi in steps, shown with fmt.
static func slider(label_: String, key_: StringName, lo_: float, hi_: float, step_: float, fmt_: String) -> SettingRow:
	var r := SettingRow.new()
	r.label = label_
	r.key = key_
	r.lo = lo_
	r.hi = hi_
	r.step_size = step_
	r.fmt = fmt_
	return r


func is_choice() -> bool:
	return not options.is_empty()


func value() -> float:
	return STG.get_value(key)


## The value as words ("Medium", "0.55").
func text_of(v: float) -> String:
	return options[clampi(roundi(v), 0, options.size() - 1)] if is_choice() else fmt % v


func change(by: int) -> void:
	if is_choice(): _apply(clampi(roundi(value()) + by, 0, options.size() - 1))
	else: _apply(value() + by * step_size)


func _apply(v: float) -> void:
	if not is_choice(): v = clampf(snappedf(v, step_size), lo, hi)
	if is_equal_approx(v, value()): return
	STG.set_value(key, v)
	Sound.ui(&"ui_toggle" if is_choice() else &"ui_tick")
	if key == STG.VOL_SFX: Sound.play(&"land_light") # hear what you're setting
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"): change(-1)
	elif event.is_action_pressed(&"ui_right"): change(1)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT: return
		_drag = mb.pressed and not is_choice() and _track().grow(10.0).has_point(mb.position)
		if mb.pressed:
			grab_focus()
			if is_choice(): _click_choice(mb.position)
			elif _drag: _slide_to(mb.position.x)
	elif event is InputEventMouseMotion and _drag: _slide_to((event as InputEventMouseMotion).position.x)
	else: return
	accept_event()


func _click_choice(at: Vector2) -> void:
	var c := _ctrl()
	if at.x < c.position.x + 40.0: change(-1)
	elif at.x > c.end.x - 40.0: change(1)
	else: # a pip
		var n := options.size()
		var pw := _pip_w()
		var x0 := c.get_center().x - (n * pw + (n - 1) * 4.0) * 0.5
		_apply(clampi(floori((at.x - x0) / (pw + 4.0)), 0, n - 1))


func _slide_to(x: float) -> void:
	var t := _track()
	_apply(lerpf(lo, hi, clampf((x - t.position.x) / t.size.x, 0.0, 1.0)))


func _ctrl() -> Rect2:
	return Rect2(size.x - _CTRL_W - 24.0, 0.0, _CTRL_W, H)


func _track() -> Rect2:
	var c := _ctrl()
	return Rect2(c.position.x, H * 0.5 - 4.0, c.size.x - 76.0, 8.0)


func _pip_w() -> float:
	return clampf(120.0 / options.size(), 14.0, 28.0)


func _draw() -> void:
	var lit := has_focus()
	if lit:
		draw_rect(Rect2(Vector2.ZERO, size), UIKit.SLAB_FOCUS)
		draw_rect(Rect2(0.0, 0.0, 5.0, H), UIKit.EMBER)
	var base := (H + UIKit.BODY.get_ascent(20) - UIKit.BODY.get_descent(20)) * 0.5
	draw_string(UIKit.BODY, Vector2(46.0, base), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - _CTRL_W - 90.0, 20,
			UIKit.TEXT if lit else Color(UIKit.TEXT, 0.82))
	var c := _ctrl()
	var v := value()
	if is_choice():
		var i := clampi(roundi(v), 0, options.size() - 1)
		var t := options[i]
		var font := UIKit.DISPLAY_BOLD
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, Vector2(c.get_center().x - tw * 0.5, H * 0.5 + 4.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.TEXT)
		var arrow := UIKit.EMBER if lit else UIKit.MUTED
		var spent := Color(UIKit.TEXT, 0.15) # at the end of the list: nowhere to go
		draw_string(font, Vector2(c.position.x + 10.0, H * 0.5 + 9.0), "‹", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, arrow if i > 0 else spent)
		draw_string(font, Vector2(c.end.x - 22.0, H * 0.5 + 9.0), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, arrow if i < options.size() - 1 else spent)
		var n := options.size()
		var pw := _pip_w()
		var x0 := c.get_center().x - (n * pw + (n - 1) * 4.0) * 0.5
		for k: int in n:
			draw_rect(Rect2(x0 + k * (pw + 4.0), H * 0.5 + 14.0, pw, 4.0),
					(UIKit.EMBER if lit else UIKit.TEXT) if k == i else Color(UIKit.TEXT, 0.18))
	else:
		var t := _track()
		var p := clampf((v - lo) / (hi - lo), 0.0, 1.0)
		draw_rect(t, UIKit.SLAB_SIDE)
		draw_rect(Rect2(t.position, Vector2(t.size.x * p, t.size.y)), UIKit.EMBER if lit else UIKit.MUTED)
		UIKit.draw_slab(self, Vector2(t.position.x + t.size.x * p - 7.0, H * 0.5 - 15.0), 14.0, 26.0, 4.0, false, 0.0, UIKit.TEXT, false)
		var s := fmt % v
		var sw := UIKit.DISPLAY_BOLD.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(UIKit.DISPLAY_BOLD, Vector2(c.end.x - sw, H * 0.5 + 8.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.TEXT)
