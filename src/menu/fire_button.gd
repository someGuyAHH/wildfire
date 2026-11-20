"""
Menu button: a slanted charcoal plate with an ember bar on its left edge and a hard shadow. Hovered
or focused (mouse and gamepad share one highlight) it swaps straight to solid ember with dark text:
no animation. Drawn by a child that sits behind the button's own text, so the text stays on top.
"""

class_name FireButton
extends Button

## The bar's colour, and the fill when lit.
@export var accent := UIKit.EMBER
## Font size of the label.
@export var text_size: int = 30

var _back: Control


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	if custom_minimum_size == Vector2.ZERO: custom_minimum_size = Vector2(440.0, 60.0)
	theme_type_variation = &"FireButton" # colours, font and text padding live in the theme
	add_theme_font_size_override(&"font_size", text_size)
	_back = Control.new()
	_back.show_behind_parent = true
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_back)
	_back.draw.connect(on_back_draw)
	for s: Signal in [focus_entered, focus_exited, mouse_entered, mouse_exited]: s.connect(_back.queue_redraw)
	mouse_entered.connect(on_mouse_entered)


func on_mouse_entered() -> void:
	if not disabled: grab_focus() # one highlight for mouse and pad


func is_lit() -> bool:
	return (has_focus() or is_hovered()) and not disabled


func on_back_draw() -> void:
	var lit := is_lit()
	UIKit.draw_plate(_back, Vector2.ZERO, size.x, size.y, accent if lit else UIKit.PANEL,
			UIKit.TEXT if lit else accent, 8.0 if lit else 6.0)
	_draw_extra(_back, lit)


## For subclasses: more drawing on the plate, under the text (the stepper's value).
func _draw_extra(_canvas: Control, _lit: bool) -> void:
	pass
