"""
A game-mode card for the mode select screen: animated placeholder banner on top, then the name,
the blurb and a line of tags. Lifts and glows on hover/focus, keeps a bright border when selected.
"""

class_name ModeCard
extends Button

const _BANNER_SHADER := preload("res://assets/gdshaders/mode_banner.gdshader")

const _CARD_SIZE   := Vector2(300.0, 430.0)
const _BANNER_H    := 190.0
const _LIFT        := 14.0
const _ANIM_SPEED  := 8.0
const _BG          := Color(0.07, 0.06, 0.07, 0.94)

var _hover := 0.0
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
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size = _CARD_SIZE
	_style = StyleBoxFlat.new()
	_style.bg_color = _BG
	_style.set_corner_radius_all(10)
	_style.set_border_width_all(3)
	_style.border_color = Color(accent, 0.25)
	_style.shadow_color = Color(0, 0, 0, 0.5)
	_style.shadow_size = 12
	_panel.add_theme_stylebox_override(&"panel", _style)
	add_child(_panel)

	var banner := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = _BANNER_SHADER
	mat.set_shader_parameter(&"pattern", pattern)
	mat.set_shader_parameter(&"main_color", accent)
	mat.set_shader_parameter(&"bg_color", accent.darkened(0.88))
	mat.set_shader_parameter(&"aspect", (_CARD_SIZE.x - 20.0) / _BANNER_H)
	banner.material = mat
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.position = Vector2(10.0, 10.0)
	banner.size = Vector2(_CARD_SIZE.x - 20.0, _BANNER_H)
	_panel.add_child(banner)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(20.0, _BANNER_H + 24.0)
	box.size = Vector2(_CARD_SIZE.x - 40.0, _CARD_SIZE.y - _BANNER_H - 36.0)
	box.add_theme_constant_override(&"separation", 10)
	_panel.add_child(box)
	box.add_child(_text(title.to_upper(), 30, Color.WHITE, true))
	box.add_child(_text(blurb, 17, Color(0.85, 0.82, 0.8), false))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	box.add_child(_text(tags, 15, Color(accent, 0.9), false))


## Selected cards keep a bright border even when not hovered.
func set_selected(on: bool) -> void:
	_selected = on
	_refresh()


func _process(delta: float) -> void:
	if not _panel: return
	var lit := has_focus() or is_hovered()
	var next := move_toward(_hover, 1.0 if lit else 0.0, delta * _ANIM_SPEED)
	if next == _hover: return
	_hover = next
	_refresh()


func _refresh() -> void:
	var e := ease(_hover, 0.5)
	_panel.position.y = -_LIFT * e
	var strength := maxf(e, 0.85 if _selected else 0.0)
	_style.border_color = Color(_accent, lerpf(0.25, 1.0, strength))
	_style.shadow_color = Color(_accent, 0.35 * strength) if strength > 0.0 else Color(0, 0, 0, 0.5)
	_style.shadow_size = int(lerpf(12.0, 26.0, strength))
	_style.bg_color = _BG.lerp(_accent.darkened(0.8), 0.25 * strength)


func _text(t: String, font_size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	if bold:
		l.add_theme_constant_override(&"outline_size", 6)
		l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.7))
	return l
