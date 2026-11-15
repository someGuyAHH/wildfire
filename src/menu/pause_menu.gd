extends CanvasLayer

# Esc / Start: freezes the whole game (get_tree().paused) and shows the pause menu.
# Also pauses by itself when the window loses focus. Runs while paused (process_mode ALWAYS),
# and so do the F1 help and F2 tuning panels, which this menu can open.

signal pause_changed(paused: bool)

const _ITUNE := preload("res://src/hud/tuning_panel.gd")
const _IHELP := preload("res://src/hud/help_overlay.gd")

const _DIM_COLOR  := Color(0, 0, 0, 0.55)
const _BG_COLOR   := Color(0.06, 0.07, 0.09, 0.95)
const _HEAD_COLOR := Color(1.0, 0.62, 0.2)

var _tm: TagManager
var _tuning: _ITUNE
var _help: _IHELP
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
func setup(tag_manager: TagManager, tuning: _ITUNE, help: _IHELP) -> void:
	_tm = tag_manager
	_tuning = tuning
	_help = help
	for panel: Control in [_tuning, _help]:
		if panel: panel.visibility_changed.connect(on_panel_visibility_changed)
	_build_buttons()


## Pauses or unpauses the whole game and shows or hides the menu.
func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_refresh_visibility()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if paused and _first_button: _first_button.grab_focus()
	pause_changed.emit(paused)


func on_resume_pressed() -> void:
	set_paused(false)


func on_restart_pressed() -> void:
	if _tm: _tm.start_round()
	set_paused(false)


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
	dim.color = _DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _BG_COLOR
	style.set_content_margin_all(28.0)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Buttons"
	box.add_theme_constant_override(&"separation", 12)
	box.custom_minimum_size.x = 320.0
	panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.modulate = _HEAD_COLOR
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 40)
	box.add_child(title)


func _build_buttons() -> void:
	var box := _root.find_child("Buttons", true, false) as VBoxContainer
	_first_button = _add_button(box, "Resume", on_resume_pressed)
	if _tm: _add_button(box, "Restart round", on_restart_pressed)
	if _tuning: _add_button(box, "Tuning  (F2)", on_tuning_pressed)
	if _help: _add_button(box, "Help  (F1)", on_help_pressed)
	_add_button(box, "Quit game", on_quit_pressed)


func _add_button(parent: Control, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 48.0
	b.add_theme_font_size_override(&"font_size", 24)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b
