class_name SettingsScreen
extends Control
## Every player setting, shared by the title screen and the pause menu: tabs down the left (Q / E,
## or LB / RB, switch them), the open tab's rows in the middle (up / down pick, left / right
## change), and on the right what the focused setting does, what it costs and its default, with
## ULTRA PRESET, RESET TO DEFAULTS (asks first) and, over a paused game, PREVIEW under it.
## Changes apply and save as you make them; BACK (or Esc, handled by whoever shows this) emits
## back_pressed.

signal back_pressed
## PREVIEW was pressed (only shown after show_preview(): the pause menu, with a game behind it)
signal preview_pressed

const _TOP := 176.0
const _TABS_X := 96.0
const _TABS_W := 264.0
const _ROWS_X := 392.0
const _ROWS_W := 840.0
const _GAP := 32.0

# the tabs and their rows: [label, key, options] for a choice, [label, key, lo, hi, step, fmt] for a slider
const _OFF_ON: Array[String] = ["Off", "On"]
var _tab_defs: Array = [
	["CONTROLS", [
		["Mouse sensitivity", STG.MOUSE_SENS, 0.2, 10.0, 0.05, "%.2f"],
		["Field of view", STG.FOV, 60.0, 130.0, 1.0, "%.0f°"],
		["Third person", STG.THIRD_PERSON, _OFF_ON],
		["Speed effects", STG.SPEED_FX, ["Off", "Low", "Medium", "High"]],
		["Camera shake", STG.CAMERA_SHAKE, ["Off", "Low", "Full"]],
		["Performance HUD", STG.PERF_HUD, ["Off", "FPS", "Full"]],
	]],
	["AUDIO", [
		["Master volume", STG.VOL_MASTER, 0.0, 100.0, 5.0, "%.0f%%"],
		["Music", STG.VOL_MUSIC, 0.0, 100.0, 5.0, "%.0f%%"],
		["Sound effects", STG.VOL_SFX, 0.0, 100.0, 5.0, "%.0f%%"],
		["Menu sounds", STG.VOL_UI, 0.0, 100.0, 5.0, "%.0f%%"],
		["Ambience", STG.VOL_AMBIENCE, 0.0, 100.0, 5.0, "%.0f%%"],
	]],
	["PICTURE", [
		["Render scale", STG.RENDER_SCALE, 0.4, 1.0, 0.05, "%.2f"],
		["VSync", STG.VSYNC, ["Off", "Adaptive", "On"]],
		["Edge smoothing: FXAA", STG.FXAA, _OFF_ON],
		["Edge smoothing: MSAA 2×", STG.MSAA, _OFF_ON],
		["Glow", STG.GLOW, _OFF_ON],
		["Ambient shadows (SSAO)", STG.SSAO, _OFF_ON],
	]],
	["LIGHTING", [
		["Shadow quality", STG.SHADOWS, ["Low", "Medium", "High"]],
		["Leaf shadows", STG.LEAF_SHADOWS, ["Off", "Low", "Medium", "High"]],
		["Fast shadows", STG.FAST_SHADOWS, _OFF_ON],
		["Lighting", STG.LIGHTING, ["Low", "High"]],
	]],
	["PREMIUM", [
		["Edge smoothing: TAA", STG.TAA, _OFF_ON],
		["Reflections (SSR)", STG.SSR, _OFF_ON],
		["Coloured bounce light (SSIL)", STG.SSIL, _OFF_ON],
		["Soft shadows", STG.SOFT_SHADOWS, _OFF_ON],
		["Detailed sun shafts", STG.FOG_DETAIL, _OFF_ON],
		["Eye adaptation", STG.AUTO_EXPOSURE, _OFF_ON],
		["Smooth glow", STG.GLOW_HQ, _OFF_ON],
		["Live global illumination (SDFGI)", STG.LIVE_GI, _OFF_ON],
	]],
]

# what each setting does: [words, cost 0..4, measured cost or ""]
const _ABOUT := {
	&"mouse_sensitivity": ["How far the view turns for a given move of the mouse.", 0, ""],
	&"fov": ["How wide you see. Wider shows chasers coming in from the side, but makes far things smaller.", 1, ""],
	&"third_person": ["See your runner from behind instead of through its eyes. V switches it during a match.", 1, ""],
	&"speed_fx": ["The streaks, blue flames and blur once you're going fast. Lower levels drop the full-screen passes.", 1, ""],
	&"camera_shake": ["The jolt when a slam-jump hits the ground near you, bigger the higher the slam. Low halves it.", 0, ""],
	&"perf_hud": ["The frame rate in the corner (FPS), or where the whole frame goes (Full).", 0, ""],
	&"vol_master": ["The overall volume of everything below.", 0, ""],
	&"vol_music": ["The music. (There is none yet.)", 0, ""],
	&"vol_sfx": ["Footsteps, slides, dashes, fire, shoves and the round's own sounds, yours and the bots'.", 0, ""],
	&"vol_ui": ["Clicks, slides and pops in the menus.", 0, ""],
	&"vol_ambience": ["What each map sounds like underneath: wind, birds, lava.", 0, ""],
	&"render_scale": ["The share of the screen's resolution the world is drawn at, then scaled up. The biggest single lever on frame rate.", 4, ""],
	&"vsync": ["Stops the picture tearing. Adaptive lets a late frame tear rather than stutter; On never tears but can stutter when the frame rate drops.", 1, ""],
	&"fxaa": ["Cheap edge smoothing over the whole picture. Softens jagged edges with a touch of blur.", 1, ""],
	&"msaa": ["Smooths the edges of shapes properly, two samples a pixel. Sharper than FXAA, dearer on busy maps.", 2, ""],
	&"glow": ["Bright things bleed light: the lava, the fire, the Torch.", 1, ""],
	&"ssao": ["Darkens creases and corners where light can't reach, so things sit in the world.", 2, ""],
	&"shadows": ["The sun's shadows. Low is soft and solid; Medium and High are crisper and cost more on the big maps.", 3, ""],
	&"leaf_shadows": ["Dappled shadows under the trees, mostly in the Jungle. Off and Low are soft blobs; Medium and High cut out every leaf.", 3, "Low saves about 2.4 ms in the Jungle."],
	&"fast_shadows": ["Cheaper, harder-edged sun shadows. The Jungle starts with it on.", 2, "With Low leaf shadows: about 6.4 ms saved in the Jungle."],
	&"lighting": ["High adds baked bounce light (the Inferno, the Jungle's temple) and volumetric fog with sun shafts.", 3, ""],
	&"taa": ["Smooths edges over several frames: no shimmer on leaves, smoother soft shadows. Can blur a little in fast motion.", 3, "Measured: +5.3 ms (Jungle fly-through)."],
	&"ssr": ["Reflections in the lava, the pools and the river.", 4, "Measured: +9.1 ms (Jungle fly-through)."],
	&"ssil": ["Coloured light bouncing off things: lava painting the walls red, grass tinting the stone.", 4, "Measured: +10.3 ms (Jungle fly-through)."],
	&"soft_shadows": ["Shadows sharp where they touch and softer further off, like real sunlight.", 4, "Measured: +18.1 ms (Jungle fly-through)."],
	&"fog_detail": ["Volumetric fog at twice the detail: crisper sun shafts. Needs Lighting High.", 3, "Measured: +5.8 ms (Jungle), +15 ms (Inferno)."],
	&"auto_exposure": ["Your eyes adjust: dark halls and the canopy brighten a little, and bright patches ease off.", 1, "Measured: +0.4 ms."],
	&"glow_hq": ["A smoother, rounder glow.", 1, "Measured: +0.5 ms."],
	&"live_gi": ["Bounce light worked out live, everywhere. Very heavy, worst when you're moving fast.", 4, "Measured: +29 ms (Jungle fly-through)."],
}

var _tab := 0
var _tabs: Array[FireButton] = []
var _rows: Array[SettingRow] = []
var _rows_box: VBoxContainer
var _rows_panel: Control
var _detail: Control
var _d_title: Label
var _d_text: Label
var _d_opts: Label
var _d_cost: Control
var _d_measured: Label
var _d_default: Label
var _d_now: Label
var _actions: VBoxContainer
var _ultra: FireButton
var _reset: FireButton
var _preview: FireButton
var _back: FireButton
var _modal: MenuModal
var _hints: HintBar
var _focused: SettingRow


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


## Shows PREVIEW (there's a paused game behind to look at).
func show_preview() -> void:
	_preview.visible = true
	_wire_actions()


## The PREVIEW button (to give focus back to after a preview).
func preview_button() -> Control:
	return _preview


## Where focus starts when the screen is shown.
func first_focus() -> Control:
	return (_rows[0] as Control) if not _rows.is_empty() else (_back as Control)


## Re-reads every row from STG (after a reset, or if something else changed a setting).
func refresh() -> void:
	for r: SettingRow in _rows: r.queue_redraw()
	_show_detail(_focused)


func is_asking() -> bool:
	return _modal.is_open()


# Q / E (and LB / RB) switch tabs from wherever the focus is on this screen
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _modal.is_open(): return
	var k := event as InputEventKey
	var jb := event as InputEventJoypadButton
	var dir := 0
	if k and k.pressed and not k.echo:
		match k.physical_keycode:
			KEY_Q, KEY_PAGEUP: dir = -1
			KEY_E, KEY_PAGEDOWN: dir = 1
	elif jb and jb.pressed:
		if jb.button_index == JOY_BUTTON_LEFT_SHOULDER: dir = -1
		elif jb.button_index == JOY_BUTTON_RIGHT_SHOULDER: dir = 1
	if dir == 0: return
	open_tab(posmod(_tab + dir, _tab_defs.size()))
	get_viewport().set_input_as_handled()


## Opens tab i, the focus on its first row.
func open_tab(i: int, focus: bool = true) -> void:
	_tab = i
	for t: int in _tabs.size(): _tabs[t].hot = t == i
	for r: SettingRow in _rows: r.queue_free()
	_rows.clear()
	for spec: Array in _tab_defs[i][1]:
		var row := SettingRow.choice(spec[0], spec[1], PackedStringArray(spec[2])) if spec.size() == 3 \
				else SettingRow.slider(spec[0], spec[1], spec[2], spec[3], spec[4], spec[5])
		row.focus_entered.connect(_show_detail.bind(row))
		_rows_box.add_child(row)
		_rows.append(row)
	_rows_panel.custom_minimum_size.y = _rows.size() * SettingRow.H + 24.0
	_rows_panel.size.y = _rows_panel.custom_minimum_size.y
	_ultra.visible = _tab_defs[i][0] == "PREMIUM"
	_wire_actions()
	if focus: _rows[0].grab_focus()
	_show_detail(_rows[0])


func on_ultra_pressed() -> void:
	STG.apply_ultra()
	refresh()


func on_reset_pressed() -> void:
	_modal.ask("RESET EVERY SETTING?", "Back to the defaults (this map's own where it has them). Your mouse and view settings too.",
			[["KEEP MINE", func() -> void: pass], ["RESET", _reset_now]], func() -> void: pass)


func _reset_now() -> void:
	STG.reset_to_defaults()
	refresh()


# up / down through the rows, then on into the buttons under the detail and back up
func _wire_actions() -> void:
	var chain: Array[Control] = []
	for r: SettingRow in _rows: chain.append(r)
	for b: FireButton in [_ultra, _reset, _preview]: if b.visible: chain.append(b)
	for i: int in chain.size():
		var c := chain[i]
		c.focus_neighbor_top = c.get_path_to(chain[maxi(i - 1, 0)])
		c.focus_neighbor_bottom = c.get_path_to(chain[mini(i + 1, chain.size() - 1)])
		c.focus_previous = c.focus_neighbor_top
		c.focus_next = c.focus_neighbor_bottom
		if c is FireButton:
			c.focus_neighbor_left = c.get_path_to(c)
			c.focus_neighbor_right = c.get_path_to(c)


func _show_detail(row: SettingRow) -> void:
	if not is_instance_valid(row): return
	_focused = row
	var about: Array = _ABOUT.get(row.key, ["", 0, ""])
	_d_title.text = row.label
	_d_text.text = about[0]
	if row.is_choice():
		var cur := clampi(roundi(row.value()), 0, row.options.size() - 1)
		var words: PackedStringArray = []
		for i: int in row.options.size(): words.append(("[%s]" % row.options[i]) if i == cur else row.options[i])
		_d_opts.text = "    ".join(words)
	else:
		_d_opts.text = "From %s to %s" % [row.fmt % row.lo, row.fmt % row.hi]
	_d_cost.set_meta(&"cost", about[1])
	_d_cost.queue_redraw()
	_d_measured.text = about[2]
	_d_default.text = row.text_of(STG.get_default(row.key))
	_d_now.text = row.text_of(row.value())


func _process(_delta: float) -> void:
	# the detail's "now" follows the focused row as it changes
	if is_visible_in_tree() and is_instance_valid(_focused):
		var now := _focused.text_of(_focused.value())
		if _d_now.text != now: _show_detail(_focused)


#region building

func _build() -> void:
	_back = _slab_button(self, "‹  BACK", back_pressed.emit, Vector2(150.0, 52.0), 22)
	_back.click_sound = &"ui_back"
	_back.position = Vector2(96.0, 52.0)
	_back.focus_mode = Control.FOCUS_NONE # Esc / B, or the mouse
	var title := UIKit.heading("SETTINGS", 60)
	title.position = Vector2(286.0, 50.0)
	add_child(title)
	# tabs
	var tabs := VBoxContainer.new()
	tabs.position = Vector2(_TABS_X, _TOP)
	tabs.custom_minimum_size.x = _TABS_W
	tabs.add_theme_constant_override(&"separation", 14)
	add_child(tabs)
	for i: int in _tab_defs.size():
		var t := _slab_button(tabs, "%s" % _tab_defs[i][0], open_tab.bind(i), Vector2(_TABS_W, 60.0), 24)
		t.focus_mode = Control.FOCUS_NONE # Q / E, LB / RB, or the mouse
		t.sub = "%d" % _tab_defs[i][1].size()
		_tabs.append(t)
	# rows
	_rows_panel = Control.new()
	_rows_panel.position = Vector2(_ROWS_X, _TOP)
	_rows_panel.size = Vector2(_ROWS_W, 100.0)
	_rows_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_panel.draw.connect(func() -> void: UIKit.draw_slab(_rows_panel, Vector2.ZERO, _rows_panel.size.x, _rows_panel.size.y, 16.0, false, 0.0))
	_rows_panel.resized.connect(_rows_panel.queue_redraw)
	add_child(_rows_panel)
	_rows_box = VBoxContainer.new()
	_rows_box.position = Vector2(0.0, 12.0)
	_rows_box.size = Vector2(_ROWS_W, 0.0)
	_rows_box.add_theme_constant_override(&"separation", 0)
	_rows_panel.add_child(_rows_box)
	# detail
	_detail = Control.new()
	_detail.anchor_right = 1.0
	_detail.offset_left = _ROWS_X + _ROWS_W + _GAP
	_detail.offset_right = -96.0
	_detail.offset_top = _TOP
	_detail.offset_bottom = _TOP + 452.0
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.draw.connect(func() -> void: UIKit.draw_slab(_detail, Vector2.ZERO, _detail.size.x, _detail.size.y, 16.0, false, 0.0))
	_detail.resized.connect(_detail.queue_redraw)
	add_child(_detail)
	var d := VBoxContainer.new()
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.offset_left = 32.0
	d.offset_right = -32.0
	d.offset_top = 28.0
	d.offset_bottom = -24.0
	d.add_theme_constant_override(&"separation", 12)
	_detail.add_child(d)
	_d_title = _plain(d, 36, UIKit.TEXT, UIKit.DISPLAY)
	_d_text = _plain(d, 19, UIKit.MUTED)
	_d_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_opts = _plain(d, 18, UIKit.TEXT, UIKit.DISPLAY_BOLD)
	_d_opts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.add_child(spacer)
	_d_measured = _plain(d, 17, UIKit.EMBER)
	_d_measured.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_cost = _line(d, "Performance cost", null)
	_d_cost.draw.connect(_draw_cost)
	_d_default = _line(d, "Default", "") as Label
	_d_now = _line(d, "Now", "") as Label
	# actions under the detail
	_actions = VBoxContainer.new()
	_actions.anchor_right = 1.0
	_actions.offset_left = _detail.offset_left
	_actions.offset_right = -96.0
	_actions.offset_top = _detail.offset_bottom + 36.0
	_actions.add_theme_constant_override(&"separation", 14)
	add_child(_actions)
	_ultra = _slab_button(_actions, "ULTRA PRESET", on_ultra_pressed, Vector2(0.0, 76.0), 24)
	_ultra.sub = "every premium effect but live GI"
	_reset = _slab_button(_actions, "RESET TO DEFAULTS", on_reset_pressed, Vector2(0.0, 56.0), 24)
	_preview = _slab_button(_actions, "PREVIEW", preview_pressed.emit, Vector2(0.0, 76.0), 24)
	_preview.sub = "hide the menu; any key comes back"
	_preview.visible = false
	_hints = HintBar.new()
	_hints.set_hints([[["Q", "E"], "Tab"], [["↑", "↓"], "Setting"], [["←", "→"], "Change"], [["Esc"], "Back"]])
	add_child(_hints)
	_modal = MenuModal.new()
	add_child(_modal)
	open_tab(0, false)


func _slab_button(parent: Control, text: String, handler: Callable, min_size: Vector2, font_size: int) -> FireButton:
	var b := FireButton.new()
	b.text = text
	b.text_size = font_size
	b.custom_minimum_size = min_size
	b.centered = parent == _actions
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _plain(parent: Control, font_size: int, color: Color, font: Font = null) -> Label:
	var l := UIKit.label("", font_size, color, font)
	l.theme_type_variation = &"" # on a panel: no shadow
	parent.add_child(l)
	return l


# "name ........ value" on one line; value null: a slot to draw in (returned)
func _line(parent: Control, name_: String, value: Variant) -> Control:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var n := _plain(row, 18, UIKit.MUTED)
	n.text = name_
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if value == null:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(4.0 * 34.0, 24.0)
		row.add_child(slot)
		return slot
	var v := _plain(row, 20, UIKit.TEXT, UIKit.DISPLAY_BOLD)
	v.text = value
	return v


func _draw_cost() -> void:
	var cost: int = _d_cost.get_meta(&"cost", 0)
	for i: int in 4:
		var c := (UIKit.EMBER if cost >= 3 else UIKit.TEXT) if i < cost else Color(UIKit.TEXT, 0.16)
		_d_cost.draw_rect(Rect2(i * 34.0, 8.0, 30.0, 8.0), c)

#endregion
