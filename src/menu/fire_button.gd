"""
Menu button: a charcoal slab with some thickness. Hovered or focused (mouse and gamepad share one
highlight) it turns into a hot ember slab and lifts toward you (up and a little right, quickly
eased), its text dark; `sub` then shows a line on its right (on a centred button it sits under the title instead).
Draws its own words (so they lift with it): the Button's text only sizes it and names it.
"""

class_name FireButton
extends Button

## The hot slab's colour.
@export var accent := UIKit.EMBER
## Font size of the label.
@export var text_size: int = 30
## A line shown on the right of the slab while it's lit ("Pick a mode and a map").
@export var sub := ""
## The words centred on the slab (else at its left).
@export var centered := false
## Always the hot slab (PLAY, the open tab); lit it still lifts.
@export var hot := false:
	set(v):
		hot = v
		if _back: _back.queue_redraw()

const _LIFT := Vector2(14.0, -6.0) # px the front moves when lit
const _DEPTH := 8.0                # slab thickness at rest (+6 when lit)
const _EASE := 12.0                # how fast it lifts / settles

var _back: Control
var _lift := 0.0


func _ready() -> void:
	flat = true
	if custom_minimum_size == Vector2.ZERO: custom_minimum_size = Vector2(440.0, 60.0)
	theme_type_variation = &"FireButton" # (the theme hides the Button's own text: drawn below)
	add_theme_font_size_override(&"font_size", text_size)
	_back = Control.new()
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_back)
	_back.draw.connect(on_back_draw)
	for s: Signal in [focus_entered, focus_exited, mouse_entered, mouse_exited]: s.connect(set_process.bind(true))
	mouse_entered.connect(on_mouse_entered)
	set_process(false)


func on_mouse_entered() -> void:
	if not disabled and focus_mode != Control.FOCUS_NONE: grab_focus() # one highlight for mouse and pad


func is_lit() -> bool:
	return (has_focus() or is_hovered()) and not disabled


func _process(delta: float) -> void:
	var target := 1.0 if is_lit() else 0.0
	_lift = move_toward(_lift, target, delta * _EASE * maxf(absf(target - _lift), 0.15))
	if absf(_lift - target) < 0.002:
		_lift = target
		set_process(false)
	_back.queue_redraw()


## The slab's front offset now (subclasses draw on it).
func lift_offset() -> Vector2:
	return _LIFT * _lift


func on_back_draw() -> void:
	var lit := is_lit()
	var at := lift_offset()
	UIKit.draw_slab(_back, at, size.x, size.y, _DEPTH + 6.0 * _lift, lit or hot)
	var font := get_theme_font(&"font")
	var ink := UIKit.CHARCOAL if lit or hot else UIKit.TEXT
	var stacked := centered and sub != "" # a centred button's sub sits under its title, always shown
	var base := at.y + (size.y + font.get_ascent(text_size) - font.get_descent(text_size)) * 0.5 - (9.0 if stacked else 0.0)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	var x := at.x + 28.0 + size.y * UIKit.SLAB_SKEW * 0.5
	if centered: x = at.x + (size.x - tw) * 0.5
	_back.draw_string(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, ink)
	if stacked:
		var fs := 16
		var sw := UIKit.BODY.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_back.draw_string(UIKit.BODY, Vector2(at.x + (size.x - sw) * 0.5, base + 24.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(ink, 0.8))
	elif sub != "" and _lift > 0.5:
		var fs := 16
		var sw := UIKit.BODY.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var sb := at.y + (size.y + UIKit.BODY.get_ascent(fs) - UIKit.BODY.get_descent(fs)) * 0.5
		_back.draw_string(UIKit.BODY, Vector2(at.x + size.x - 24.0 - sw, sb), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(UIKit.CHARCOAL, (_lift - 0.5) * 2.0 * 0.8))
	_draw_extra(_back, lit or hot, at)


## For subclasses: more drawing on the slab's front (at: its offset), over it.
func _draw_extra(_canvas: Control, _lit: bool, _at: Vector2) -> void:
	pass
