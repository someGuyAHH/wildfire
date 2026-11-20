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


# the value, right-aligned in the display font; the arrows only where it can still go
func _draw_extra(canvas: Control, lit: bool) -> void:
	var value := options[index] if index < options.size() else ""
	var font := UIKit.DISPLAY_BOLD
	var fs := text_size
	var ink := UIKit.CHARCOAL if lit else UIKit.TEXT
	var dim := Color(ink, 0.55) if lit else UIKit.EMBER
	var right := size.x - size.y * UIKit.SKEW - 24.0
	var base := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var arrow_w := font.get_string_size("›", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var value_w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := right - arrow_w
	if wrap_around or index < options.size() - 1: canvas.draw_string(font, Vector2(x, base), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	x -= _ARROW_GAP + value_w
	canvas.draw_string(font, Vector2(x, base), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	x -= _ARROW_GAP + arrow_w
	if wrap_around or index > 0: canvas.draw_string(font, Vector2(x, base), "‹", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
