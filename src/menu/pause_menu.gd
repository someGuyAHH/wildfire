extends CanvasLayer

# Esc / Start: freezes the whole game (get_tree().paused) and shows the pause menu.
# Also pauses by itself when the window loses focus. Runs while paused (process_mode ALWAYS),
# and so do the F1 help and F2 tuning panels, which this menu can open.

signal pause_changed(paused: bool)

const _ITUNE := preload("res://src/hud/tuning_panel.gd")
const _IHELP := preload("res://src/hud/help_overlay.gd")

const _BACKDROP  := preload("res://assets/gdshaders/menu_backdrop.gdshader")
const _FIRE_TEXT := preload("res://assets/gdshaders/fire_text.gdshader")

const _ACCENT := Color(1.0, 0.52, 0.1)
const _MUTED  := Color(0.82, 0.78, 0.75)
const _MARGIN := 110.0

var _tm: TagManager
var _tuning: _ITUNE
var _help: _IHELP
var _to_title: Callable
var _mode_label: Label
var _root: Control
var _first_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_build()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"): return
	get_viewport().set_input_as_handled()
	if _help and _help.visible: # Esc closes the cheat sheet first
		_help.toggle()
		return
	set_paused(not get_tree().paused)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not get_tree().paused: set_paused(true)


## Hooks up what the menu can restart and open. Any of them can be null; its button just hides.
## to_title: called by "Back to title" (optional; the button hides without it).
func setup(tag_manager: TagManager, tuning: _ITUNE, help: _IHELP, to_title: Callable = Callable()) -> void:
	_tm = tag_manager
	_tuning = tuning
	_help = help
	_to_title = to_title
	for panel: Control in [_tuning, _help]:
		if panel: panel.visibility_changed.connect(on_panel_visibility_changed)
	_build_buttons()


## Pauses or unpauses the whole game and shows or hides the menu.
func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_refresh_visibility()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if paused and _first_button: _first_button.grab_focus()
	if paused and _tm and _mode_label: _mode_label.text = "%s  ·  %s" % [_tm.rules.mode_name.to_upper(), _tm.rules.mode_blurb]
	pause_changed.emit(paused)


func on_resume_pressed() -> void:
	set_paused(false)


func on_restart_pressed() -> void:
	if _tm: _tm.start_round()
	set_paused(false)


func on_title_pressed() -> void:
	set_paused(false)
	_to_title.call()


func on_tuning_pressed() -> void:
	if _tuning and not _tuning.visible: _tuning.toggle()


func on_help_pressed() -> void:
	if _help and not _help.visible: _help.toggle()


func on_quit_pressed() -> void:
	get_tree().quit()


func on_panel_visibility_changed() -> void:
	_refresh_visibility()


# the menu steps aside while the tuning or help panel is open on top of a pause
func _refresh_visibility() -> void:
	var panel_open := (_tuning and _tuning.visible) or (_help and _help.visible)
	_root.visible = get_tree().paused and not panel_open
	if _root.visible and _first_button: _first_button.grab_focus()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	var bm := ShaderMaterial.new()
	bm.shader = _BACKDROP
	dim.material = bm
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var box := VBoxContainer.new()
	box.name = "Buttons"
	box.anchor_top = 0.2
	box.anchor_bottom = 1.0
	box.offset_left = _MARGIN
	box.add_theme_constant_override(&"separation", 12)
	_root.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override(&"font_size", 96)
	title.add_theme_constant_override(&"outline_size", 14)
	title.add_theme_color_override(&"font_outline_color", Color(0.12, 0.02, 0.0, 0.95))
	var fm := ShaderMaterial.new()
	fm.shader = _FIRE_TEXT
	fm.set_shader_parameter(&"text_height", 125.0)
	title.material = fm
	box.add_child(title)
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override(&"font_size", 22)
	_mode_label.add_theme_color_override(&"font_color", _MUTED)
	_mode_label.add_theme_constant_override(&"outline_size", 5)
	_mode_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.75))
	box.add_child(_mode_label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 30.0
	box.add_child(gap)


func _build_buttons() -> void:
	var box := _root.find_child("Buttons", true, false) as VBoxContainer
	_first_button = _add_button(box, "RESUME", on_resume_pressed)
	if _tm: _add_button(box, "RESTART ROUND", on_restart_pressed)
	if _tuning and OS.is_debug_build(): _add_button(box, "TUNING [DEBUG]  (F2)", on_tuning_pressed)
	if _help: _add_button(box, "HELP  (F1)", on_help_pressed)
	if _to_title.is_valid(): _add_button(box, "BACK TO TITLE", on_title_pressed)
	_add_button(box, "QUIT GAME", on_quit_pressed)


func _add_button(parent: Control, text: String, handler: Callable) -> FireButton:
	var b := FireButton.new()
	b.text = text
	b.accent = _ACCENT
	b.pressed.connect(handler)
	parent.add_child(b)
	return b
