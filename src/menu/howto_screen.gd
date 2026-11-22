class_name HowToScreen
extends Control
## How to play: on the left the keys (and the mouse) as caps that sink and glow while you press
## them, with what each does; on the right the rules of one mode, picked with the tabs or left /
## right: the goal, three steps and a tip. BACK (or Esc, handled by the menu) emits back_pressed.

signal back_pressed

const _TOP := 176.0
const _LEFT_W := 760.0
const _GAP := 32.0
# [label, physical key, x, y, width] (px in the keys panel)
const _KEYS: Array = [
	["Q", KEY_Q, 0, 0, 52], ["W", KEY_W, 60, 0, 52], ["E", KEY_E, 120, 0, 52], ["R", KEY_R, 180, 0, 52],
	["A", KEY_A, 16, 60, 52], ["S", KEY_S, 76, 60, 52], ["D", KEY_D, 136, 60, 52], ["C", KEY_C, 196, 60, 52],
	["SHIFT", KEY_SHIFT, 0, 120, 112], ["V", KEY_V, 120, 120, 52], ["TAB", KEY_TAB, 180, 120, 72],
	["CTRL", KEY_CTRL, 0, 180, 84], ["SPACE", KEY_SPACE, 92, 180, 300],
]
const _LEGEND: Array = [
	["W A S D", "Move (the arrows too)"],
	["Space", "Jump; hold it for full height"],
	["Shift / right mouse", "Dash"],
	["Ctrl / C", "Slide; in the air, slam"],
	["Q", "Brake; in the air, a brake slam"],
	["R", "Respawn"],
	["Middle mouse", "Hold: free look"],
	["V", "First or third person"],
	["Tab", "Scoreboard"],
	["F1", "Every rule and number"],
	["Esc", "Pause"],
]
const _RULES: Array = [
	["CLASSIC", "Spend the least time on fire.", [
		["The Torch", "One player is on fire. Touch someone and the fire is theirs. The new Torch is frozen a moment and can't light the last one straight back."],
		["Fight back", "Hit anyone at 20+ m/s (blue flames on screen) to shove them. Shoving the Torch is a snuff: 3 s off your time."],
		["No hiding", "The dry outer ring heats you up, and standing still makes you smoke. Either way, you catch fire."]],
		"Lowest score wins: time burning, minus 3 s a snuff and 1 s a shove."],
	["SPREAD", "Stay unlit the longest.", [
		["Patient zero", "One Torch starts it, frozen for a few seconds while everyone scatters."],
		["It spreads", "Everyone the fire touches becomes another Torch. It only grows."],
		["Hold out", "Your score is how long you stayed unlit."]],
		"A shove still works: knock a Torch away before it reaches you."],
	["HUNTED", "Stay unlit. It's you against the swarm.", [
		["The swarm", "The bots burn as one: while they're on fire, all of them hunt you."],
		["Lit", "When they light you, their fire goes out. Touch any bot and the whole swarm is burning again."],
		["Stay out", "The less time you spend on fire, the better you do."]],
		"A shove still stuns a bot: buy yourself a gap."],
	["HOT POTATO", "Be the last one standing.", [
		["The fuse", "The fire burns for about 20 seconds. Whoever holds it when it blows is out."],
		["Pass it on", "Touch someone to hand it over. The fuse shows on the HUD and turns red in its last 5 seconds."],
		["The storm", "A wall of fire starts closing in. Outside it you heat up, then burn out."]],
		"Burned out? Watch the rest: jump to switch who you follow."],
	["FREEZE", "Hold out until the clock, or freeze everyone.", [
		["Solid", "The Torches freeze runners on touch and stay Torches. A frozen runner can't move until they're melted."],
		["Melt", "Stand next to a frozen runner for a second and a half: the ice lets go. You can't be frozen again for a couple of seconds."],
		["The end", "Freeze every runner and the fire wins. Any runner free at the buzzer and the runners win."]],
		"After 20 s with no touch, hunter's sense shows the nearest runner through walls."],
]

var _mode := 0
var _down: Dictionary[int, bool] = {} # physical key or -mouse button -> held
var _keys_panel: Control
var _rules_panel: Control
var _tabs: Array[FireButton] = []
var _r_name: Label
var _r_goal: Label
var _r_steps: VBoxContainer
var _r_tip: RichTextLabel


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL
	_build()


## Where focus goes when the screen opens (it takes the keys itself).
func first_focus() -> Control:
	return self


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	var k := event as InputEventKey
	if k and not k.echo:
		var code := int(k.physical_keycode)
		if k.pressed: _down[code] = true
		else: _down.erase(code)
		_keys_panel.queue_redraw()
	var mb := event as InputEventMouseButton
	if mb and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if mb.pressed: _down[-mb.button_index] = true
		else: _down.erase(-mb.button_index)
		_keys_panel.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"): show_mode(posmod(_mode - 1, _RULES.size()))
	elif event.is_action_pressed(&"ui_right"): show_mode(posmod(_mode + 1, _RULES.size()))
	else: return
	accept_event()


func show_mode(i: int) -> void:
	_mode = i
	for t: int in _tabs.size(): _tabs[t].hot = t == i
	var r: Array = _RULES[i]
	_r_name.text = r[0]
	_r_goal.text = r[1]
	for c: Node in _r_steps.get_children(): c.queue_free()
	for s: int in 3:
		var step: Array = r[2][s]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 18)
		var num := Control.new()
		num.custom_minimum_size = Vector2(48.0, 48.0)
		num.draw.connect(func() -> void:
			num.draw_rect(Rect2(Vector2.ZERO, num.size), UIKit.KEY)
			var t := "%d" % (s + 1)
			var w := UIKit.DISPLAY.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			num.draw_string(UIKit.DISPLAY, Vector2((num.size.x - w) * 0.5, 34.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UIKit.TEXT))
		row.add_child(num)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override(&"separation", 2)
		row.add_child(col)
		var head := _plain(col, 22, UIKit.TEXT, UIKit.DISPLAY_BOLD)
		head.text = step[0].to_upper()
		var body := _plain(col, 18, UIKit.MUTED)
		body.text = step[1]
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_r_steps.add_child(row)
	_r_tip.text = "[color=#ff6a1a]TIP[/color]   " + r[3]


#region building

func _build() -> void:
	var back := FireButton.new()
	back.text = "‹  BACK"
	back.text_size = 22
	back.custom_minimum_size = Vector2(150.0, 52.0)
	back.position = Vector2(96.0, 52.0)
	back.click_sound = &"ui_back"
	back.pressed.connect(back_pressed.emit)
	add_child(back)
	back.focus_mode = Control.FOCUS_NONE
	var title := UIKit.heading("HOW TO PLAY", 60)
	title.position = Vector2(286.0, 50.0)
	add_child(title)
	# keys
	_keys_panel = Control.new()
	_keys_panel.position = Vector2(96.0, _TOP)
	_keys_panel.size = Vector2(_LEFT_W, 744.0)
	_keys_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_panel.draw.connect(_draw_keys)
	add_child(_keys_panel)
	var legend := GridContainer.new()
	legend.columns = 2
	legend.position = Vector2(36.0, 340.0)
	legend.add_theme_constant_override(&"h_separation", 28)
	legend.add_theme_constant_override(&"v_separation", 6)
	_keys_panel.add_child(legend)
	for pair: Array in _LEGEND:
		var k := _plain(legend, 19, UIKit.TEXT, UIKit.DISPLAY_BOLD)
		k.text = pair[0]
		var v := _plain(legend, 19, UIKit.MUTED)
		v.text = pair[1]
	# rules
	_rules_panel = Control.new()
	_rules_panel.anchor_right = 1.0
	_rules_panel.offset_left = 96.0 + _LEFT_W + _GAP
	_rules_panel.offset_right = -96.0
	_rules_panel.offset_top = _TOP
	_rules_panel.offset_bottom = _TOP + 744.0
	_rules_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules_panel.draw.connect(func() -> void: UIKit.draw_slab(_rules_panel, Vector2.ZERO, _rules_panel.size.x, _rules_panel.size.y, 16.0, false, 0.0))
	_rules_panel.resized.connect(_rules_panel.queue_redraw)
	add_child(_rules_panel)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 36.0
	col.offset_right = -36.0
	col.offset_top = 34.0
	col.offset_bottom = -30.0
	col.add_theme_constant_override(&"separation", 14)
	_rules_panel.add_child(col)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 14)
	col.add_child(tabs)
	for i: int in _RULES.size():
		var t := FireButton.new()
		t.text = _RULES[i][0]
		t.text_size = 20
		t.centered = true
		t.custom_minimum_size = Vector2(0.0, 52.0)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.pressed.connect(show_mode.bind(i))
		tabs.add_child(t)
		t.focus_mode = Control.FOCUS_NONE
		_tabs.append(t)
	col.add_child(UIKit.gap(16.0))
	_r_name = _plain(col, 64, UIKit.TEXT, UIKit.DISPLAY)
	_r_goal = _plain(col, 21, UIKit.MUTED)
	col.add_child(UIKit.gap(8.0))
	_r_steps = VBoxContainer.new()
	_r_steps.add_theme_constant_override(&"separation", 22)
	col.add_child(_r_steps)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_r_tip = RichTextLabel.new()
	_r_tip.bbcode_enabled = true
	_r_tip.fit_content = true
	_r_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_r_tip.add_theme_font_size_override(&"normal_font_size", 18)
	_r_tip.add_theme_color_override(&"default_color", UIKit.MUTED)
	_r_tip.add_theme_constant_override(&"shadow_offset_x", 0)
	_r_tip.add_theme_constant_override(&"shadow_offset_y", 0)
	col.add_child(_r_tip)
	var hints := HintBar.new()
	hints.set_hints([[["←", "→"], "Mode rules"], [["Esc"], "Back"]])
	add_child(hints)
	show_mode(0)


func _plain(parent: Control, font_size: int, color: Color, font: Font = null) -> Label:
	var l := UIKit.label("", font_size, color, font)
	l.theme_type_variation = &""
	parent.add_child(l)
	return l


# the panel, the caps (sunk and hot while held) and the mouse beside them
func _draw_keys() -> void:
	var p := _keys_panel
	UIKit.draw_slab(p, Vector2.ZERO, p.size.x, p.size.y, 16.0, false, 0.0)
	p.draw_string(UIKit.DISPLAY_BOLD, Vector2(36.0, 52.0), "CONTROLS  ·  PRESS THE KEYS TO TRY THEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.MUTED)
	var o := Vector2(36.0, 76.0)
	for k: Array in _KEYS:
		UIKit.draw_key(p, o + Vector2(k[2], k[3]), k[4], k[0], _down.has(k[1]), 50.0)
	# the mouse: a body with three buttons (left plain; right dash; middle free look)
	var m := o + Vector2(470.0, 0.0)
	var body := _mouse_shape(m, Vector2(140.0, 220.0))
	var drop := body.duplicate()
	for i: int in drop.size(): drop[i] += Vector2(0.0, 8.0)
	p.draw_colored_polygon(drop, UIKit.KEY_SIDE)
	p.draw_colored_polygon(body, UIKit.KEY)
	var half := 70.0
	# the two buttons (lit while held), split by a groove, and the wheel between them
	for b: Array in [[MOUSE_BUTTON_LEFT, true], [MOUSE_BUTTON_RIGHT, false]]:
		if _down.has(-int(b[0])): p.draw_colored_polygon(_button_shape(m, half, b[1]), UIKit.EMBER)
	p.draw_line(m + Vector2(half, 0.0), m + Vector2(half, 92.0), UIKit.KEY_SIDE, 4.0)
	p.draw_line(m + Vector2(0.0, 92.0), m + Vector2(140.0, 92.0), UIKit.KEY_SIDE, 4.0)
	p.draw_rect(Rect2(m + Vector2(half - 9.0, 26.0), Vector2(18.0, 40.0)), UIKit.EMBER if _down.has(-MOUSE_BUTTON_MIDDLE) else UIKit.SLAB_SIDE)
	var note := m + Vector2(164.0, 0.0)
	p.draw_string(UIKit.DISPLAY_BOLD, note + Vector2(0.0, 40.0), "RIGHT: DASH", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.MUTED)
	p.draw_string(UIKit.DISPLAY_BOLD, note + Vector2(0.0, 70.0), "MIDDLE (HOLD):", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.MUTED)
	p.draw_string(UIKit.DISPLAY_BOLD, note + Vector2(0.0, 92.0), "FREE LOOK", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.MUTED)


# one of the mouse's buttons (the top of its shape, either side of the groove), inset a little
func _button_shape(at: Vector2, r: float, left: bool) -> PackedVector2Array:
	var inset := 4.0
	var c := at + Vector2(r, r)
	var pts := PackedVector2Array()
	var a0 := PI if left else PI * 1.5
	for i: int in 9:
		var a := a0 + PI * 0.5 * i / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r - inset))
	if left:
		pts.set(pts.size() - 1, Vector2(at.x + r - inset, pts[pts.size() - 1].y))
		pts.append(at + Vector2(r - inset, 88.0))
		pts.append(at + Vector2(inset, 88.0))
	else:
		pts.set(0, Vector2(at.x + r + inset, pts[0].y))
		pts.append(at + Vector2(2.0 * r - inset, 88.0))
		pts.append(at + Vector2(r + inset, 88.0))
	return pts


# a mouse from above: straight sides, round top and bottom
func _mouse_shape(at: Vector2, sz: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := sz.x * 0.5
	for i: int in 17: # the top half-circle, left to right
		var a := PI + PI * i / 16.0
		pts.append(at + Vector2(r, r) + Vector2(cos(a), sin(a)) * r)
	for i: int in 17: # the bottom, right to left
		var a := PI * i / 16.0
		pts.append(at + Vector2(r, sz.y - r) + Vector2(cos(a), sin(a)) * r)
	return pts

#endregion
