"""
A game-mode card for the mode select screen: the mode's banner on top, then the name, the blurb
and a line of tags, on a charcoal card with a bar of the mode's colour along the top. Hovered or
focused it lightens; selected it's outlined in its colour. No animation, the swap is instant.
"""

class_name ModeCard
extends Button

const _BANNER_MAT  := preload("res://assets/tres/materials/mode_banner.tres")
const _PANEL_STYLE := preload("res://assets/tres/ui/mode_card_panel.tres")

const _CARD_SIZE   := Vector2(304.0, 424.0)
const _BANNER_H    := 184.0
const _LIT_BG      := Color(0.16, 0.13, 0.11, 0.95)

var _selected := false
var _accent := Color(1.0, 0.5, 0.1)
var _panel: Panel
var _style: StyleBoxFlat


## Fills the card. pattern picks the banner (0 classic, 1 spread, 2 hunted, 3 hot potato).
func setup(title: String, blurb: String, tags: String, pattern: int, accent: Color) -> void:
	_accent = accent
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = _CARD_SIZE
	theme_type_variation = &"ModeCard" # no button chrome, the panel below is the card
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size = _CARD_SIZE
	_style = _PANEL_STYLE.duplicate() as StyleBoxFlat # own copy: _refresh() changes it
	_style.border_color = accent
	_panel.add_theme_stylebox_override(&"panel", _style)
	add_child(_panel)

	var banner := ColorRect.new()
	var mat := _BANNER_MAT.duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"pattern", pattern)
	mat.set_shader_parameter(&"main_color", accent)
	mat.set_shader_parameter(&"bg_color", accent.darkened(0.88))
	mat.set_shader_parameter(&"aspect", _CARD_SIZE.x / _BANNER_H)
	banner.material = mat
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.position = Vector2(0.0, 6.0)
	banner.size = Vector2(_CARD_SIZE.x, _BANNER_H)
	_panel.add_child(banner)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(24.0, _BANNER_H + 24.0)
	box.size = Vector2(_CARD_SIZE.x - 48.0, _CARD_SIZE.y - _BANNER_H - 48.0)
	box.add_theme_constant_override(&"separation", 8)
	_panel.add_child(box)
	box.add_child(_text(title.to_upper(), 40, UIKit.TEXT, UIKit.DISPLAY))
	box.add_child(_text(blurb, 18, Color(UIKit.TEXT, 0.8)))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	box.add_child(_text(tags.to_upper(), 19, accent, UIKit.DISPLAY_BOLD))


## Selected cards keep a bright border even when not hovered.
func set_selected(on: bool) -> void:
	_selected = on
	_refresh()


func _ready() -> void:
	for sig: Signal in [focus_entered, focus_exited, mouse_entered, mouse_exited]: sig.connect(_refresh)


func _refresh() -> void:
	if not _style: return
	var lit := has_focus() or is_hovered()
	var ring := 3 if _selected else 0
	_style.border_width_left = ring
	_style.border_width_right = ring
	_style.border_width_bottom = ring
	_style.border_width_top = 6 if not _selected else 8
	_style.bg_color = _LIT_BG if lit else _PANEL_STYLE.bg_color


func _text(t: String, font_size: int, color: Color, font: Font = null) -> Label:
	var l := UIKit.label(t, font_size, color, font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = &"" # no shadow on the card
	return l
