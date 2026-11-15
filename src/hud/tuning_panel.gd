extends Control

# live tuning panel (F2). sliders write straight into STG (view settings) and into the
# character's MovementConfig, which is shared by everyone using that .tres.
# adding a knob = one _add_config_slider / _add_setting_slider line in _build().

const _PANEL_WIDTH := 460.0
const _BG_COLOR    := Color(0.07, 0.08, 0.1, 0.94)
const _DIM_COLOR   := Color(0, 0, 0, 0.35)
const _HEAD_COLOR  := Color(1.0, 0.62, 0.2)

## One slider row: knows how to read, write and reset its value.
class Row:
	extends RefCounted

	var title: String
	var slider: HSlider
	var value_label: Label
	var fmt: String
	var getter: Callable
	var setter: Callable
	var default_value: float

	func _init(title_: String = "", fmt_: String = "%.2f") -> void:
		self.title = title_
		self.fmt = fmt_

	func refresh() -> void:
		slider.set_value_no_signal(getter.call())
		value_label.text = fmt % slider.value

var _character: Character
var _rows: Array[Row] = []
var _toggles: Dictionary[StringName, CheckButton] = {}
var _readout: Label
var _status: Label


func _ready() -> void:
	visible = false
	# eats clicks while open so they don't recapture the mouse
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible: _update_readout() # keeps the fps number live


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tuning") or (visible and event.is_action_pressed(&"pause")):
		toggle()
		get_viewport().set_input_as_handled()


## Hands over the character whose MovementConfig gets tuned. Call once, from the HUD.
func setup(character: Character) -> void:
	if not character or not character.config:
		push_error("TuningPanel.setup() needs a character with a config")
		return
	_character = character
	_build()


## Opens/closes the panel. Opening frees the mouse, closing captures it again and saves settings.
func toggle() -> void:
	if not _character: return
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_all()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		STG.save_settings()


func on_slider_changed(value: float, row: Row) -> void:
	row.setter.call(value)
	row.value_label.text = row.fmt % value
	_update_readout()


func on_toggle_changed(on: bool, key: StringName) -> void:
	STG.set_value(key, 1.0 if on else 0.0, false)


func on_reset_pressed() -> void:
	for row: Row in _rows:
		row.setter.call(row.default_value)
	for key: StringName in _toggles.keys():
		STG.set_value(key, STG.get_default(key), false)
	_refresh_all()
	_status.text = "reset everything to defaults"


func on_save_pressed() -> void:
	var cfg := _character.config
	var err := ResourceSaver.save(cfg)
	_status.text = "saved %s" % cfg.resource_path if err == OK \
			else "save failed: %s (only works when run from the editor)" % error_string(err)
	STG.save_settings()


func on_copy_pressed() -> void:
	var lines: PackedStringArray = []
	for row: Row in _rows:
		lines.append("%s = %s" % [row.title, row.fmt % row.slider.value])
	for key: StringName in _toggles.keys():
		lines.append("%s = %s" % [key, "on" if STG.is_on(key) else "off"])
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	print("tuning values:\n%s" % text)
	_status.text = "copied to clipboard (also printed to output)"


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = _DIM_COLOR
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _BG_COLOR
	style.set_content_margin_all(20.0)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -_PANEL_WIDTH
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)

	_add_heading(box, "TUNING   (F2 / Esc closes)")
	_add_heading(box, "View: saved to user://settings.cfg")
	_add_setting_slider(box, "Mouse sensitivity", STG.MOUSE_SENS, 0.2, 10.0, 0.05, "%.2f")
	_add_setting_slider(box, "FOV", STG.FOV, 60.0, 130.0, 1.0, "%.0f°")
	_add_setting_toggle(box, "Third person (V)", STG.THIRD_PERSON)
	_add_heading(box, "Graphics: saved too")
	_add_setting_slider(box, "Render scale (FSR upscale)", STG.RENDER_SCALE, 0.4, 1.0, 0.05, "%.2f")
	var flags := GridContainer.new()
	flags.columns = 3
	box.add_child(flags)
	_add_setting_toggle(flags, "SSAO", STG.SSAO)
	_add_setting_toggle(flags, "Glow", STG.GLOW)
	_add_setting_toggle(flags, "MSAA 2x", STG.MSAA)
	_add_setting_toggle(flags, "FXAA", STG.FXAA)
	_add_setting_toggle(flags, "VSync", STG.VSYNC)
	_add_heading(box, "Movement: shared MovementConfig")
	_add_config_slider(box, "gravity", &"gravity", 2.0, 40.0, 0.5, "%.1f m/s²")
	_add_config_slider(box, "fall_gravity_mult", &"fall_gravity_mult", 1.0, 3.0, 0.05, "×%.2f")
	_add_config_slider(box, "jump_velocity", &"jump_velocity", 3.0, 20.0, 0.25, "%.2f m/s")

	_readout = Label.new()
	_readout.modulate = Color(0.75, 0.9, 1.0)
	box.add_child(_readout)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	box.add_child(buttons)
	_add_button(buttons, "Defaults", on_reset_pressed)
	_add_button(buttons, "Save to .tres", on_save_pressed)
	_add_button(buttons, "Copy values", on_copy_pressed)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(_status)


func _add_setting_slider(parent: Control, title: String, key: StringName,
						min_v: float, max_v: float, step: float, fmt: String) -> void:
	var row := Row.new(title, fmt)
	row.getter = STG.get_value.bind(key)
	row.setter = func(v: float) -> void: STG.set_value(key, v, false)
	row.default_value = STG.get_default(key)
	_add_row(parent, row, min_v, max_v, step)


func _add_setting_toggle(parent: Control, title: String, key: StringName) -> void:
	var b := CheckButton.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.set_pressed_no_signal(STG.is_on(key))
	b.toggled.connect(on_toggle_changed.bind(key))
	parent.add_child(b)
	_toggles[key] = b


func _add_config_slider(parent: Control, title: String, prop: StringName,
						min_v: float, max_v: float, step: float, fmt: String) -> void:
	var cfg := _character.config
	var row := Row.new(title, fmt)
	row.getter = cfg.get.bind(prop)
	row.setter = func(v: float) -> void: cfg.set(prop, v)
	# fresh instance = the script's defaults, not whatever the .tres says
	row.default_value = MovementConfig.new().get(prop)
	_add_row(parent, row, min_v, max_v, step)


func _add_row(parent: Control, row: Row, min_v: float, max_v: float, step: float) -> void:
	var head := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = row.title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.value_label = Label.new()
	head.add_child(name_label)
	head.add_child(row.value_label)
	parent.add_child(head)

	row.slider = HSlider.new()
	row.slider.min_value = min_v
	row.slider.max_value = max_v
	row.slider.step = step
	row.slider.custom_minimum_size.y = 24.0
	row.slider.focus_mode = Control.FOCUS_NONE # arrow keys stay with the game
	row.slider.value_changed.connect(on_slider_changed.bind(row))
	parent.add_child(row.slider)
	_rows.append(row)
	row.refresh()


func _add_heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = _HEAD_COLOR
	parent.add_child(l)


func _add_button(parent: Control, text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	parent.add_child(b)


func _refresh_all() -> void:
	for row: Row in _rows: row.refresh()
	for key: StringName in _toggles.keys(): _toggles[key].set_pressed_no_signal(STG.is_on(key))
	_update_readout()


func _update_readout() -> void:
	if not _readout: return
	var cfg := _character.config
	var g := maxf(cfg.gravity, 0.01)
	var v := cfg.jump_velocity
	var apex := v * v / (2.0 * g)
	var fall_g := g * cfg.fall_gravity_mult
	var airtime := v / g + sqrt(2.0 * apex / fall_g)
	_readout.text = "jump apex %.2f m   airtime %.2f s\nfall gravity %.1f m/s²   fps %d" % [
			apex, airtime, fall_g, Engine.get_frames_per_second()]
