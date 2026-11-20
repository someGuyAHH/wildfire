class_name FlameTitle
extends Control
## A title whose letters burn (the logo and the screens' titles; not HUD text): flat bands of flame
## lick up off the tops of the letters (assets/gdshaders/flame_title.gdshader). The text is drawn
## once, white, into a SubViewport with headroom above it, and the shader adds the fire. Takes the
## letters' size in a layout; the flames spill up over whatever is above.

const _SHADER := preload("res://assets/gdshaders/flame_title.gdshader")
const _HEADROOM := 0.75 # flame room above the letters, as a fraction of the font size
const _PAD := 0.18      # room left and right (the italic leans out), same

var text := ""
var font_size := 64
var _vp: SubViewport
var _label: Label
var _view: TextureRect


## The words and their size (call again to change them).
func setup(text_: String, font_size_: int) -> void:
	text = text_
	font_size = font_size_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _vp: _build()
	_label.text = text
	_label.add_theme_font_size_override(&"font_size", font_size)
	var glyphs := UIKit.DISPLAY.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(font_size * _PAD, font_size * _HEADROOM)
	_vp.size = Vector2i((glyphs + Vector2(pad.x * 2.0, pad.y + font_size * 0.1)).ceil())
	_label.position = pad
	_label.size = glyphs
	_view.position = -pad
	_view.size = Vector2(_vp.size)
	custom_minimum_size = glyphs
	(_view.material as ShaderMaterial).set_shader_parameter(&"reach", pad.y / float(_vp.size.y))
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_label = Label.new()
	_label.add_theme_font_override(&"font", UIKit.DISPLAY)
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	_vp.add_child(_label)
	_view = TextureRect.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture = _vp.get_texture()
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	_view.material = mat
	add_child(_view)
