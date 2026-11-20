"""
A tall game-mode card for the mode wheel (ModeWheel): the mode's picture (baked by
tools/mapgen/mode_art.gd) filling it, darkening toward the bottom where the info sits: its number,
tags, name and blurb. A bar of the mode's colour along the top, outlined in it while chosen, and a
hard shadow. The wheel moves, turns and scales it; clicking it or scrolling over it tells the wheel.
"""

class_name ModeCard
extends Control

signal clicked
## +1 / -1: the mouse wheel turned over the card.
signal scrolled(step: int)

const SIZE := Vector2(480.0, 744.0)
const _PAD := 32.0

var _outline: Panel
var _outline_style: StyleBoxFlat


## Fills the card: number / count ("01 / 04"), the words, the picture and the mode's colour.
func setup(number: int, count: int, title: String, blurb: String, tags: String, picture: Texture2D, accent: Color) -> void:
	size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shadow := ColorRect.new()
	shadow.color = UIKit.SHADOW
	shadow.size = SIZE
	shadow.position = Vector2(10.0, 10.0)
	_quiet(shadow)
	var frame := Control.new() # the picture and the shading are clipped to the card
	frame.size = SIZE
	frame.clip_contents = true
	_quiet(frame)
	var pic := TextureRect.new()
	pic.texture = picture
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size = SIZE
	_quiet(pic, frame)
	var shade := TextureRect.new() # clear at the top, charcoal behind the words
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.38, 0.66, 1.0])
	grad.colors = PackedColorArray([Color(UIKit.CHARCOAL, 0.25), Color(UIKit.CHARCOAL, 0.0), Color(UIKit.CHARCOAL, 0.88), Color(UIKit.CHARCOAL, 0.97)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 4
	tex.height = 256
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.size = SIZE
	_quiet(shade, frame)
	var bar := ColorRect.new()
	bar.color = accent
	bar.size = Vector2(SIZE.x, 8.0)
	_quiet(bar, frame)
	var num := UIKit.label("%02d" % number, 44, UIKit.TEXT, UIKit.DISPLAY)
	num.position = Vector2(_PAD, 20.0)
	_quiet(num, frame)
	var of := UIKit.label("/ %02d" % count, 22, Color(UIKit.TEXT, 0.7), UIKit.DISPLAY_BOLD)
	of.position = Vector2(_PAD + 58.0, 38.0)
	_quiet(of, frame)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 2)
	info.position = Vector2(_PAD, 0.0)
	info.size = Vector2(SIZE.x - _PAD * 2.0, 0.0)
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_quiet(info, frame)
	info.add_child(UIKit.label(tags.to_upper(), 24, accent, UIKit.DISPLAY_BOLD))
	info.add_child(UIKit.label(title.to_upper(), 92, UIKit.TEXT, UIKit.DISPLAY))
	var words := UIKit.label(blurb, 22, Color(UIKit.TEXT, 0.88))
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size.x = info.size.x
	info.add_child(words)
	# sits on the bottom edge, however tall the words come out
	info.resized.connect(func() -> void: info.position.y = SIZE.y - _PAD - info.size.y)
	_outline_style = StyleBoxFlat.new()
	_outline_style.draw_center = false
	_outline_style.set_border_width_all(4)
	_outline_style.border_color = accent
	_outline = Panel.new()
	_outline.add_theme_stylebox_override(&"panel", _outline_style)
	_outline.size = SIZE
	_outline.visible = false
	_quiet(_outline)


## The chosen card is outlined in its colour.
func set_selected(on: bool) -> void:
	if _outline: _outline.visible = on


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if not mb or not mb.pressed: return
	match mb.button_index:
		MOUSE_BUTTON_LEFT: clicked.emit()
		MOUSE_BUTTON_WHEEL_UP: scrolled.emit(-1)
		MOUSE_BUTTON_WHEEL_DOWN: scrolled.emit(1)
		_: return
	accept_event()


# a child that lets the mouse through to the card
func _quiet(c: Control, parent: Control = self) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
