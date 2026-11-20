extends CanvasLayer

# title screen + mode select + settings + how to play. sits over a live bot match (Main runs the
# attract mode behind it). all built in code; screens slide/fade in, Esc / B goes back, every
# control works with mouse, keyboard and gamepad (focus = hover).

signal start_requested(mode_index: int, bot_count: int, difficulty: int, map_index: int)
## The MAP choice changed (Main swaps the live background match over to it).
signal map_changed(map_index: int)

const _BACKDROP     := preload("res://assets/tres/materials/menu_backdrop.tres")
const _EMBERS       := preload("res://scn/vfx/menu_embers.tscn")

const _MARGIN       := 112.0
const _SLIDE        := 60.0
const _FADE_TIME    := 0.35
const _BOTS_MIN     := 1
const _BOTS_MAX     := 15
const _DIFFICULTIES: Array[String] = ["Easy", "Normal", "Hard", "Mixed"]
# per-mode card art: banner pattern + accent color
const _MODE_COLORS: Array[Color] = [UIKit.EMBER, Color("ff4a24"), Color("f2335a"), UIKit.GOLD]
const _MODE_PICTURES: Array[Texture2D] = [preload("res://assets/images/ui/modes/classic.png"),
		preload("res://assets/images/ui/modes/spread.png"), preload("res://assets/images/ui/modes/hunted.png"),
		preload("res://assets/images/ui/modes/hot_potato.png")]
const _MODE_TAGS: Array[String] = ["1 Torch  ·  pass on touch", "the fire spreads  ·  survive",
								   "you vs the swarm", "fuse  ·  storm  ·  last one standing"]

var _modes: Array[MatchRules] = []
var _mode_index := 0
var _bot_count := 7
var _difficulty := 3
var _maps := PackedStringArray()
var _map_index := 0
var _screens: Dictionary[StringName, Control] = {}
var _current: StringName = &""
var _wheel: ModeWheel
var _map: MenuStepper
var _bots: MenuStepper
var _diff: MenuStepper
var _start: FireButton
var _back: FireButton
var _first_focus: Dictionary[StringName, Control] = {}
var _root: Control


## Hands over the selectable modes, maps (names) and the starting setup. Call once after adding to the tree.
func setup(modes: Array[MatchRules], bot_count: int, difficulty: int, maps: PackedStringArray, map_index: int) -> void:
	_modes = modes
	_maps = maps
	_map_index = clampi(map_index, 0, maxi(maps.size() - 1, 0))
	_bot_count = clampi(bot_count, _BOTS_MIN, _BOTS_MAX)
	_difficulty = clampi(difficulty, 0, _DIFFICULTIES.size() - 1)
	_build()
	show_screen(&"title")


## Shows the menu again on a given screen (title by default).
func open(screen: StringName = &"title") -> void:
	visible = true
	show_screen(screen)


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		if _current != &"title":
			show_screen(&"title")
			get_viewport().set_input_as_handled()


## Slides/fades to a screen: "title", "modes", "settings" or "howto".
func show_screen(screen: StringName) -> void:
	if not _screens.has(screen): return
	for key: StringName in _screens.keys():
		_screens[key].visible = key == screen
	_current = screen
	var s := _screens[screen]
	s.modulate.a = 0.0
	s.position.x = -_SLIDE
	var tw := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(s, ^"modulate:a", 1.0, _FADE_TIME)
	tw.tween_property(s, ^"position:x", 0.0, _FADE_TIME)
	if screen == &"modes":
		_wheel.select(_mode_index, false) # back to what you picked last time, swinging in
		_wheel.swing_in()
		_wheel.grab_focus.call_deferred()
	elif _first_focus.has(screen):
		_first_focus[screen].grab_focus.call_deferred()


func on_play_pressed() -> void:
	show_screen(&"modes")


func on_start_pressed() -> void:
	start_requested.emit(_mode_index, _bot_count, _difficulty, _map_index)


## The wheel turned to a mode.
func on_mode_selected(i: int) -> void:
	_mode_index = i


## Clicking the chosen card (or accept on the wheel) jumps to START. Only START starts.
func on_mode_confirmed() -> void:
	_start.grab_focus()


func on_map_changed(index: int) -> void:
	_map_index = index
	map_changed.emit(index)


func on_bots_changed(index: int) -> void:
	_bot_count = _BOTS_MIN + index


func on_difficulty_changed(index: int) -> void:
	_difficulty = index


func on_quit_pressed() -> void:
	get_tree().quit()


#region building

func _build() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.material = _BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
	_root.add_child(_EMBERS.instantiate())
	_screens[&"title"] = _build_title()
	_screens[&"modes"] = _build_modes()
	_screens[&"settings"] = _build_settings()
	_screens[&"howto"] = _build_howto()
	for s: Control in _screens.values(): _root.add_child(s)


func _build_title() -> Control:
	var screen := _screen()
	var box := _column(screen, 0.24)
	box.add_child(UIKit.heading("WILDFIRE", 168))
	box.add_child(UIKit.label("TAG, BUT THE TAG IS FIRE.", 30, UIKit.MUTED, UIKit.DISPLAY_BOLD))
	box.add_child(UIKit.gap(40.0))
	var play := _button(box, "PLAY", on_play_pressed, 40)
	play.custom_minimum_size.y = 72.0
	_button(box, "SETTINGS", show_screen.bind(&"settings"))
	_button(box, "HOW TO PLAY", show_screen.bind(&"howto"))
	_button(box, "QUIT", on_quit_pressed)
	_first_focus[&"title"] = play
	_footer(screen, "Enter / A  select      Esc / B  back")
	return screen


# the wheel of mode cards on the left, the setup column on the right
func _build_modes() -> Control:
	var screen := _screen()
	_wheel = ModeWheel.new()
	screen.add_child(_wheel)
	for i: int in _modes.size():
		var r := _modes[i]
		var card := ModeCard.new()
		card.setup(i + 1, _modes.size(), r.mode_name, r.mode_blurb, _MODE_TAGS[i % _MODE_TAGS.size()],
				_MODE_PICTURES[r.mode % _MODE_PICTURES.size()], _MODE_COLORS[i % _MODE_COLORS.size()])
		_wheel.add_card(card)
	_wheel.selected.connect(on_mode_selected)
	_wheel.confirmed.connect(on_mode_confirmed)
	var col := VBoxContainer.new()
	col.anchor_left = 0.62
	col.anchor_right = 1.0
	col.anchor_bottom = 1.0
	col.offset_right = -_MARGIN
	col.offset_top = 136.0
	col.offset_bottom = -72.0
	col.add_theme_constant_override(&"separation", 16)
	screen.add_child(col)
	col.add_child(UIKit.heading("CHOOSE YOUR FIRE", 72))
	col.add_child(UIKit.label("Turn the cards: left / right, the arrows, or scroll over the card.", 20, UIKit.MUTED))
	col.add_child(UIKit.gap(32.0))
	_map = _stepper(col, "MAP", _maps, _map_index, true)
	_map.value_changed.connect(on_map_changed)
	var counts: PackedStringArray = []
	for n: int in range(_BOTS_MIN, _BOTS_MAX + 1): counts.append("%d" % n)
	_bots = _stepper(col, "BOTS", counts, _bot_count - _BOTS_MIN)
	_bots.value_changed.connect(on_bots_changed)
	_diff = _stepper(col, "DIFFICULTY", PackedStringArray(_DIFFICULTIES), _difficulty, true)
	_diff.value_changed.connect(on_difficulty_changed)
	col.add_child(UIKit.gap(16.0))
	_start = _button(col, "START", on_start_pressed, 48)
	_start.custom_minimum_size = Vector2(0.0, 88.0)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	_back = _small_button(col, "‹  BACK", show_screen.bind(&"title"), 220.0)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_END
	# arrows under the front card
	var arrows := HBoxContainer.new()
	arrows.anchor_top = 0.5
	arrows.anchor_bottom = 0.5
	arrows.offset_left = _MARGIN
	arrows.offset_top = ModeCard.SIZE.y * 0.5 + 24.0
	arrows.add_theme_constant_override(&"separation", 16)
	screen.add_child(arrows)
	var prev := _small_button(arrows, "‹  PREV", _wheel.step.bind(-1), 168.0)
	var next := _small_button(arrows, "NEXT  ›", _wheel.step.bind(1), 168.0)
	for b: FireButton in [prev, next]:
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_NONE # the carousel itself takes the keys
	_first_focus[&"modes"] = _wheel
	# one path: the carousel (left/right turns it) -> down -> map -> bots -> difficulty -> start -> back
	_wheel.focus_neighbor_bottom = _wheel.get_path_to(_map)
	_wheel.focus_neighbor_top = _wheel.get_path_to(_wheel)
	_wheel.focus_next = _wheel.get_path_to(_map)
	_chain(_map, _wheel, _bots)
	_chain(_bots, _map, _diff)
	_chain(_diff, _bots, _start)
	_chain(_start, _diff, _back)
	_chain(_back, _start, _back)
	_start.focus_neighbor_left = _start.get_path_to(_wheel) # (the steppers' left/right change their value)
	_back.focus_neighbor_left = _back.get_path_to(_wheel)
	_start.focus_neighbor_right = _start.get_path_to(_start)
	_back.focus_neighbor_right = _back.get_path_to(_back)
	return screen


func _stepper(parent: Control, title: String, options: PackedStringArray, at: int, wrap_: bool = false) -> MenuStepper:
	var st := MenuStepper.new()
	st.custom_minimum_size = Vector2(0.0, 60.0)
	parent.add_child(st)
	st.setup(title, options, at, wrap_)
	return st


func _chain(c: Control, up: Control, down: Control) -> void:
	if up:
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_previous = c.get_path_to(up)
	if down:
		c.focus_neighbor_bottom = c.get_path_to(down)
		c.focus_next = c.get_path_to(down)


func _build_settings() -> Control:
	var screen := _screen()
	var box := _column(screen, 0.1)
	box.add_child(UIKit.heading("SETTINGS"))
	box.add_child(UIKit.gap(8.0))
	box.offset_bottom = -40.0 # the scroller stops short of the screen's edge
	var list := SettingsList.new()
	box.add_child(list.in_scroller())
	list.back_pressed.connect(show_screen.bind(&"title"))
	_first_focus[&"settings"] = list.first_focus()
	return screen


func _build_howto() -> Control:
	var screen := _screen()
	var box := _column(screen, 0.1)
	box.add_child(UIKit.heading("HOW TO PLAY"))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(980.0, 0.0)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override(&"normal_font_size", 22)
	rt.add_theme_font_size_override(&"bold_font_size", 22)
	rt.add_theme_font_override(&"bold_font", UIKit.BODY_BOLD)
	rt.add_theme_constant_override(&"line_separation", 8)
	rt.text = "\n".join(PackedStringArray([
		"[color=#ff6a1a][b]The fire[/b][/color]  One player is [b]the Torch[/b]. Touch someone to [b]set them alight[/b] and the fire is theirs.",
		"[color=#ff6a1a][b]Move[/b][/color]  WASD or arrows, Space jump, [b]Ctrl[/b] slide (slam in the air), [b]Shift[/b] dash, [b]Q[/b] brake. Wall-jump off anything steep.",
		"[color=#ff6a1a][b]Fight back[/b][/color]  Hit anyone at 20+ m/s (blue flames on screen) to [b]shove[/b] them. Shoving the Torch is a [b]snuff[/b]: bonus points.",
		"[color=#ff6a1a][b]No camping[/b][/color]  The outer ring of the map heats you up: stay out there and you catch fire. Sit still too long and you start smoking, then catch fire.",
		"[color=#ff6a1a][b]Modes[/b][/color]  Classic, Spread, Hunted and Hot Potato. Pick one on the mode screen.",
		"[color=#ff6a1a][b]Keys[/b][/color]  Esc pause · F1 full help · Tab scores · V camera · hold middle mouse to free-look",
		"[color=#888888][DEBUG]  F2 tuning · F3 readout · F4 slow-mo · F5 bot debug · F6 Torch hunts you · 7 no-tag · 8 alone · 9 fly · 0 freeze[/color]" if OS.is_debug_build() else "",
	]))
	box.add_child(rt)
	box.add_child(UIKit.gap(24.0))
	var back := _button(box, "BACK", show_screen.bind(&"title"))
	_first_focus[&"howto"] = back
	return screen

#endregion


#region widgets

func _screen() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.visible = false
	return s


func _column(parent: Control, top_frac: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.anchor_top = top_frac
	box.anchor_bottom = 1.0
	box.offset_left = _MARGIN
	box.add_theme_constant_override(&"separation", 16)
	parent.add_child(box)
	return box


func _button(parent: Control, text: String, handler: Callable, font_size: int = 30) -> FireButton:
	var b := FireButton.new()
	b.text = text
	b.text_size = font_size
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _small_button(parent: Control, text: String, handler: Callable, width: float = 70.0) -> FireButton:
	var b := FireButton.new()
	b.text = text
	b.text_size = 24
	b.custom_minimum_size = Vector2(width, 50.0)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _footer(parent: Control, text: String) -> void:
	var l := UIKit.label(text, 20, UIKit.MUTED)
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = _MARGIN
	l.offset_top = -56.0
	parent.add_child(l)


#endregion
