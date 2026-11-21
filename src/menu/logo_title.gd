class_name LogoTitle
extends Control
## The game's logo: upright bold sans, a vertical gradient from deep orange to amber, a thin dark
## outline and a soft dark drop shadow. Three stacked labels (shadow, outline, fill), so the
## gradient stays on the letters only. Takes the text's size in a layout.

const _SHADER := preload("res://assets/gdshaders/logo_gradient.gdshader")
const _OUTLINE := Color(0.10, 0.03, 0.0, 1.0)
const _SHADOW := Color(0.0, 0.0, 0.0, 0.35)

var text := ""


## The words and their size.
func setup(text_: String, font_size: int, top: Color = Color("ff5a14"), bottom: Color = UIKit.GOLD) -> void:
	text = text_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := UIKit.BODY_BOLD
	var glyphs := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	glyphs.y = font.get_height(font_size)
	custom_minimum_size = glyphs
	size = glyphs
	var outline := maxi(roundi(font_size * 0.035), 2)
	# soft shadow: wide faint outline, pushed down and right
	_add(font, font_size, _SHADOW, _SHADOW, outline * 3, Vector2(font_size * 0.03, font_size * 0.045))
	_add(font, font_size, _OUTLINE, _OUTLINE, outline, Vector2.ZERO)
	var fill := _add(font, font_size, Color.WHITE, Color(0, 0, 0, 0), 0, Vector2.ZERO)
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter(&"top", top)
	mat.set_shader_parameter(&"bottom", bottom)
	mat.set_shader_parameter(&"height", glyphs.y)
	fill.material = mat


func _add(font: Font, font_size: int, color: Color, outline_color: Color, outline: int, offset: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", outline_color)
	l.add_theme_constant_override(&"outline_size", outline)
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_offset_y", 0)
	l.position = offset
	l.size = custom_minimum_size
	add_child(l)
	return l
