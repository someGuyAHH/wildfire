"""
Menu button: a slanted dark bar that sweeps full of fire with a glowing accent edge when
hovered or focused (mouse and gamepad share one highlight). Drawn by a child that sits behind
the button's own text, so the text always stays on top.
"""

class_name FireButton
extends Button

## Glow / fill / pressed-text color.
@export var accent := Color(1.0, 0.52, 0.1)
## Font size of the label.
@export var text_size: int = 30

const _ANIM_SPEED  := 7.0
const _SKEW        := 0.35   # slant, as a fraction of height
const _REST_REACH  := 0.84   # bar width at rest, as a fraction of the button

var _hover := 0.0
var _back: Control


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	if custom_minimum_size == Vector2.ZERO: custom_minimum_size = Vector2(400.0, 62.0)
	theme_type_variation = &"FireButton" # colors, outline and text padding live in the theme
	add_theme_font_size_override(&"font_size", text_size)
	add_theme_color_override(&"font_hover_pressed_color", accent)
	add_theme_color_override(&"font_pressed_color", accent)
	_back = Control.new()
	_back.show_behind_parent = true
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_back)
	_back.draw.connect(on_back_draw)
	mouse_entered.connect(on_mouse_entered)
	pressed.connect(on_pressed)


func _process(delta: float) -> void:
	var lit := (has_focus() or is_hovered()) and not disabled
	var next := move_toward(_hover, 1.0 if lit else 0.0, delta * _ANIM_SPEED)
	if next == _hover: return
	_hover = next
	_back.queue_redraw()


func on_mouse_entered() -> void:
	if not disabled: grab_focus() # one highlight for mouse and pad


func on_pressed() -> void:
	# a quick flash so the press reads even when the screen changes right away
	_hover = 1.0
	var tw := create_tween()
	tw.tween_property(self, ^"modulate", Color(1.6, 1.3, 1.0), 0.05)
	tw.tween_property(self, ^"modulate", Color.WHITE, 0.15)


func on_back_draw() -> void:
	var w := size.x
	var h := size.y
	var skew := h * _SKEW
	var e := ease(_hover, 0.5)
	var reach := lerpf(_REST_REACH, 1.0, e) * w
	# backdrop
	_back.draw_colored_polygon(PackedVector2Array([Vector2(skew, 0), Vector2(reach, 0),
			Vector2(reach - skew, h), Vector2(0, h)]), Color(0.05, 0.04, 0.05, lerpf(0.6, 0.88, e)))
	# fire sweep, fading toward the right
	if e > 0.01:
		var fill := skew + (reach - skew) * e
		var hot := Color(accent, 0.62 * e)
		var cold := Color(accent, 0.0)
		_back.draw_polygon(PackedVector2Array([Vector2(skew, 0), Vector2(fill, 0), Vector2(fill - skew, h), Vector2(0, h)]),
				PackedColorArray([hot, cold, cold, hot]))
	# accent edge, thicker when lit
	var bar := lerpf(4.0, 11.0, e)
	_back.draw_colored_polygon(PackedVector2Array([Vector2(skew, 0), Vector2(skew + bar, 0),
			Vector2(bar, h), Vector2(0, h)]), Color(accent, lerpf(0.75, 1.0, e)))
