extends Control

# F1 cheat sheet: every control and mechanic, with numbers pulled live from the
# MovementConfig so it stays right while you tune.

## Where the rule numbers come from (the pause menu hands it over). Without one: MatchRules defaults.
var tag_manager: TagManager

var _character: Character
var _text: RichTextLabel


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS # usable from the pause menu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"help"):
		toggle()
		get_viewport().set_input_as_handled()


## Hands over the character the numbers are read from. Call once, from the HUD.
func setup(character: Character) -> void:
	if not character or not character.config:
		push_error("HelpOverlay.setup() needs a character with a config")
		return
	_character = character
	_build()


## Shows/hides the cheat sheet. Doesn't touch the mouse, you can keep playing with it open.
func toggle() -> void:
	if not _character: return
	visible = not visible
	if visible: _text.text = _compose()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DarkPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60.0
	panel.offset_top = 40.0
	panel.offset_right = -60.0
	panel.offset_bottom = -40.0
	add_child(panel)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override(&"normal_font_size", 19)
	_text.add_theme_font_size_override(&"bold_font_size", 19)
	panel.add_child(_text)


func _compose() -> String:
	var c := _character.config
	var r := tag_manager.rules if tag_manager and tag_manager.rules else MatchRules.new()
	var lines: PackedStringArray = [
		"[b][color=#ff9e33]WILDFIRE[/color][/b]   (F1 closes)",
		"One player is [b]the Torch[/b]: on fire, glowing, name shown through walls. Touch someone to [b]set them alight[/b] and the fire is theirs. Everyone else is kindling. Lowest [b]score[/b] wins: time burning, minus %.0f s per [b]snuff[/b] (shoving the Torch) and %.0f s per shove on kindling." % [r.snuff_bonus, r.shove_bonus],
		"[b]Modes[/b] (pause menu): [b]Classic[/b] one Torch, passes on touch. [b]Spread[/b] everyone you light becomes another Torch; survive the longest. [b]Hunted[/b] you vs the swarm: the bots burn as one, lighting any of them sets them all on fire, getting lit puts them all out; stay unlit. [b]Hot Potato[/b] the fire has a fuse: hold it when it blows and you're out, and a storm of fire closes in. Last one standing wins.",
		"A fresh Torch is frozen for a moment, and the last Torch can't be set alight straight back. The Torch runs %d%% faster. Hold [b]Tab[/b] for the scoreboard." % int(round((r.torch_speed_mult - 1.0) * 100.0)),
		"[b]Shove[/b]: run into anyone (even the Torch) at 20+ m/s, a point-blank dash counts, and they're stunned for a moment, but you bounce off a bit dizzy. [b]Stomp[/b]: slam (Ctrl or Q in the air) down onto someone after falling %.0f m or more and they're stunned too; you bounce back up. The Torch touching you always just sets you alight." % r.stomp_min_drop,
		"[b]Dry edge[/b]: the outer ring of the map (amber on the ground) heats kindling up. Full heat and you [b]smolder[/b]: your time burning ticks up without being the Torch, until you cool off back inside.",
		"[b]Smoke[/b]: stay within %.0f m of one spot for %.0f s and you start [b]smoking[/b]. Move within %.0f s or you [b]catch fire and become the Torch[/b]. No hiding." % [r.still_distance, r.still_time, r.smoke_time],
		"Bots only see what's in front of them (plus a glance back now and then) and hear you up close: sneak up from behind. A [b]red screen edge[/b] and arrow mean a bot is hunting you.",
		"Bots notice when you hover around them, stare at them or dash at them. Push it and they either [b]come for you[/b] (they'll shove first) or bolt. Watch what they shout.",
		"[b]Blue flames + cyan crosshair[/b] = you're over 20 m/s: fast enough to shove someone (and to bonk walls if you've had a run-up). [b]Violet flames + sparks[/b] = overdrive, over %.0f m/s." % _character.config.overdrive_speed,
		"",
		"[b][color=#ff9e33]CONTROLS[/color][/b]",
		"Move [b]WASD[/b] or [b]arrows[/b] / left stick    Look [b]mouse[/b] / right stick    Jump [b]Space[/b] / A",
		"Slide / slam [b]Ctrl[/b] or [b]C[/b] / B    Dash [b]Shift[/b] or [b]right mouse[/b] / RB    Brake [b]Q[/b] / LB    Respawn [b]R[/b]",
		"[b]Esc[/b] pause    [b]F11[/b] fullscreen    [b]V[/b] 1st / 3rd person",
		"[color=#888888][DEBUG]  [b]F2[/b] tuning sliders    [b]F3[/b] readout    [b]F4[/b] slow-mo    [b]F6[/b] the Torch hunts only you[/color]" if OS.is_debug_build() else "",
		"Hold [b]middle mouse[/b]: cruise + free look. Everything you were holding (movement keys, slide, jump) stays held in that direction while the mouse only turns the camera. Keys pressed meanwhile stack on top. Let go and the camera snaps back to where it was pointing.",
		"",
		"[b][color=#ff9e33]MECHANICS[/color][/b]   (what, how, where to test in the gym)",
		"[b]Run[/b]  %.0f m/s top speed, full speed in about %.2f s." % [c.max_speed, c.max_speed / c.ground_accel],
		"[b]Variable jump[/b]  tap for a short hop, hold for full height. Releasing early cuts upward speed ×%.2f." % c.jump_cut_mult,
		"[b]Coyote time[/b]  you can still jump %.2f s after running off a ledge." % c.coyote_time,
		"[b]Jump buffer[/b]  press jump up to %.2f s before landing, it fires on touchdown." % c.jump_buffer,
		"[b]Bhop[/b]  jump within %.2f s of landing and ground friction never touches your extra speed." % c.landing_grace,
		"[b]Air strafe[/b]  above top speed, steer in the air to bend your momentum without losing it.",
		"[b]Slide[/b]  press Ctrl on the ground. +%.0f m/s boost (once every %.1f s), never under %.0f m/s on flat ground while held, speeds up downhill. → SLIDE HILL, SLIDE TUNNEL" % [c.slide_boost, c.slide_boost_cooldown, c.slide_min_speed],
		"[b]Slide-jump[/b]  jump during a slide, you keep all the slide speed.",
		"[b]Dash[/b]  Shift. Goes where you're pressing (or where you look), %.0f m/s for %.2f s, ignores gravity. %d charges, one back every %.1f s." % [c.dash_speed, c.dash_time, c.dash_charges, c.dash_regen],
		"[b]Dash-jump[/b]  jump during a dash on the ground, keeps %d%% of the dash speed. Already faster? +%d m/s on top." % [int(c.dash_jump_keep * 100.0), int(c.dash_jump_boost)],
		"[b]Wall-jump[/b]  in the air next to any wall (steeper than %.0f°), press jump. %d per airtime, refilled on landing. → WALL-JUMP SHAFT" % [c.floor_max_angle_deg, c.wall_jumps_max],
		"[b]Wall-slide[/b]  falling while holding toward a wall caps your fall at %.0f m/s (camera leans)." % c.wall_slide_speed,
		"[b]Slam[/b]  Ctrl in the air, drops at %.0f m/s." % c.slam_speed,
		"[b]Slam-bounce[/b]  jump within %.2f s of a slam landing: you bounce %.0f m + %d%% of how far you fell (max %.0f m). Bigger drop, bigger launch." % [c.slam_bounce_window, c.slam_bounce_base_height, int(c.slam_bounce_fall_ratio * 100.0), c.slam_bounce_max_height],
		"[b]Slam-slide[/b]  keep Ctrl held through a slam landing and you land straight in a slide.",
		"[b]Brake slam[/b]  Q in the air: drops you at %.0f m/s while your speed eases off (%.0f m/s² decel), with a little steering left to hit a small landing. → PILLARS" % [c.slam_speed, c.brake_air_decel],
		"[b]Skid stop[/b]  Q on the ground stops you hard. Spam it %.0f times quickly and you're dizzy: stunned for %.1f s. From over %.0f m/s it's a crash stop: stunned %.1f s, then you stumble about." % [c.dizzy_threshold, c.dizzy_duration, c.overdrive_speed, c.hard_stop_stun],
		"[b]Wall bonk[/b]  hitting a wall head-on faster than %.0f m/s (dashes count) disorients you for %.1f s or more: the camera sways, your steering drifts and you stumble around on your own, but you can still move. → PILLARS, SHAFT" % [c.wall_bonk_speed, c.bonk_duration],
		"[b]Vault[/b]  jump at a ledge up to %.1f m, keep jump held and push forward, you get popped onto it. → VAULT WALLS" % c.vault_height,
		"[b]Auto-step[/b]  steps up to %.2f m need no jump, even mid-dash. → STAIRS" % c.step_height,
		"[b]Steep ground[/b]  slopes over %.0f° are walls, not floors. → RAMPS" % c.floor_max_angle_deg,
		"[b]Pads & strips[/b]  orange pads launch you, cyan strips push you to their speed. → PADS, LAUNCHER, SPEED STRIP, PAD to hill top",
	]
	return "\n".join(lines)
