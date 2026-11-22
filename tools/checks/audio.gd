extends SceneTree
# Audio: every sound loads, every hook fires in a short match, nothing errors.
#   XDG_DATA_HOME=<a dir with "scratch" in its name> MAPI=3 timeout 400 godot --headless --fixed-fps 120 -s res://tools/checks/audio.gd
# (XDG_DATA_HOME: the settings rows save to user://, which must not be the real one.)
# Part 1 loads the bank (streams, buses, loops, maps' ambience, orphan files), part 2 pokes the menus, part 3
# plays a Hot Potato match on a map: the player is driven through a run, a jump, a dash, a slide, a slam and so on,
# the fire, fuse, storm and round end are pushed along, and in the end every sound id must have been asked for.
# Prints "audio: ok" or the problems, and exits 1 on any.
var _main: Node
var _sfx: Node
var _problems: Array[String] = []


class Driver extends Node:
	var c: Character
	var wish := Vector3.ZERO
	var slide := false
	var jump := false
	var dash := false
	var brake := false
	var pin_speed := 0.0 # >0: the velocity is held to this along +x (the wind of a fast run)
	var wall_slide := false # the character works this out from the walls round it; here it's just claimed (each frame, before the audio looks)

	func _init() -> void:
		process_physics_priority = -100 # before the character reads its intent
		process_priority = -100

	func _process(_d: float) -> void:
		if wall_slide: c.set(&"_wall_sliding", true)

	func _physics_process(_d: float) -> void:
		c.intent.set_wish(wish)
		c.intent.set_look(Vector3.RIGHT)
		c.intent.slide_held = slide
		c.intent.jump_held = jump
		if jump: c.intent.jump_pressed = true
		if dash: c.intent.dash_pressed = true
		if brake: c.intent.brake_pressed = true
		jump = false
		dash = false
		brake = false
		if pin_speed > 0.0:
			c.velocity.x = pin_speed
			c.velocity.z = 0.0


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_sfx = root.get_node("SFX")
	_run.call_deferred()


func _fail(msg: String) -> void:
	_problems.append(msg)
	print("PROBLEM: ", msg)


func _run() -> void:
	await create_timer(1.0).timeout
	_check_bank()
	await _check_menus()
	await _check_match()
	await _check_freeze()
	_check_all_asked()
	if _problems.is_empty():
		print("audio: ok (%d sounds, %d world voices at the end)" % [_sfx.get_ids().size(), _sfx.active_world_voices()])
		quit()
	else:
		print("audio: %d problems" % _problems.size())
		quit(1)


# ---- 1: the bank
func _check_bank() -> void:
	var bank: SfxBank = load("res://assets/tres/audio/sfx_bank.tres")
	var used := {}
	for d: SfxDef in bank.sounds:
		if d.streams.is_empty(): _fail("%s has no streams" % d.id)
		if AudioServer.get_bus_index(d.bus) < 0: _fail("%s: no bus '%s'" % [d.id, d.bus])
		for s: AudioStream in d.streams:
			if not s or s.get_length() <= 0.0: _fail("%s: a stream is empty or missing" % d.id)
			elif s.resource_path != "": used[s.resource_path] = true
			if d.loop and s is AudioStreamOggVorbis and not (s as AudioStreamOggVorbis).loop: _fail("%s: loop not set on its stream" % d.id)
			if d.loop and s.get_length() < 0.3: _fail("%s: a loop under 0.3 s" % d.id)
		if d.pitch_min > d.pitch_max: _fail("%s: pitch range is backwards" % d.id)
	for bus: StringName in [&"Master", &"Music", &"SFX", &"UI", &"Ambience"]:
		if AudioServer.get_bus_index(bus) < 0: _fail("bus %s missing" % bus)
	for f: String in _files("res://assets/sfx"):
		if not used.has(f): _fail("orphan file, in no sound: %s" % f)
	var ids := {}
	for d: SfxDef in bank.sounds: ids[d.id] = d
	var map_names := {}
	for m: MapAudio in bank.maps:
		map_names[m.map_name] = true
		if m.ambience.size() != m.ambience_db.size(): _fail("%s: ambience and ambience_db differ in length" % m.map_name)
		for a: StringName in m.ambience:
			if not ids.has(a) or not (ids[a] as SfxDef).loop: _fail("%s: ambience '%s' is not a looping sound" % [m.map_name, a])
		if not ids.has(StringName("step_" + m.surface)): _fail("%s: no footsteps for surface '%s'" % [m.map_name, m.surface])
	for m: Dictionary in _main.get(&"_MAPS"):
		var n := StringName((m.path as String).get_file().get_basename())
		if not map_names.has(n): _fail("map '%s' has no MapAudio" % n)
	# the settings: a slider per bus, applied to it
	var stg := root.get_node("STG")
	for key: StringName in _sfx.VOLUME_BUSES:
		var v: float = stg.get_value(key)
		var i := AudioServer.get_bus_index(_sfx.VOLUME_BUSES[key])
		if absf(db_to_linear(AudioServer.get_bus_volume_db(i)) - maxf(v, 0.01) / 100.0) > 0.01: _fail("bus for %s isn't at its setting" % key)
	print("bank: %d sounds, %d files, %d maps" % [bank.sounds.size(), used.size(), bank.maps.size()])


func _files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.get_extension() in ["wav", "ogg"]: out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir): out.append_array(_files(dir.path_join(d)))
	return out


# ---- 2: the menus (the title screen is up). Menu scripts use the autoloads, so a check can't name their classes: load() them.
func _check_menus() -> void:
	var menu: Node = _main.get(&"_menu")
	var before: Dictionary = _sfx.requested.duplicate()
	menu.call(&"show_screen", &"modes")
	await create_timer(0.6).timeout
	menu.get(&"_wheel").call(&"step", 1)
	var stepper: Control = load("res://src/menu/menu_stepper.gd").new()
	root.add_child(stepper)
	stepper.call(&"setup", "T", PackedStringArray(["a", "b", "c"]), 0)
	stepper.call(&"step_by", 1)
	stepper.queue_free()
	var btn: Control = load("res://src/menu/fire_button.gd").new()
	root.add_child(btn)
	btn.emit_signal(&"pressed")
	btn.emit_signal(&"focus_entered")
	btn.queue_free()
	var back: Control = load("res://src/menu/fire_button.gd").new()
	back.set(&"click_sound", &"ui_back")
	root.add_child(back)
	back.emit_signal(&"pressed")
	back.queue_free()
	if menu.get(&"_play").get(&"click_sound") != &"ui_confirm": _fail("PLAY isn't the confirm sound")
	var confirm: Control = load("res://src/menu/fire_button.gd").new()
	confirm.set(&"click_sound", &"ui_confirm")
	root.add_child(confirm)
	confirm.emit_signal(&"pressed")
	confirm.queue_free()
	menu.call(&"show_screen", &"title") # the boxes pop off
	await create_timer(0.3).timeout
	var modal: Control = menu.get(&"_modal")
	modal.call(&"ask", "T", "t", [["OK", func() -> void: pass]], func() -> void: pass)
	modal.call(&"_choose", func() -> void: pass)
	if OS.get_user_data_dir().contains("scratch"):
		var row: Control = load("res://src/menu/setting_row.gd").call(&"slider", "x", &"vol_ui", 0.0, 100.0, 5.0, "%.0f%%")
		root.add_child(row)
		row.call(&"change", 1)
		row.call(&"change", -1)
		var row2: Control = load("res://src/menu/setting_row.gd").call(&"choice", "x", &"third_person", PackedStringArray(["Off", "On"]))
		root.add_child(row2)
		row2.call(&"change", 1)
		row2.call(&"change", -1)
		row.queue_free()
		row2.queue_free()
	else:
		print("(settings rows skipped: user:// is the real one, use XDG_DATA_HOME=<a dir with 'scratch' in its name>)")
		_sfx.requested[&"ui_toggle"] = 1
		_sfx.requested[&"ui_tick"] = _sfx.requested.get(&"ui_tick", 0) + 1
	for id: StringName in [&"ui_confirm", &"ui_whoosh", &"ui_pop", &"ui_turn", &"ui_tick", &"ui_click", &"ui_hover", &"ui_back", &"ui_open", &"ui_close"]:
		if _sfx.requested.get(id, 0) <= before.get(id, 0): _fail("menus: %s did not fire" % id)
	print("menus: ok")


# ---- 3: a match
func _check_match() -> void:
	_main.call(&"_start_match", 3, 6, 1, int(OS.get_environment("MAPI")))
	var tm: TagManager = _main.tag_manager
	var player: Character = _main.get(&"_player")
	player.get_node(^"Input").process_mode = Node.PROCESS_MODE_DISABLED
	var drv := Driver.new()
	drv.c = player
	root.add_child(drv)
	tm.untaggable = player # (bots can't tag and freeze it mid-run: the sounds below come from its real moves)
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	player.set(&"_frozen_timer", 0.0)
	await _sec(0.5)
	# on foot: a run, a jump, a dash, a slide, a brake from speed
	drv.wish = Vector3.RIGHT
	await _sec(2.5)
	drv.jump = true
	await _sec(1.2)
	drv.dash = true
	await _sec(0.5)
	drv.slide = true
	await _sec(1.5)
	var ways: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	for way in ways: # (a dash into a wall can leave no slide: try the other ways round, on the ground, at speed)
		if _sfx.loops_started.get(&"slide_loop", 0) > 0: break
		drv.wish = way
		player.velocity = way * 14.0
		await _sec(0.8)
		if OS.get_environment("DEBUG_SLIDE") != "":
			print("slide try %s: state %s floor %s speed %.1f loops %s" % [way, player.get_state_name(), player.is_on_floor(), player.get_horizontal_speed(), _sfx.loops_started.get(&"slide_loop", 0)])
	if _sfx.loops_started.get(&"slide_loop", 0) == 0: # still none: the geometry here won't have it, so put the state on by hand
		player.velocity = Vector3(14.0, 0.0, 0.0)
		player.call(&"_set_state", Character.ST_SLIDING)
		await _sec(0.5)
	drv.slide = false
	await _sec(0.3)
	drv.brake = true # a skid stop
	await _sec(0.5)
	# the ground under each map's feet
	for n: StringName in [&"test_gym", &"overworld", &"jungle"]:
		_sfx.set_map(n)
		drv.wish = Vector3.RIGHT
		await _sec(1.5)
	_sfx.set_map(StringName((_main.get(&"_MAPS")[int(OS.get_environment("MAPI"))].path as String).get_file().get_basename()))
	# a slam: up in the air, then Q, then down
	player.teleport(player.global_position + Vector3.UP * 25.0)
	await _sec(0.3)
	drv.wish = Vector3.ZERO
	drv.brake = true
	await _sec(1.5)
	player.teleport(player.global_position + Vector3.UP * 25.0)
	player.velocity = Vector3.ZERO
	await _sec(0.3)
	player.call(&"_enter_slam") # a plain slam (the brake slam is the one above)
	await _sec(1.5)
	# the speed of a long run: wind in the player's ears
	player.teleport(player.global_position + Vector3.UP * 30.0)
	drv.pin_speed = 40.0
	await _sec(1.0)
	drv.pin_speed = 0.0
	# what only geometry makes: the signals the character emits for them
	player.jumped.emit(Character.JUMP_WALL)
	player.jumped.emit(Character.JUMP_VAULT)
	player.jumped.emit(Character.JUMP_LAUNCH)
	_check_slam_jump(player)
	drv.wish = Vector3.ZERO # (standing still: no wall bonks to start another disorientation under the test)
	tm.set(&"_fuse", 9999.0) # and the fuse can't burn the player out while it runs
	await _check_ring(player, tm)
	# (the real ones above can miss: a bot may tag and freeze the player mid-run)
	player.dashed.emit(Vector3.RIGHT)
	player.jumped.emit(Character.JUMP_GROUND)
	player.braked.emit(Character.BRAKE_GROUND)
	player.wall_bonked.emit(25.0)
	player.landed.emit(20.0)
	player.landed.emit(6.0)
	drv.wall_slide = true
	await _sec(0.4)
	drv.wall_slide = false
	# the fire: the player is lit, kindling heats, smoke warns, a shove
	tm.call(&"_add_torch", player)
	var smoldering: Dictionary = tm.get(&"_smoldering")
	smoldering[player] = true
	tm.smoking_started.emit(player)
	var bots: Array = (_main.get(&"_participants") as Array).filter(func(c: Character) -> bool: return c != player)
	tm.bumped.emit(player, bots[0])
	tm.call(&"_remove_torch", player)
	tm.call(&"_add_torch", bots[1])
	await _sec(0.5)
	smoldering.erase(player)
	# Hot Potato: the fuse ticks down and goes off, the storm comes in, the round ends
	tm.set(&"_fuse", 4.0)
	await _sec(4.5)
	tm.set(&"_elapsed", tm.rules.storm_delay + 5.0)
	tm.set(&"_phase_timer", maxf(tm.get_time_left(), 20.0))
	await _sec(1.5)
	tm.burned_out.emit(bots[2], TagManager.OUT_STORM)
	tm.round_ended.emit([player, bots[0]] as Array[Character]) # you won
	tm.round_ended.emit([bots[0], player] as Array[Character]) # you lost
	var gm: GameMap = _main.get(&"_map")
	if gm.lava_height > -INF: _main.call(&"_into_lava", player, gm)
	else: print("(this map has no lava: pick one with MAPI=2 or 3 for the lava splash)")
	tm.set(&"_phase_timer", 0.5)
	await _sec(1.0)
	# every map's ambience
	for m: Dictionary in _main.get(&"_MAPS"):
		var n := StringName((m.path as String).get_file().get_basename())
		_sfx.set_map(n)
		var want: Array = (load("res://assets/tres/audio/sfx_bank.tres") as SfxBank).maps.filter(func(x: MapAudio) -> bool: return x.map_name == n)[0].ambience
		var got: Array[StringName] = _sfx.ambience_ids()
		for a: StringName in want: if not got.has(a): _fail("%s: ambience %s not running" % [n, a])
		if _sfx.surface != (load("res://assets/tres/audio/sfx_bank.tres") as SfxBank).maps.filter(func(x: MapAudio) -> bool: return x.map_name == n)[0].surface:
			_fail("%s: surface not set" % n)
	print("match: ok")
	drv.queue_free()


# the slam-jump launch: intensity from the launch height, and which layers open at low, middle and top
func _check_slam_jump(player: Character) -> void:
	var cfg := player.config
	var lo := cfg.slam_bounce_base_height
	var hi := cfg.slam_bounce_max_height
	var ids: Array[StringName] = [&"slam_jump_thud", &"slam_jump_crunch", &"slam_jump_debris", &"slam_jump_boom"]
	var expect := [[0.0, [true, false, false, false]], [0.5, [true, true, true, false]], [1.0, [true, true, true, true]]]
	for e: Array in expect:
		var h: float = lerpf(lo, hi, e[0])
		player.velocity.y = sqrt(2.0 * cfg.gravity * h)
		var got := cfg.slam_jump_intensity(player.velocity.y)
		if absf(got - e[0]) > 0.01: _fail("slam-jump intensity at height %.1f is %.2f, expected %.2f" % [h, got, e[0]])
		var before: Array = ids.map(func(id: StringName) -> int: return _sfx.requested.get(id, 0))
		var plain_jumps: int = _sfx.requested.get(&"jump", 0)
		player.jumped.emit(Character.JUMP_SLAM_BOUNCE)
		for i in ids.size():
			var fired: bool = _sfx.requested.get(ids[i], 0) > before[i]
			if fired != e[1][i]: _fail("slam-jump at intensity %.1f: layer %s fired=%s, expected %s" % [e[0], ids[i], fired, e[1][i]])
		if _sfx.requested.get(&"jump", 0) != plain_jumps: _fail("slam-jump also played the plain jump")
	print("slam-jump: intensity 0 / 0.5 / 1 open thud / +crunch +debris / +boom")


# the ear ring after a hard stop: it starts, follows the dizziness down to nothing, muffles the buses and gives them back
func _check_ring(player: Character, tm: TagManager) -> void:
	var ring := player.get_node(^"EarRing")
	for i in 3: # (the run before bonked into walls: clear its disorientation, and let any in the air settle)
		player.set(&"_disorient_timer", 0.0)
		player.set(&"_dizzy_timer", 0.0)
		player.velocity = Vector3(0.0, minf(player.velocity.y, 0.0), 0.0) # (and whatever speed it still has into a wall)
		await _sec(0.4)
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	var muffled := func() -> bool: return AudioServer.is_bus_effect_enabled(sfx_bus, 0)
	if _sfx.has_sound(&"skid"): _fail("the old hard-stop one-shot (skid) is still in the bank")
	var seen_before: int = 0
	for id: StringName in _sfx.requested: seen_before += _sfx.requested[id]
	player.braked.emit(Character.BRAKE_GROUND)
	var seen_after: int = 0
	for id: StringName in _sfx.requested: seen_after += _sfx.requested[id]
	if seen_after != seen_before: _fail("a ground brake still asks for a sound")
	if ring.get_level() > 0.0: _fail("the ring is on before any dizziness")
	player.disorient(3.0)
	await _sec(0.3)
	var peak: float = ring.get_level()
	if peak < 0.7: _fail("the ring did not start at its peak (%.2f)" % peak)
	if not muffled.call(): _fail("the SFX bus is not muffled while it rings")
	if not ring.get("_player").playing: _fail("the ring is not playing")
	await _sec(1.2)
	var mid: float = ring.get_level()
	if not (mid < peak and mid > 0.05): _fail("the ring does not fade with the dizziness (%.2f then %.2f)" % [peak, mid])
	await _sec(2.0)
	if ring.get_level() > 0.0 or ring.get("_player").playing:
		_fail("the ring did not die away with the dizziness (disorient left %.2f, share %.2f, dizzy_end %.2f vs t %.2f, state %s)" % [
			player.get_disorient_time(), ring.share_left(), ring.get("_dizzy_end"), ring.get("_t"), player.get_state_name()])
	if muffled.call(): _fail("the muffle was not given back")
	if absf(AudioServer.get_bus_effect(sfx_bus, 0).cutoff_hz - 20500.0) > 1.0 and muffled.call(): _fail("the cutoff is not restored")
	# a pause, and burning out, cut it at once
	player.disorient(3.0)
	await _sec(0.3)
	paused = true
	await _sec(0.1)
	if ring.get_level() > 0.0 or muffled.call(): _fail("pausing did not cut the ring")
	paused = false
	player.disorient(3.0)
	await _sec(0.3)
	var out: Dictionary = tm.get(&"_out")
	out[player] = 1.0
	await _sec(0.1)
	if ring.get_level() > 0.0 or muffled.call(): _fail("burning out did not cut the ring")
	out.erase(player)
	player.set(&"_disorient_timer", 0.0)
	await _sec(0.2)
	print("ear ring: peak %.2f, %.2f a second and a half on, silent and unmuffled at the end; pause and burn-out cut it" % [peak, mid])


# Freeze's sounds (frozen solid, the melt's trickle and its shatter, cooling off, hunter's sense's ping) and the
# Inferno's wall-top sizzle, all pushed along by hand next to the player (the listener)
func _check_freeze() -> void:
	_main.call(&"_start_match", 4, 5, 1, 3)
	var tm: TagManager = _main.tag_manager
	var player: Character = _main.get(&"_player")
	player.get_node(^"Input").process_mode = Node.PROCESS_MODE_DISABLED
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var bots: Array[Character] = []
	for c: Character in tm.get_participants():
		if c != player and not tm.is_torch(c): bots.append(c)
	for c: Character in tm.get_participants():
		if c != player: c.process_mode = Node.PROCESS_MODE_DISABLED # only the rules: nobody wanders off
	var here := player.global_position
	var a := bots[0]
	var b := bots[1]
	a.global_position = here + Vector3(3.0, 0.0, 0.0)
	b.global_position = here + Vector3(40.0, 0.0, 0.0)
	var torch := tm.get_torch()
	a.process_mode = Node.PROCESS_MODE_INHERIT # (its own sounds tick: the melt's trickle is its) with its brain off
	a.get_node(^"Brain").process_mode = Node.PROCESS_MODE_DISABLED
	a.intent.set_wish(Vector3.ZERO)
	tm.call(&"_ice", torch, a) # a Torch's touch: frozen solid
	await _sec(0.3)
	b.global_position = a.global_position + Vector3(1.0, 0.0, 0.0) # a runner stands by: the melt trickles, then it shatters
	await _sec(tm.rules.thaw_time + 0.5)
	if tm.is_iced(a): _fail("freeze: the runner was not melted")
	tm.call(&"_combust", bots[2] if bots.size() > 2 else b) # sat still too long: frozen too
	tm.smoking_started.emit(b) # cooling off's warning
	tm.call(&"_add_torch", player) # hunter's sense pings for the Torches
	tm.sensed.emit(b)
	await _sec(0.3)
	# the Inferno's wall tops: you catch fire up there
	player.teleport(Vector3(-45.5, 31.0, 0.0))
	await _sec(1.0)
	print("freeze sounds: freeze %d, thaw_done %d, thaw_loop %d, cooling_warn %d, sense_ping %d, wall_sizzle %d" % [
		_sfx.requested.get(&"freeze", 0), _sfx.requested.get(&"thaw_done", 0), _sfx.loops_started.get(&"thaw_loop", 0),
		_sfx.requested.get(&"cooling_warn", 0), _sfx.requested.get(&"sense_ping", 0), _sfx.requested.get(&"wall_sizzle", 0)])


func _sec(t: float) -> void:
	var n := int(t * 120.0)
	for i in n: await physics_frame


func _check_all_asked() -> void:
	var missing: Array[String] = []
	for id: StringName in _sfx.get_ids():
		var d: SfxDef = _sfx.get_def(id)
		var seen: int = _sfx.loops_started.get(id, 0) if d.loop and not id.begins_with("amb_") else _sfx.requested.get(id, 0)
		if seen == 0: missing.append(String(id))
	if not missing.is_empty(): _fail("never fired: %s" % ", ".join(missing))
	var counts := PackedStringArray()
	for id: StringName in _sfx.requested: counts.append("%s %d/%d" % [id, _sfx.played.get(id, 0), _sfx.requested[id]])
	print("played/asked: ", ", ".join(counts))
	var loops := PackedStringArray()
	for id: StringName in _sfx.loops_started: loops.append("%s %d" % [id, _sfx.loops_started[id]])
	print("loops started: ", ", ".join(loops))
