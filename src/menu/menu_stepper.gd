"""
One-control value picker for menus: the label on the left, "‹ value ›" on the right of one plate.
Left/right (keys, d-pad, stick) change it while focused; clicking the left/right half steps it too.
Emits value_changed(index) with the index into `options`.
"""

class_name MenuStepper
extends FireButton

signal value_changed(index: int)

const _ARROW_GAP := 18.0

var title := ""
var options: PackedStringArray = []
var index := 0
var wrap_around := false


## Sets the label, the choices and which one is showing.
func setup(title_: String, options_: PackedStringArray, start_index: int, wrap_: bool = false) -> void:
	title = title_
	options = options_
	wrap_around = wrap_
	index = clampi(start_index, 0, maxi(options.size() - 1, 0))
	text = title
	if _back: _back.queue_redraw()


## Moves the choice by `step` (clamped, or wrapping if wrap_around). Returns true if it changed.
func step_by(step: int) -> bool:
	if options.is_empty(): return false
	var n := options.size()
	var next := posmod(index + step, n) if wrap_around else clampi(index + step, 0, n - 1)
	if next == index: return false
	index = next
	_back.queue_redraw()
	Sound.ui(&"ui_tick")
	value_changed.emit(index)
	return true


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"):
		step_by(-1)
		accept_event() # left/right change the value, they don't move focus
	elif event.is_action_pressed(&"ui_right"):
		step_by(1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		step_by(-1 if (event as InputEventMouseButton).position.x < size.x * 0.5 else 1)
		accept_event()


# the value right-aligned in the display font, the arrows only where it can still go, and under
# a short list a row of pips (which one of how many)
func _draw_extra(canvas: Control, lit: bool, at: Vector2) -> void:
	var value := options[index] if index < options.size() else ""
	var font := UIKit.DISPLAY_BOLD
	var fs := text_size
	var ink := UIKit.CHARCOAL if lit else UIKit.TEXT
	var dim := Color(ink, 0.55) if lit else UIKit.EMBER
	var pips := options.size() > 1 and options.size() <= 6
	var right := at.x + size.x - 24.0
	var mid := at.y + size.y * 0.5 - (4.0 if pips else 0.0)
	var base := mid + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var arrow_w := font.get_string_size("›", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var value_w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box_w := maxf(value_w, 120.0) # the value's slot, so the arrows don't jump about
	var x := right - arrow_w
	if wrap_around or index < options.size() - 1: canvas.draw_string(font, Vector2(x, base), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	var slot_l := x - _ARROW_GAP - box_w
	canvas.draw_string(font, Vector2(slot_l + (box_w - value_w) * 0.5, base), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	if wrap_around or index > 0: canvas.draw_string(font, Vector2(slot_l - _ARROW_GAP - arrow_w, base), "‹", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	if pips:
		var n := options.size()
		var pw := 16.0
		var gap := 4.0
		var total := n * pw + (n - 1) * gap
		var px := slot_l + (box_w - total) * 0.5
		var py := base + 8.0
		for i: int in n:
			var c := (UIKit.CHARCOAL if lit else UIKit.EMBER) if i == index else Color(ink, 0.25)
			canvas.draw_rect(Rect2(px + i * (pw + gap), py, pw, 4.0), c)
