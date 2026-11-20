extends CanvasLayer

# Esc / Start: freezes the whole game (get_tree().paused) and shows the pause menu.
# Also pauses by itself when the window loses focus. Runs while paused (process_mode ALWAYS),
# and so do the F1 help and F2 tuning panels, which this menu can open.

const _ITUNE := preload("res://src/hud/tuning_panel.gd")
const _IHELP := preload("res://src/hud/help_overlay.gd")

const _BACKDROP := preload("res://assets/tres/materials/menu_backdrop.tres")
const _MARGIN   := 112.0

var _tm: TagManager
var _tuning: _ITUNE
var _help: _IHELP
var _to_title: Callable
var _mode_label: Label
var _root: Control
var _first_button: Button
var _buttons: VBoxContainer
var _settings: Control # the settings screen (the button list steps aside for it)
var _settings_list: SettingsList
var _previewing: Array[CanvasLayer] = [] # the UI layers PREVIEW hid (empty: not previewing)
var _confirm: Control # "are you sure?" for RESTART ROUND and BACK TO TITLE (the buttons step aside)
var _confirm_label: FlameTitle
var _confirm_no: Button
var _confirm_yes: Button
var _confirmed: Callable # what YES does


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_build()
	_root.visible = false


# PREVIEW: any key, click or pad button brings the menu back (and does nothing else)
func _input(event: InputEvent) -> void:
	if _previewing.is_empty(): return
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if not press: return
	get_viewport().set_input_as_handled()
	preview(false)


## Hides every UI layer (this menu, the HUDs) to show the paused game as it looks with the
## current settings, or puts them back.
func preview(on: bool) -> void:
	if on:
		for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var cl := n as CanvasLayer
			if cl.visible:
				cl.visible = false
				_previewing.append(cl)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		for cl: CanvasLayer in _previewing:
			if is_instance_valid(cl): cl.visible = true
		_previewing.clear()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_settings_list.preview_button().grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"): return
	get_viewport().set_input_as_handled()
	if _help and _help.visible: # Esc closes the cheat sheet first
		_help.toggle()
		return
	if _settings.visible: # ...and settings go back to the pause buttons
		show_settings(false)
		return
	if _confirm.visible: # ...and "are you sure?" is a no
		_cancel_confirm()
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
	if _help: _help.tag_manager = tag_manager
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


func on_resume_pressed() -> void:
	set_paused(false)


func on_restart_pressed() -> void:
	_ask("RESTART THE ROUND?", _restart)


func on_title_pressed() -> void:
	_ask("BACK TO THE TITLE SCREEN?", _go_to_title)


func _restart() -> void:
	if _tm: _tm.start_round()
	set_paused(false)


func _go_to_title() -> void:
	set_paused(false)
	_to_title.call()


## "Are you sure?" in place of the buttons; NO has the focus, so a double press does nothing.
func _ask(question: String, then: Callable) -> void:
	_confirmed = then
	_confirm_label.setup(question, 64)
	_buttons.visible = false
	_confirm.visible = true
	_confirm_no.grab_focus()


func _cancel_confirm() -> void:
	_confirm.visible = false
	_buttons.visible = true
	if _first_button: _first_button.grab_focus()


func _on_confirm_yes() -> void:
	_confirm.visible = false
	_buttons.visible = true
	_confirmed.call()


func on_tuning_pressed() -> void:
	if _tuning and not _tuning.visible: _tuning.toggle()


func on_help_pressed() -> void:
	if _help and not _help.visible: _help.toggle()


func on_settings_pressed() -> void:
	show_settings(true)


## Swaps the pause buttons for the settings list (or back).
func show_settings(on: bool) -> void:
	_settings.visible = on
	_buttons.visible = not on
	if on:
		_settings_list.refresh()
		_settings_list.first_focus().grab_focus()
	elif _first_button: _first_button.grab_focus()


func on_panel_visibility_changed() -> void:
	_refresh_visibility()


# the menu steps aside while the tuning or help panel is open on top of a pause
func _refresh_visibility() -> void:
	var panel_open := (_tuning and _tuning.visible) or (_help and _help.visible)
	_root.visible = get_tree().paused and not panel_open
	if not get_tree().paused and _settings.visible: show_settings(false) # unpaused: next pause starts on the buttons
	if not get_tree().paused and _confirm and _confirm.visible: _cancel_confirm()
	if _root.visible and _first_button and _buttons.visible: _first_button.grab_focus()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.material = _BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var box := VBoxContainer.new()
	box.name = "Buttons"
	_buttons = box
	box.anchor_top = 0.24
	box.anchor_bottom = 1.0
	box.offset_left = _MARGIN
	box.add_theme_constant_override(&"separation", 16)
	_root.add_child(box)
	box.add_child(UIKit.heading("PAUSED", 112))
	_mode_label = UIKit.label("", 22, UIKit.MUTED)
	box.add_child(_mode_label)
	box.add_child(UIKit.gap(24.0))
	# settings: its own column, hidden till SETTINGS is picked
	var col := VBoxContainer.new()
	col.anchor_top = 0.1
	col.anchor_bottom = 1.0
	col.offset_left = _MARGIN
	col.offset_top = 96.0
	col.offset_bottom = -40.0 # the scroller stops short of the screen's edge
	col.add_theme_constant_override(&"separation", 16)
	col.visible = false
	_root.add_child(col)
	_settings = col
	col.add_child(UIKit.heading("SETTINGS"))
	col.add_child(UIKit.gap(8.0))
	_settings_list = SettingsList.new()
	col.add_child(_settings_list.in_scroller())
	_settings_list.back_pressed.connect(show_settings.bind(false))
	_settings_list.show_preview()
	_settings_list.preview_pressed.connect(preview.bind(true))
	# "are you sure?": its own column, hidden till RESTART ROUND or BACK TO TITLE is picked
	var ask := VBoxContainer.new()
	ask.anchor_top = 0.32
	ask.anchor_bottom = 1.0
	ask.offset_left = _MARGIN
	ask.add_theme_constant_override(&"separation", 16)
	ask.visible = false
	_root.add_child(ask)
	_confirm = ask
	_confirm_label = UIKit.heading("", 64)
	ask.add_child(_confirm_label)
	ask.add_child(UIKit.label("The current round's progress will be lost.", 22, UIKit.MUTED))
	ask.add_child(UIKit.gap(16.0))
	_confirm_no = _add_button(ask, "NO, KEEP PLAYING", _cancel_confirm)
	_confirm_yes = _add_button(ask, "YES", _on_confirm_yes)


func _build_buttons() -> void:
	var box := _root.find_child("Buttons", true, false) as VBoxContainer
	_first_button = _add_button(box, "RESUME", on_resume_pressed)
	if _tm: _add_button(box, "RESTART ROUND", on_restart_pressed)
	_add_button(box, "SETTINGS", on_settings_pressed)
	if _tuning and OS.is_debug_build(): _add_button(box, "TUNING [DEBUG]  (F2)", on_tuning_pressed)
	if _help: _add_button(box, "HELP  (F1)", on_help_pressed)
	if _to_title.is_valid(): _add_button(box, "BACK TO TITLE", on_title_pressed)


func _add_button(parent: Control, text: String, handler: Callable) -> FireButton:
	var b := FireButton.new()
	b.text = text
	b.pressed.connect(handler)
	parent.add_child(b)
	return b
