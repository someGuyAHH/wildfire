extends CanvasLayer

# title screen + match setup + settings + how to play, over a live bot match (Main runs the
# attract mode behind it). Built in code. Screens slide in over the title, each from its own side
# (MenuSlide: durations and directions), and slide back out; the shade over the match changes with them.
# Esc / B goes back (on the title, it asks before quitting). Every control works with mouse,
# keyboard and gamepad (focus = hover), and a strip at the bottom says which keys do what.

signal start_requested(mode_index: int, bot_count: int, difficulty: int, map_index: int)
## The MAP choice changed (Main swaps the live background match over to it).
signal map_changed(map_index: int)

const _BACKDROP := preload("res://assets/tres/materials/menu_backdrop.tres")
const _EMBERS   := preload("res://scn/vfx/menu_embers.tscn")

const _MARGIN := 112.0
const _BOTS_MIN := 1
const _BOTS_MAX := 15
const _DIFFICULTIES: Array[String] = ["Easy", "Normal", "Hard", "Mixed"]
const _MODE_COLORS: Array[Color] = [UIKit.EMBER, Color("ff4a24"), Color("f2335a"), UIKit.GOLD]
const _MODE_PICTURES: Array[Texture2D] = [preload("res://assets/images/ui/modes/classic.png"),
		preload("res://assets/images/ui/modes/spread.png"), preload("res://assets/images/ui/modes/hunted.png"),
		preload("res://assets/images/ui/modes/hot_potato.png")]
const _MODE_TAGS: Array[String] = ["1 Torch  ·  pass on touch", "the fire spreads  ·  survive",
								   "you vs the swarm", "fuse  ·  storm  ·  last one standing"]
# how each screen shades the match: [side, low, full]
const _SHADE := {&"title": Vector3(1, 0, 0), &"modes": Vector3(0.35, 1, 0), &"settings": Vector3(0, 0, 1), &"howto": Vector3(0, 0, 1)}
const _HINTS := {
	&"title": [[["↑", "↓"], "Select"], [["Enter"], "Confirm"], [["Esc"], "Quit"]],
	&"modes": [[["←", "→"], "Change"], [["↑", "↓"], "Section"], [["Enter"], "Next / Play"], [["Esc"], "Back"]],
}

var _modes: Array[MatchRules] = []
var _mode_index := 0
var _bot_count := 7
var _difficulty := 3
var _maps := PackedStringArray()
var _map_index := 0
var _screens: Dictionary[StringName, Control] = {}
var _current: StringName = &""
var _first_focus: Dictionary[StringName, Control] = {}
var _root: Control
var _shade: ShaderMaterial
var _hints: HintBar
var _modal: MenuModal
var _wheel: ModeWheel
var _bots: BotsZone
var _map: MapZone
var _diff: DifficultyZone
var _play: FireButton
var _play_sum: Label
var _last: Control # the title screen's "last match" card
var _settings: SettingsScreen
var _slide: MenuSlide = preload("res://assets/tres/ui/menu_slide.tres")
var _slide_tween: Tween
var _slide_pair: Array[Control] = []
var _slide_hide: StringName = &""
var _pieces: Dictionary[StringName, Control] = {} # the match setup's parts, which come and go one by one
var _piece_rest: Dictionary[StringName, Vector4] = {} # each piece's resting offsets (left, top, right, bottom)
var _fall: Array[Dictionary] = []
var _fall_tween: Tween # the boxes falling off the screen, which outlast the title's slide
var _fall_ignored: Array[Control] = []
var _slide_pieces := false # the slide in progress moves those
var _blocker: Control # swallows clicks for the first moments of a slide


## Hands over the selectable modes, maps (names) and the starting setup. Call once after adding to the tree.
func setup(modes: Array[MatchRules], bot_count: int, difficulty: int, maps: PackedStringArray, map_index: int) -> void:
	_modes = modes
	_maps = maps
	_map_index = clampi(map_index, 0, maxi(maps.size() - 1, 0))
	_bot_count = clampi(bot_count, _BOTS_MIN, _BOTS_MAX)
	_difficulty = clampi(difficulty, 0, _DIFFICULTIES.size() - 1)
	_build()
	show_screen(&"title")
	_capture_rest_later()


func _capture_rest_later() -> void:
	for i: int in 2: await get_tree().process_frame # (laid out)
	_capture_rest()


## Shows the menu again on a given screen (title by default).
func open(screen: StringName = &"title") -> void:
	visible = true
	if _slide_tween: _finish_slide()
	_end_fall()
	_current = &"" # (so it shows even if it is the one already up)
	show_screen(screen, false)


func close() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	# a key or click during a slide skips to its end (and is otherwise used as normal)
	if (_slide_tween or _fall_tween) and event.is_pressed() and not event is InputEventMouseMotion:
		_finish_slide()
		_end_fall()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _modal.is_open() or _settings.is_asking(): return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if _current == &"title": on_quit_pressed()
		else: show_screen(&"title")


## Moves to a screen ("title", "modes", "settings" or "howto"): the settings and how to play slide in
## whole from their side; the match setup is put together piece by piece (see MenuSlide) and falls apart
## the same way. Going back reverses it.
func show_screen(screen: StringName, slide: bool = true) -> void:
	if not _screens.has(screen) or screen == _current: return
	if _slide_tween: _finish_slide()
	_end_fall()
	var from := _current
	var animate := slide and from != &"" and visible
	_enter(screen)
	if not animate: return
	var size := get_viewport().get_visible_rect().size
	var to_modes := screen == &"modes"
	var from_modes := from == &"modes"
	var going_in := screen != &"title"
	var moving := _screens[screen]
	var other := _screens[from]
	other.visible = true
	_slide_pair = [moving, other]
	_slide_hide = from
	_slide_pieces = to_modes or from_modes
	_blocker.visible = true
	_slide_tween = create_tween().set_parallel().set_trans(_slide.transition).set_ease(_slide.easing)
	if _slide_pieces:
		# the title slides in / out while the setup builds / falls apart
		var title := _screens[&"title"]
		var away := _slide.title_from * size
		if to_modes:
			title.position = Vector2.ZERO
			_slide_tween.tween_property(title, ^"position", away, _slide.title_time)
			_build_pieces(size)
		else:
			title.position = away
			_slide_tween.tween_property(title, ^"position", Vector2.ZERO, _slide.title_time)
			_drop_pieces(size)
	else:
		var offset := _slide.side_of(screen if going_in else from) * size
		# the incoming screen starts off to its side (or, coming back to the title, a way off the other)
		moving.position = offset if going_in else -offset * _slide.title_follow
		other.position = Vector2.ZERO
		var end_out := -offset * _slide.title_follow if going_in else offset
		_slide_tween.tween_property(moving, ^"position", Vector2.ZERO, _slide.duration)
		_slide_tween.tween_property(other, ^"position", end_out, _slide.duration)
	_slide_tween.finished.connect(_finish_slide)
	get_tree().create_timer(_slide.input_block).timeout.connect(func() -> void:
		if _slide_tween: _blocker.visible = false)


# A piece moves by shifting all four of its offsets together, so it keeps its size and anchors whatever
# the container or the resolution (setting `position` on an anchored control let the size drift).
func _place(piece: Control, rest: Vector4, by: Vector2) -> void:
	piece.offset_left = rest.x + by.x
	piece.offset_top = rest.y + by.y
	piece.offset_right = rest.z + by.x
	piece.offset_bottom = rest.w + by.y


# The resting offsets of the pieces, read once the screen has been laid out (hidden, a frame after setup).
func _capture_rest() -> void:
	for key: StringName in _pieces:
		var c := _pieces[key]
		_piece_rest[key] = Vector4(c.offset_left, c.offset_top, c.offset_right, c.offset_bottom)


# the setup's pieces slide in each from its own side, one after another
func _build_pieces(size: Vector2) -> void:
	var i := 0
	for key: StringName in _slide.piece_from:
		var piece: Control = _pieces.get(key)
		if not piece or not _piece_rest.has(key): continue
		var rest: Vector4 = _piece_rest[key]
		piece.rotation = 0.0
		var start: Vector2 = _slide.piece_from[key] * size
		_place(piece, rest, start)
		_slide_tween.tween_method(func(by: Vector2) -> void: _place(piece, rest, by), start, Vector2.ZERO, _slide.piece_time) \
				.set_delay(i * _slide.piece_stagger)
		i += 1


# ...and leave by popping up off their spots and falling off the screen (gravity, a little spin and drift,
# each letting go at a slightly different moment). They fall on their own clock, outliving the title's
# slide, until each is fully below the screen (or the cap runs out); meanwhile they take no clicks.
func _drop_pieces(size: Vector2) -> void:
	_fall.clear()
	var total := 0.0
	var g := _slide.gravity
	for key: StringName in _pieces:
		var piece := _pieces[key]
		if not _piece_rest.has(key): continue
		var drop := size.y - piece.global_position.y + piece.size.length() # clear of the screen, turned or not
		var v := _slide.pop_speed
		var delay := randf() * _slide.fall_delay_max
		var t_exit := (-v + sqrt(v * v + 2.0 * g * maxf(drop, 0.0))) / g
		piece.pivot_offset = piece.size * 0.5
		_fall.append({&"piece": piece, &"rest": _piece_rest[key], &"delay": delay,
				&"spin": 0.0 if key == &"wheel" else deg_to_rad(randf_range(-1.0, 1.0) * _slide.spin_max),
				&"drift": randf_range(-1.0, 1.0) * _slide.drift_max})
		total = maxf(total, delay + t_exit)
		for c: Node in [piece] + piece.find_children("*", "Control", true, false):
			var ctl := c as Control
			_fall_ignored.append(ctl)
			ctl.set_meta(&"menu_mouse", ctl.mouse_filter)
			ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := total + _slide.fall_cap_extra
	_fall_tween = create_tween()
	_fall_tween.tween_method(_fall_step, 0.0, cap, cap)


func _fall_step(t: float) -> void:
	var viewport_bottom := get_viewport().get_visible_rect().size.y
	var all_gone := true
	for f: Dictionary in _fall:
		var lt := maxf(t - float(f[&"delay"]), 0.0)
		var piece := f[&"piece"] as Control
		_place(piece, f[&"rest"], Vector2(float(f[&"drift"]) * lt, -_slide.pop_speed * lt + 0.5 * _slide.gravity * lt * lt))
		piece.rotation = float(f[&"spin"]) * lt
		var top := INF # the box's highest corner, turned and all
		var xf := piece.get_global_transform()
		for corner: Vector2 in [Vector2.ZERO, Vector2(piece.size.x, 0.0), Vector2(0.0, piece.size.y), piece.size]:
			top = minf(top, (xf * corner).y)
		if top < viewport_bottom or lt <= 0.0: all_gone = false
	if all_gone and t > 0.0: _end_fall.call_deferred()


# the boxes are down (or skipped): back in their places, out of sight with the screen
func _end_fall() -> void:
	if not _fall_tween: return
	_fall_tween.kill()
	_fall_tween = null
	_reset_pieces()
	for c: Control in _fall_ignored: c.mouse_filter = c.get_meta(&"menu_mouse", Control.MOUSE_FILTER_STOP)
	_fall_ignored.clear()
	if _current != &"modes": _screens[&"modes"].visible = false


func _finish_slide() -> void:
	if not _slide_tween: return
	var t := _slide_tween
	_slide_tween = null
	t.kill()
	for s: Control in _slide_pair: s.position = Vector2.ZERO
	if _slide_pieces and not _fall_tween: _reset_pieces()
	if _slide_hide != _current and not _fall_tween: _screens[_slide_hide].visible = false
	_blocker.visible = false


func _reset_pieces() -> void:
	for key: StringName in _pieces:
		if _piece_rest.has(key): _place(_pieces[key], _piece_rest[key], Vector2.ZERO)
		_pieces[key].rotation = 0.0


# shows a screen (the screen it replaces stays up for the slide; show_screen hides it after)
func _enter(screen: StringName) -> void:
	for key: StringName in _screens.keys(): _screens[key].visible = key == screen
	_current = screen
	var tw := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var shade: Vector3 = _SHADE[screen]
	for k: int in 3:
		var param: StringName = [&"side", &"low", &"full"][k]
		var now: Variant = _shade.get_shader_parameter(param) # (null until set: the shader's default)
		tw.tween_method(func(v: float) -> void: _shade.set_shader_parameter(param, v),
				float(now) if now != null else (1.0 if k == 0 else 0.0), shade[k], _slide.duration)
	_hints.visible = _HINTS.has(screen)
	if _hints.visible: _hints.set_hints(_HINTS[screen])
	if screen == &"title": _refresh_last()
	if screen == &"modes":
		_wheel.select(_mode_index, false) # back to what you picked last time, swinging in
		_wheel.swing_in()
		_refresh_sum()
		_wheel.grab_focus.call_deferred()
	elif screen == &"settings":
		_settings.refresh()
		_settings.first_focus().grab_focus.call_deferred()
	elif _first_focus.has(screen):
		_first_focus[screen].grab_focus.call_deferred()


func on_play_pressed() -> void:
	show_screen(&"modes")


func on_start_pressed() -> void:
	start_requested.emit(_mode_index, _bot_count, _difficulty, _map_index)


func on_quit_pressed() -> void:
	_modal.ask("QUIT TO DESKTOP?", "Your setup and settings are kept for next time.",
			[["STAY", func() -> void: pass], ["QUIT", get_tree().quit]], func() -> void: pass)


## The carousel turned to a mode.
func on_mode_selected(i: int) -> void:
	_mode_index = i
	_refresh_sum()


## Clicking the front card (or accept on the carousel): on to the next section.
func on_mode_confirmed() -> void:
	_bots.grab_focus()


func on_map_changed() -> void:
	_map_index = _map.index
	_refresh_sum()
	map_changed.emit(_map_index)


func on_bots_changed() -> void:
	_bot_count = _bots.count
	_refresh_sum()


func on_difficulty_changed() -> void:
	_difficulty = _diff.index
	_refresh_sum()


func _refresh_sum() -> void:
	if not _play_sum: return
	var mode := _modes[_mode_index].mode_name if _mode_index < _modes.size() else ""
	var map := _maps[_map_index] if _map_index < _maps.size() else ""
	_play_sum.text = "%s on %s\n%d bots, %s" % [mode, map, _bot_count, _DIFFICULTIES[_difficulty].to_lower()]


func _refresh_last() -> void:
	if _last: _last.queue_redraw()


#region building

func _build() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var backdrop := ColorRect.new()
	_shade = _BACKDROP.duplicate() as ShaderMaterial # own copy: the menu eases its shading
	backdrop.material = _shade
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
	_root.add_child(_EMBERS.instantiate())
	_screens[&"title"] = _build_title()
	_screens[&"modes"] = _build_modes()
	_settings = SettingsScreen.new()
	_settings.visible = false
	_settings.back_pressed.connect(show_screen.bind(&"title"))
	_screens[&"settings"] = _settings
	var howto := HowToScreen.new()
	howto.visible = false
	howto.back_pressed.connect(show_screen.bind(&"title"))
	_first_focus[&"howto"] = howto.first_focus()
	_screens[&"howto"] = howto
	for s: Control in _screens.values(): _root.add_child(s)
	_hints = HintBar.new()
	_hints.left_text = "WILDFIRE  ·  " + ("debug build" if OS.is_debug_build() else "v%s" % ProjectSettings.get_setting("application/config/version", "0.6"))
	_root.add_child(_hints)
	_blocker = Control.new()
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	_root.add_child(_blocker)
	_modal = MenuModal.new()
	_root.add_child(_modal)


func _build_title() -> Control:
	var screen := _screen()
	var logo := LogoTitle.new()
	logo.setup("WILDFIRE", 190)
	logo.position = Vector2(_MARGIN, 150.0)
	screen.add_child(logo)
	var tagline := UIKit.label("tag, but the tag is fire.", 32, UIKit.TEXT, UIKit.BODY)
	tagline.position = Vector2(_MARGIN + 6.0, logo.position.y + logo.custom_minimum_size.y + 8.0)
	screen.add_child(tagline)
	var box := VBoxContainer.new()
	box.position = Vector2(_MARGIN + 40.0, 520.0)
	box.add_theme_constant_override(&"separation", 18)
	screen.add_child(box)
	var play := _menu_button(box, "PLAY", on_play_pressed, "Pick a mode and a map, then go", 56, 96.0)
	_menu_button(box, "SETTINGS", show_screen.bind(&"settings"), "Controls, picture, lighting, premium")
	_menu_button(box, "HOW TO PLAY", show_screen.bind(&"howto"), "The keys, and the rules of each mode")
	_menu_button(box, "QUIT", on_quit_pressed, "Close the game")
	_first_focus[&"title"] = play
	_last = _build_last()
	screen.add_child(_last)
	return screen


func _menu_button(parent: Control, text: String, handler: Callable, sub: String, font_size: int = 30, h: float = 66.0) -> FireButton:
	var b := FireButton.new()
	b.text = text
	b.text_size = font_size
	b.sub = sub
	b.custom_minimum_size = Vector2(560.0, h)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


# bottom right of the title: what you played last (or what's set up), click it to go set up again
func _build_last() -> Control:
	var card := Control.new()
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = -96.0 - 420.0
	card.offset_right = -96.0
	card.offset_top = -120.0 - 236.0
	card.offset_bottom = -120.0
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_entered.connect(card.queue_redraw)
	card.mouse_exited.connect(card.queue_redraw)
	card.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT: on_play_pressed())
	card.draw.connect(func() -> void:
		var hover := Rect2(Vector2.ZERO, card.size).has_point(card.get_local_mouse_position())
		var at := Vector2(-10.0, -6.0) if hover else Vector2.ZERO
		UIKit.draw_slab(card, at, card.size.x, card.size.y, 14.0 if not hover else 20.0, false, 0.0,
				UIKit.SLAB_FOCUS if hover else UIKit.SLAB)
		card.draw_string(UIKit.DISPLAY_BOLD, at + Vector2(28.0, 44.0), "LAST MATCH SETUP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
				UIKit.EMBER if hover else UIKit.MUTED)
		var rows := [["Mode", _modes[_mode_index].mode_name if _mode_index < _modes.size() else ""],
				["Map", _maps[_map_index] if _map_index < _maps.size() else ""],
				["Bots", "%d" % _bot_count], ["Difficulty", _DIFFICULTIES[_difficulty]]]
		for i: int in rows.size():
			var y := at.y + 86.0 + i * 38.0
			card.draw_string(UIKit.BODY, Vector2(at.x + 28.0, y), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UIKit.MUTED)
			var v: String = rows[i][1]
			var w := UIKit.DISPLAY_BOLD.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			card.draw_string(UIKit.DISPLAY_BOLD, Vector2(at.x + card.size.x - 28.0 - w, y), v, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.TEXT))
	return card


# the match setup: a header, the carousel of mode cards up top, and along the bottom the bots,
# the map, the difficulty and PLAY
func _build_modes() -> Control:
	var screen := _screen()
	var back := FireButton.new()
	back.text = "‹  BACK"
	back.text_size = 22
	back.custom_minimum_size = Vector2(150.0, 52.0)
	back.position = Vector2(96.0, 52.0)
	back.pressed.connect(show_screen.bind(&"title"))
	screen.add_child(back)
	back.focus_mode = Control.FOCUS_NONE # Esc / B, or the mouse
	_pieces[&"back"] = back
	var title := UIKit.heading("CHOOSE YOUR FIRE", 60)
	title.position = Vector2(286.0, 50.0)
	screen.add_child(title)
	_pieces[&"title"] = title
	_wheel = ModeWheel.new()
	_wheel.card_scale = 0.7
	_wheel.front_top = 150.0
	screen.add_child(_wheel)
	_pieces[&"wheel"] = _wheel
	for i: int in _modes.size():
		var r := _modes[i]
		var card := ModeCard.new()
		card.setup(i + 1, _modes.size(), r.mode_name, r.mode_blurb, _MODE_TAGS[i % _MODE_TAGS.size()],
				_MODE_PICTURES[r.mode % _MODE_PICTURES.size()], _MODE_COLORS[i % _MODE_COLORS.size()])
		_wheel.add_card(card)
	_wheel.selected.connect(on_mode_selected)
	_wheel.confirmed.connect(on_mode_confirmed)
	# arrows either side of the carousel, beyond the side cards
	var card_size := ModeCard.SIZE * _wheel.card_scale
	for k: int in 2:
		var arrow := FireButton.new()
		arrow.text = "‹" if k == 0 else "›"
		arrow.text_size = 56
		arrow.centered = true
		arrow.custom_minimum_size = Vector2(72.0, 120.0)
		arrow.pressed.connect(_wheel.step.bind(-1 if k == 0 else 1))
		arrow.anchor_left = 0.5
		arrow.anchor_right = 0.5
		var reach := card_size.x * 0.5 + card_size.x * 0.62 + 48.0
		arrow.offset_left = -reach - 72.0 if k == 0 else reach
		arrow.offset_top = _wheel.front_top + card_size.y * 0.5 - 60.0
		arrow.offset_right = arrow.offset_left + 72.0
		arrow.offset_bottom = arrow.offset_top + 120.0
		screen.add_child(arrow)
		_pieces[&"arrow_l" if k == 0 else &"arrow_r"] = arrow
		arrow.focus_mode = Control.FOCUS_NONE # (the carousel takes left / right itself)
	# the bottom row, centred
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = 96.0
	row.offset_right = -96.0
	row.offset_top = -104.0 - 232.0
	row.offset_bottom = -104.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(row)
	_bots = BotsZone.new()
	_bots.lo = _BOTS_MIN
	_bots.hi = _BOTS_MAX
	_bots.count = _bot_count
	_bots.changed.connect(on_bots_changed)
	row.add_child(_slot(_bots, &"bots"))
	_map = MapZone.new()
	_map.setup(_maps, _map_index)
	_map.changed.connect(on_map_changed)
	row.add_child(_slot(_map, &"map"))
	_diff = DifficultyZone.new()
	_diff.index = _difficulty
	_diff.changed.connect(on_difficulty_changed)
	row.add_child(_slot(_diff, &"diff"))
	var play_col := VBoxContainer.new()
	play_col.add_theme_constant_override(&"separation", 14)
	row.add_child(_slot(play_col, &"play"))
	_play = FireButton.new()
	_play.text = "PLAY"
	_play.text_size = 60
	_play.hot = true
	_play.centered = true
	_play.custom_minimum_size = Vector2(240.0, 150.0)
	_play.pressed.connect(on_start_pressed)
	play_col.add_child(_play)
	_play_sum = UIKit.label("", 17, UIKit.MUTED)
	_play_sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_col.add_child(_play_sum)
	_refresh_sum()
	# sections in order, up / down (left / right change values): the carousel, bots, map, difficulty, PLAY
	var chain: Array[Control] = [_wheel, _bots, _map, _diff, _play]
	for i: int in chain.size():
		var c := chain[i]
		c.focus_neighbor_top = c.get_path_to(chain[maxi(i - 1, 0)])
		c.focus_neighbor_bottom = c.get_path_to(chain[mini(i + 1, chain.size() - 1)])
		c.focus_previous = c.focus_neighbor_top
		c.focus_next = c.focus_neighbor_bottom
	_play.focus_neighbor_left = _play.get_path_to(_diff)
	_play.focus_neighbor_right = _play.get_path_to(_play)
	# accept moves on to the next section (on PLAY it plays)
	for z: MenuZone in [_bots, _map, _diff]:
		z.gui_input.connect(func(e: InputEvent) -> void:
			if e.is_action_pressed(&"ui_accept"):
				(z.get_node(z.focus_neighbor_bottom) as Control).grab_focus()
				z.accept_event())
	return screen


# A box in the bottom row sits in a plain Control of its size, so it can be moved about by hand
# (a container would put it back); it fills the slot.
func _slot(child: Control, key: StringName) -> Control:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_vertical = Control.SIZE_FILL
	slot.add_child(child)
	child.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.custom_minimum_size = child.get_combined_minimum_size()
	child.minimum_size_changed.connect(func() -> void: slot.custom_minimum_size = child.get_combined_minimum_size())
	_pieces[key] = child
	return slot


func _screen() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.visible = false
	return s

#endregion
