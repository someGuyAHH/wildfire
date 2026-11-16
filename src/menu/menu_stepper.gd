"""
One-control value picker for menus: "LABEL   ‹  value  ›" in a single fire bar. Left/right
(keys, d-pad, stick) change it while focused; clicking the left/right half steps it too.
Emits value_changed(index) with the index into `options`.
"""

class_name MenuStepper
extends FireButton

signal value_changed(index: int)

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
	_refresh()


## Moves the choice by `step` (clamped, or wrapping if wrap_around). Returns true if it changed.
func step_by(step: int) -> bool:
	if options.is_empty(): return false
	var n := options.size()
	var next := posmod(index + step, n) if wrap_around else clampi(index + step, 0, n - 1)
	if next == index: return false
	index = next
	_refresh()
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


func _refresh() -> void:
	var value := options[index] if index < options.size() else ""
	var left := "‹" if wrap_around or index > 0 else " "
	var right := "›" if wrap_around or index < options.size() - 1 else " "
	text = "%s      %s   %s   %s" % [title, left, value, right]
