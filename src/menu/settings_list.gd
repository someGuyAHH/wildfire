class_name SettingsList
extends VBoxContainer

## Every player setting as menu rows (sliders, on/off and choice steppers), then RESET TO
## DEFAULTS and BACK. Shared by the title screen's settings and the pause menu. Changes apply
## and save as you make them; BACK just emits back_pressed for whoever's showing it.

signal back_pressed
## PREVIEW was pressed (only shown after show_preview(): the pause menu, with a game behind it)
signal preview_pressed

# abbreviations get a plain-words name, the acronym kept for anyone who knows it
const _TOGGLES: Array[Array] = [
	["Ambient shadows (SSAO)", STG.SSAO],
	["Glow", STG.GLOW],
	["Edge smoothing: MSAA 2x", STG.MSAA],
	["Edge smoothing: FXAA", STG.FXAA],
]

# premium effects (ULTRA turns them all on)
const _PREMIUM: Array[Array] = [
	["Edge smoothing: TAA (no shimmer)", STG.TAA],
	["Reflections (SSR)", STG.SSR],
	["Coloured bounce light (SSIL)", STG.SSIL],
	["Soft shadows (contact-hardening)", STG.SOFT_SHADOWS],
	["Detailed sun shafts", STG.FOG_DETAIL],
	["Eye adaptation (auto-exposure)", STG.AUTO_EXPOSURE],
	["Smooth glow", STG.GLOW_HQ],
]

var _refresh: Array[Callable] = []
var _preview: FireButton
var _first: Control


# built straight away (not in _ready), so first_focus() works before it's in the tree
func _init() -> void:
	add_theme_constant_override(&"separation", 8)
	add_child(_section("CONTROLS"))
	_first = _slider_row("Mouse sensitivity", STG.MOUSE_SENS, 0.2, 10.0, 0.05, "%.2f")
	_slider_row("Field of view", STG.FOV, 60.0, 130.0, 1.0, "%.0f°")
	_choice("Third person", STG.THIRD_PERSON, PackedStringArray(["Off", "On"]))
	add_child(_section("GRAPHICS"))
	_slider_row("Render scale", STG.RENDER_SCALE, 0.4, 1.0, 0.05, "%.2f")
	for pair: Array in _TOGGLES: _choice(pair[0], pair[1], PackedStringArray(["Off", "On"]))
	_choice("VSync", STG.VSYNC, PackedStringArray(["Off", "Adaptive", "On"]))
	_choice("Shadow quality", STG.SHADOWS, PackedStringArray(["Low", "Medium", "High"]))
	_choice("Leaf shadows", STG.LEAF_SHADOWS, PackedStringArray(["Off", "Low", "Medium", "High"]))
	_choice("Fast shadows (sharper, coarser edges)", STG.FAST_SHADOWS, PackedStringArray(["Off", "On"]))
	_choice("Speed effects", STG.SPEED_FX, PackedStringArray(["Off", "Low", "Medium", "High"]))
	_choice("Lighting (sun shafts, fog, bounce light)", STG.LIGHTING, PackedStringArray(["Low", "High"]))
	_choice("Performance HUD", STG.PERF_HUD, PackedStringArray(["Off", "FPS", "Full"]))
	add_child(_section("PREMIUM EFFECTS  ·  STRONG GPUS"))
	for pair: Array in _PREMIUM: _choice(pair[0], pair[1], PackedStringArray(["Off", "On"]))
	_choice("Live global illumination (SDFGI: very heavy)", STG.LIVE_GI, PackedStringArray(["Off", "On"]))
	_button("ULTRA PRESET  (every premium effect but live GI)", on_ultra_pressed)
	add_child(UIKit.gap(16.0))
	_preview = _button("PREVIEW  (hide the menu, any key to come back)", preview_pressed.emit)
	_preview.visible = false
	_button("RESET TO DEFAULTS", on_reset_pressed)
	_button("BACK", back_pressed.emit)


## The list inside a vertical scroller that fills the rest of its column, for screens too short to
## show every row: the mouse wheel scrolls it, and moving focus with keys or a pad scrolls along.
func in_scroller() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.custom_minimum_size.x = 880.0 # the rows' width, so the scrollbar sits beside them
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(self)
	return sc


## Shows PREVIEW (there's a paused game behind the menu to look at).
func show_preview() -> void:
	_preview.visible = true


## The PREVIEW button (to give focus back to after a preview).
func preview_button() -> Control:
	return _preview


## Where focus starts when the list is shown.
func first_focus() -> Control:
	return _first


## Every setting back to its default; the rows follow.
func on_ultra_pressed() -> void:
	STG.apply_ultra()
	refresh()


func on_reset_pressed() -> void:
	STG.reset_to_defaults()
	refresh()


## Re-reads every row from STG (after a reset, or if something else changed a setting).
func refresh() -> void:
	for f: Callable in _refresh: f.call()


func _slider_row(title: String, key: StringName, lo: float, hi: float, step: float, fmt: String) -> HSlider:
	var plate := PanelContainer.new() # the same slanted plate as the steppers
	plate.theme_type_variation = &"SlantPanel"
	plate.custom_minimum_size = Vector2(840.0, 52.0)
	add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	plate.add_child(row)
	var name_label := UIKit.label(title.to_upper(), 24, UIKit.TEXT, UIKit.DISPLAY_BOLD)
	name_label.custom_minimum_size.x = 300.0
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = STG.get_value(key)
	slider.custom_minimum_size = Vector2(0.0, 32.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.theme_type_variation = &"MenuSlider"
	slider.scrollable = false # the wheel scrolls the list, not whichever slider is under the mouse
	row.add_child(slider)
	var value := UIKit.label(fmt % slider.value, 28, UIKit.TEXT, UIKit.DISPLAY_BOLD)
	row.add_child(value)
	slider.value_changed.connect(func(v: float) -> void: STG.set_value(key, v); value.text = fmt % v)
	# focus shows on the label, no boxy outline
	slider.focus_entered.connect(func() -> void: name_label.add_theme_color_override(&"font_color", UIKit.EMBER))
	slider.focus_exited.connect(func() -> void: name_label.add_theme_color_override(&"font_color", UIKit.TEXT))
	slider.mouse_entered.connect(slider.grab_focus)
	_refresh.append(func() -> void: slider.set_value_no_signal(STG.get_value(key)); value.text = fmt % slider.value)
	return slider


# a stepper bar, same as the mode screen ("Glow  ‹ On ›"); the setting stores the option index
func _choice(title: String, key: StringName, options: PackedStringArray) -> void:
	var st := MenuStepper.new()
	st.custom_minimum_size = Vector2(840.0, 52.0)
	st.text_size = 24
	add_child(st)
	var index := func() -> int: return clampi(roundi(STG.get_value(key)), 0, options.size() - 1)
	st.setup(title.to_upper(), options, index.call(), true)
	st.value_changed.connect(func(i: int) -> void: STG.set_value(key, float(i)))
	_refresh.append(func() -> void: st.setup(title.to_upper(), options, index.call(), true))


func _button(text: String, handler: Callable) -> FireButton:
	var b := FireButton.new()
	b.text = text
	b.text_size = 28
	b.pressed.connect(handler)
	add_child(b)
	return b


# a group's name: small caps in ember, a hairline under it
func _section(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	box.add_child(UIKit.gap(16.0))
	box.add_child(UIKit.label(text, 22, UIKit.EMBER, UIKit.DISPLAY_BOLD))
	var rule := ColorRect.new()
	rule.color = Color(UIKit.EMBER, 0.4)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return box
