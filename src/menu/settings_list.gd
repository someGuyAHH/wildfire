class_name SettingsList
extends VBoxContainer

## Every player setting as menu rows (sliders, on/off and choice steppers), then RESET TO
## DEFAULTS and BACK. Shared by the title screen's settings and the pause menu. Changes apply
## and save as you make them; BACK just emits back_pressed for whoever's showing it.

signal back_pressed

const _ACCENT := Color(1.0, 0.52, 0.1)
const _MUTED  := Color(0.82, 0.78, 0.75)

# abbreviations get a plain-words name, the acronym kept for anyone who knows it
const _TOGGLES: Array[Array] = [
	["Third person", STG.THIRD_PERSON],
	["Ambient shadows (SSAO)", STG.SSAO],
	["Glow", STG.GLOW],
	["Edge smoothing: MSAA 2x", STG.MSAA],
	["Edge smoothing: FXAA", STG.FXAA],
]

var _refresh: Array[Callable] = []
var _first: Control


# built straight away (not in _ready), so first_focus() works before it's in the tree
func _init() -> void:
	add_theme_constant_override(&"separation", 14)
	_first = _slider_row("Mouse sensitivity", STG.MOUSE_SENS, 0.2, 10.0, 0.05, "%.2f")
	_slider_row("Field of view", STG.FOV, 60.0, 130.0, 1.0, "%.0f°")
	_slider_row("Render scale", STG.RENDER_SCALE, 0.4, 1.0, 0.05, "%.2f")
	add_child(_gap(6.0))
	for pair: Array in _TOGGLES: _choice(pair[0], pair[1], PackedStringArray(["Off", "On"]))
	_choice("VSync", STG.VSYNC, PackedStringArray(["Off", "Adaptive", "On"]))
	_choice("Shadow quality", STG.SHADOWS, PackedStringArray(["Low", "Medium", "High"]))
	_choice("Lighting (global illumination, fog)", STG.LIGHTING, PackedStringArray(["Low", "High"]))
	_choice("Performance HUD", STG.PERF_HUD, PackedStringArray(["Off", "FPS", "Full"]))
	add_child(_gap(14.0))
	_button("RESET TO DEFAULTS", on_reset_pressed)
	_button("BACK", back_pressed.emit)


## The list inside a vertical scroller that fills the rest of its column, for screens too short to
## show every row: the mouse wheel scrolls it, and moving focus with keys or a pad scrolls along.
func in_scroller() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.custom_minimum_size.x = 920.0 # the rows' width, so the scrollbar sits beside them
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(self)
	return sc


## Where focus starts when the list is shown.
func first_focus() -> Control:
	return _first


## Every setting back to its default; the rows follow.
func on_reset_pressed() -> void:
	STG.reset_to_defaults()
	refresh()


## Re-reads every row from STG (after a reset, or if something else changed a setting).
func refresh() -> void:
	for f: Callable in _refresh: f.call()


func _slider_row(title: String, key: StringName, lo: float, hi: float, step: float, fmt: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 20)
	add_child(row)
	var name_label := _label(title, 26, _MUTED)
	name_label.custom_minimum_size.x = 300.0
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = STG.get_value(key)
	slider.custom_minimum_size = Vector2(420.0, 32.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.theme_type_variation = &"MenuSlider"
	slider.scrollable = false # the wheel scrolls the list, not whichever slider is under the mouse
	row.add_child(slider)
	var value := _label(fmt % slider.value, 26, Color.WHITE)
	row.add_child(value)
	slider.value_changed.connect(func(v: float) -> void: STG.set_value(key, v); value.text = fmt % v)
	# focus shows on the label, no boxy outline
	slider.focus_entered.connect(func() -> void: name_label.add_theme_color_override(&"font_color", _ACCENT))
	slider.focus_exited.connect(func() -> void: name_label.add_theme_color_override(&"font_color", _MUTED))
	slider.mouse_entered.connect(slider.grab_focus)
	_refresh.append(func() -> void: slider.set_value_no_signal(STG.get_value(key)); value.text = fmt % slider.value)
	return slider


# a stepper bar, same as the mode screen ("Glow  ‹ On ›"); the setting stores the option index
func _choice(title: String, key: StringName, options: PackedStringArray) -> void:
	var st := MenuStepper.new()
	st.custom_minimum_size = Vector2(620.0, 52.0)
	st.text_size = 24
	st.accent = _ACCENT
	add_child(st)
	var index := func() -> int: return clampi(roundi(STG.get_value(key)), 0, options.size() - 1)
	st.setup(title, options, index.call(), true)
	st.value_changed.connect(func(i: int) -> void: STG.set_value(key, float(i)))
	_refresh.append(func() -> void: st.setup(title, options, index.call(), true))


func _button(text: String, handler: Callable) -> FireButton:
	var b := FireButton.new()
	b.text = text
	b.text_size = 30
	b.accent = _ACCENT
	b.pressed.connect(handler)
	add_child(b)
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = &"MenuLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	return l


func _gap(px: float) -> Control:
	var g := Control.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.custom_minimum_size = Vector2(0.0, px)
	return g
