extends Node

# the one persistent root scene, and the scene manager:
#   title  - attract mode: a live bot match on the map behind the main menu, cinematic orbit cam
#   match  - the player + bots in the chosen mode, match HUD, pause menu
# switching between them burns the screen away and back in.

const _IPINPUT := preload("res://src/player/player_input.gd")
const _IPCAM   := preload("res://src/player/player_camera.gd")
const _BOT_DEBUG := preload("res://src/debug/bot_debug.gd")
const _IBRAIN  := preload("res://src/bot/bot_brain.gd")
const _IMHUD   := preload("res://src/hud/match_hud.gd")
const _IPHUD   := preload("res://src/hud/player_hud.gd")
const _IPAUSE  := preload("res://src/menu/pause_menu.gd")
const _IMENU   := preload("res://src/menu/main_menu.gd")

const PLAYER_SCENE    := preload("res://scn/player/player.tscn")
const BOT_SCENE       := preload("res://scn/bot/bot.tscn")
const MATCH_HUD_SCENE := preload("res://scn/hud/match_hud.tscn")
const PAUSE_SCENE     := preload("res://scn/menu/pause_menu.tscn")
const MENU_SCENE      := preload("res://scn/menu/main_menu.tscn")
const _BURN_SCENE     := preload("res://scn/vfx/burn_transition.tscn")
const _FADE_SCENE     := preload("res://scn/vfx/background_fade.tscn") # under the menu: only the 3D view cross-fades

# bot difficulty: 0 easy, 1 normal, 2 hard (the _SKILLS order), or mixed
const BOTS_MIXED := 3
const _MODES: Array[MatchRules] = [
	preload("res://assets/tres/match/classic_rules.tres"),
	preload("res://assets/tres/match/spread_rules.tres"),
	preload("res://assets/tres/match/hunted_rules.tres"),
	preload("res://assets/tres/match/hot_potato_rules.tres"),
]
## Playable maps, in menu order.
const _MAPS: Array[Dictionary] = [
	{"name": "Gym", "path": "res://scn/map/test_gym.tscn"},
	{"name": "Overworld", "path": "res://scn/map/overworld.tscn"},
	{"name": "Jungle", "path": "res://scn/map/jungle.tscn"},
]
const _SKILLS: Array[BotSkill] = [
	preload("res://assets/tres/bot/easy.tres"),
	preload("res://assets/tres/bot/normal.tres"),
	preload("res://assets/tres/bot/hard.tres"),
]

const _PLAYER_TINT := Color(0.42, 0.7, 1.0)
const _BOT_TINTS: Array[Color] = [
	Color(0.95, 0.85, 0.3), Color(0.45, 0.9, 0.5), Color(0.75, 0.5, 0.95), Color(0.95, 0.6, 0.85),
	Color(0.4, 0.9, 0.9), Color(0.95, 0.65, 0.35), Color(0.7, 0.75, 0.8), Color(0.6, 0.95, 0.25),
]
# title screen
const _ATTRACT_BOTS  := 8
const _ORBIT_RADIUS  := 95.0
const _ORBIT_HEIGHT  := 34.0
const _ORBIT_SPEED   := 0.035
const _ORBIT_FOLLOW  := 1.2   # how quickly the camera's aim drifts toward the action
const _BURN_IN       := 0.45
const _BURN_OUT      := 0.6
const _CROSSFADE     := 0.7 # menu MAP switch: old map dissolves into the new one

@export_file("*.tscn") var start_map: String = "res://scn/map/test_gym.tscn"
@export var tag_manager: TagManager
@export var bot_count: int = 7
## Mixed cycles easy/normal/hard.
@export_enum("Easy", "Normal", "Hard", "Mixed") var bot_difficulty: int = BOTS_MIXED
## Extra spawn points are laid out on a ring this wide around the map's spawn marker.
@export var spawn_ring_radius: float = 7.0
## Falling below this respawns you.
@export var kill_height: float = -60.0
## Skip the title screen and drop straight into a match (tests, quick iteration).
@export var skip_title: bool = false

var _map: Node3D
var _bot_debug: Node3D # [DEBUG] F5 overlay, made on first use in a match
var _map_cache: Dictionary[String, Node3D] = {} # visited maps stay loaded, parked (GameMap.set_active)
var _player: Character
var _participants: Array[Character] = []
var _spawn := Transform3D.IDENTITY
var _hud: _IMHUD
var _pause: _IPAUSE
var _menu: _IMENU
var _menu_cam: Camera3D
var _burn: ColorRect
var _burn_mat: ShaderMaterial
var _snapshot: TextureRect
var _hunt_player := false
var _mode_index := 0
var _map_index := -1
var _wanted_map := -1 # the menu's MAP choice the background should show
var _game_time := 0.0
var _in_match := false
var _switching := false
var _orbit := 0.0
var _look := Vector3.ZERO


func _ready() -> void:
	if not tag_manager:
		push_error("Main needs a TagManager assigned")
		return
	if not _use_map(start_map): return
	_build_burn()
	_menu_cam = Camera3D.new()
	_menu_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # moved per frame
	_menu_cam.fov = 70.0
	_menu_cam.far = 3000.0
	add_child(_menu_cam)
	_menu = MENU_SCENE.instantiate() as _IMENU
	add_child(_menu)
	var names := PackedStringArray()
	for m: Dictionary in _MAPS: names.append(m.name)
	_menu.setup(_MODES, bot_count, bot_difficulty, names, maxi(_map_index, 0))
	_menu.start_requested.connect(on_start_requested)
	_menu.map_changed.connect(on_menu_map_changed)
	tag_manager.burned_out.connect(on_burned_out)
	tag_manager.phase_changed.connect(on_phase_changed)
	_mode_index = maxi(_MODES.find(tag_manager.rules), 0)
	if skip_title: _start_match(_mode_index, bot_count, bot_difficulty, maxi(_map_index, 0))
	else: _enter_title()


# drives the game_time shader global (flames, speed lines, vignettes, chevrons). Main pauses with
# the game, so effects freeze on Esc instead of running off TIME (which never stops)
func _process(delta: float) -> void:
	_game_time += delta
	RenderingServer.global_shader_parameter_set(&"game_time", _game_time)
	if not _in_match: _orbit_camera(delta)


func _physics_process(_delta: float) -> void:
	for c: Character in _participants:
		if c.global_position.y < kill_height: tag_manager.respawn(c)


func _unhandled_input(event: InputEvent) -> void:
	if _in_match and _player and tag_manager.is_out(_player) and event.is_action_pressed(&"jump"):
		_spectate_next()
		return
	if _in_match and OS.is_debug_build() and event.is_action_pressed(&"debug_bots"): # [DEBUG]
		toggle_bot_debug()
		return
	if _in_match and OS.is_debug_build() and event.is_action_pressed(&"debug_hunt_me"): # [DEBUG]
		set_hunt_player(not _hunt_player)
		return
	if not event.is_action_pressed(&"toggle_fullscreen"): return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full
								else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Loads a map and points everything at it (tag manager, dry edge, menu's map choice).
## Returns true on success, false on fail.
func _use_map(path: String) -> bool:
	if not load_map(path): return false
	_map_index = -1
	for i: int in _MAPS.size(): if _MAPS[i].path == path: _map_index = i
	var game_map := _map as GameMap
	tag_manager.map = game_map
	if game_map: game_map.mark_dry_edge(game_map.arena_radius * tag_manager.rules.edge_start)
	return true


## Swaps the current map for the one at `path`. Returns true on success, false on fail.
## A map seen before comes back from the cache (parked, so instant); a new one is loaded and kept.
func load_map(path: String) -> bool:
	var map: Node3D = _map_cache.get(path)
	if not map:
		var packed: PackedScene = load(path)
		if not packed:
			push_error("Couldn't load map '%s'" % path)
			return false
		map = packed.instantiate() as Node3D
		if not map:
			push_error("Map '%s' root has to be a Node3D" % path)
			return false
		add_child(map)
		_map_cache[path] = map
	if _map and _map != map:
		if _map is GameMap: (_map as GameMap).set_active(false)
		else:
			remove_child(_map)
			_map.queue_free()
	_map = map
	if _map is GameMap: (_map as GameMap).set_active(true)
	var spawns := _map_spawns()
	var spawn: Node3D = spawns[0] if not spawns.is_empty() else null
	_spawn = spawn.global_transform if spawn else Transform3D.IDENTITY
	STG.apply_graphics() # new map, new WorldEnvironment
	if not spawn: push_error("Map '%s' has no node in group 'spawn', using origin" % path)
	return true


## Menu PLAY -> burn the screen away, set the match up, burn back in.
func on_start_requested(mode_index: int, bots: int, difficulty: int, map_index: int) -> void:
	if _switching: return
	_switching = true
	await _burn_to(1.0, _BURN_IN)
	_start_match(mode_index, bots, difficulty, map_index)
	await _burn_to(0.0, _BURN_OUT)
	_switching = false


## Menu MAP choice changed: freeze a picture of the background (rendered without the menu), lay it
## under the menu, switch the attract match to that map behind it, then fade the picture out so the
## old map dissolves into the new one. A pick made meanwhile chains on once this one's done.
func on_menu_map_changed(map_index: int) -> void:
	_wanted_map = clampi(map_index, 0, _MAPS.size() - 1)
	if _switching or _in_match or _wanted_map == _map_index: return
	_switching = true
	var picture := await _background_picture()
	if picture:
		_snapshot.texture = picture
		_snapshot.modulate.a = 1.0
		_snapshot.visible = true
	_clear_match()
	_use_map(_MAPS[_wanted_map].path)
	_start_attract()
	if picture:
		for i: int in 2: await get_tree().process_frame # the new map's first frames are up underneath
		var tw := _snapshot.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_snapshot, ^"modulate:a", 0.0, _CROSSFADE)
		await tw.finished
		_snapshot.visible = false
		_snapshot.texture = null
	_switching = false
	if _wanted_map != _map_index and not _in_match: on_menu_map_changed.call_deferred(_wanted_map)


# one frame of the 3D view through the menu camera, without any UI: a throwaway SubViewport on the
# same world renders it once. null where nothing renders (headless)
func _background_picture() -> Texture2D:
	if DisplayServer.get_name() == "headless": return null # nothing renders, and frame_post_draw never comes
	var vp := SubViewport.new()
	var root_vp := get_viewport()
	vp.size = root_vp.get_visible_rect().size
	vp.scaling_3d_mode = root_vp.scaling_3d_mode
	vp.scaling_3d_scale = root_vp.scaling_3d_scale
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.fov = _menu_cam.fov
	cam.far = _menu_cam.far
	vp.add_child(cam)
	add_child(vp)
	cam.global_transform = _menu_cam.global_transform
	cam.make_current()
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if not img or img.is_empty(): return null
	return ImageTexture.create_from_image(img)


## Pause menu "Back to title": same burn, back to the attract mode.
func return_to_title() -> void:
	if _switching: return
	_switching = true
	get_tree().paused = false
	await _burn_to(1.0, _BURN_IN)
	_enter_title()
	await _burn_to(0.0, _BURN_OUT)
	_switching = false


## Every bot, whenever it's on fire, chases only the player. F6 toggles it (debug); Hunted
## mode turns it on for the whole round. announce=false skips the feed line.
func set_hunt_player(on: bool, announce: bool = true) -> void:
	_hunt_player = on
	for c: Character in _participants:
		var brain := c.get_node_or_null(^"Brain") as _IBRAIN
		if brain: brain.force_target = _player if on else null
	if _hud and announce:
		_hud.notify("debug: the Torch is locked onto you" if on else "debug: the Torch picks targets normally", Color(1, 0.62, 0.2))


## Puts the player back on a spawn point.
func respawn_player() -> void:
	if _player: tag_manager.respawn(_player)


func on_player_respawn_requested() -> void:
	respawn_player()


#region scenes

# title: bots only, classic, orbiting camera, menu up, mouse free
func _enter_title() -> void:
	_clear_match()
	_start_attract()
	_menu.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# the live bot match behind the menu, on whatever map is loaded
func _start_attract() -> void:
	tag_manager.rules = _MODES[0]
	tag_manager.focus = null
	for i: int in _ATTRACT_BOTS: _spawn_bot(i, BOTS_MIXED, false)
	get_tree().call_group(GameMap.MAP_LABELS, &"set_visible", false) # nothing 3D reads through the menu
	if tag_manager.set_participants(_participants, _spawn_points()): tag_manager.start_round()
	_menu_cam.current = true
	_in_match = false


func _start_match(mode_index: int, bots: int, difficulty: int, map_index: int) -> void:
	_clear_match()
	_menu.close()
	map_index = clampi(map_index, 0, _MAPS.size() - 1)
	if map_index != _map_index: _use_map(_MAPS[map_index].path)
	_mode_index = clampi(mode_index, 0, _MODES.size() - 1)
	bot_count = bots
	bot_difficulty = difficulty
	var rules := _MODES[_mode_index]
	tag_manager.rules = rules
	_spawn_player()
	for i: int in bot_count: _spawn_bot(i, bot_difficulty)
	get_tree().call_group(GameMap.MAP_LABELS, &"set_visible", true)
	_hud = MATCH_HUD_SCENE.instantiate() as _IMHUD
	add_child(_hud)
	_hud.setup(tag_manager, _player)
	_pause = PAUSE_SCENE.instantiate() as _IPAUSE
	add_child(_pause)
	var phud := _player.get_node_or_null(^"Hud") as _IPHUD
	_pause.setup(tag_manager, phud.tuning_panel if phud else null, phud.help_overlay if phud else null,
				return_to_title)
	tag_manager.focus = _player
	set_hunt_player(rules.mode == MatchRules.MODE_HUNTED, false)
	if tag_manager.set_participants(_participants, _spawn_points()): tag_manager.start_round()
	_menu_cam.current = false
	(_player.get_node(^"CameraRig/Camera") as Camera3D).make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_in_match = true


## [DEBUG] F5: every bot's state and path drawn over the world.
func toggle_bot_debug() -> void:
	if not _bot_debug:
		_bot_debug = _BOT_DEBUG.new()
		_bot_debug.set(&"participants", _participants)
		_bot_debug.set(&"tag_manager", tag_manager)
		_bot_debug.visible = false
		add_child(_bot_debug)
	_bot_debug.visible = not _bot_debug.visible


## Burned out (you, or whoever you were watching): watch the next survivor.
func on_burned_out(c: Character, _reason: int) -> void:
	if _player and (c == _player or c == _player_rig().spectating): _spectate_next()


## A new round brings you back: your own view again.
func on_phase_changed(_phase: int) -> void:
	if _player and not tag_manager.is_out(_player): _player_rig().spectate(null)


func _player_rig() -> _IPCAM:
	return _player.get_node(^"CameraRig") as _IPCAM


## Cycles the spectator view through whoever is still standing.
func _spectate_next() -> void:
	var rig := _player_rig()
	var alive: Array[Character] = []
	for c: Character in _participants:
		if not tag_manager.is_out(c): alive.append(c)
	if alive.is_empty(): return
	rig.spectate(alive[(alive.find(rig.spectating) + 1) % alive.size()])


## Frees everyone and the match UI. The TagManager is re-fed right after, same frame.
func _clear_match() -> void:
	for c: Character in _participants: c.queue_free()
	_participants.clear()
	_player = null
	if _bot_debug: _bot_debug.queue_free()
	_bot_debug = null
	if _hud: _hud.queue_free()
	if _pause: _pause.queue_free()
	_hud = null
	_pause = null
	_hunt_player = false


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Character
	_player.position = _spawn.origin
	_player.display_name = "You"
	_player.base_tint = _PLAYER_TINT
	add_child(_player)
	_participants.append(_player)
	var input := _player.get_node(^"Input") as _IPINPUT
	if input: input.respawn_requested.connect(on_player_respawn_requested)


func _spawn_bot(i: int, difficulty: int, labels: bool = true) -> void:
	var bot := BOT_SCENE.instantiate() as Character
	bot.show_labels = labels
	bot.display_name = "Bot %d" % (i + 1)
	bot.base_tint = _BOT_TINTS[i % _BOT_TINTS.size()]
	bot.position = _spawn.origin + Vector3(i * 2.0, 0.0, 3.0)
	var brain := bot.get_node(^"Brain") as _IBRAIN
	if brain:
		brain.tag_manager = tag_manager
		brain.map = _map as GameMap
		brain.skill = _SKILLS[i % _SKILLS.size()] if difficulty == BOTS_MIXED else _SKILLS[clampi(difficulty, 0, 2)]
	add_child(bot)
	_participants.append(bot)


## The current map's spawn markers (parked maps have theirs in the group too).
func _map_spawns() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n: Node in get_tree().get_nodes_in_group(&"spawn"):
		if n is Node3D and _map.is_ancestor_of(n): out.append(n as Node3D)
	return out


## Every "spawn" marker on the map, topped up with a ring around the main one.
func _spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n: Node3D in _map_spawns(): out.append(n.global_position)
	var missing := _participants.size() - out.size()
	for i: int in missing:
		var a := TAU * i / float(missing)
		out.append(_spawn.origin + Vector3(cos(a), 0.0, sin(a)) * spawn_ring_radius)
	return out

#endregion


#region title camera + transition

# slow orbit around the arena, aim drifting toward wherever the fire is
func _orbit_camera(delta: float) -> void:
	_orbit += delta * _ORBIT_SPEED
	var center := (_map as GameMap).arena_center if _map is GameMap else Vector3.ZERO
	var torch := tag_manager.get_torch()
	var want := torch.global_position if torch else center
	_look = _look.lerp(want, 1.0 - exp(-_ORBIT_FOLLOW * delta))
	_menu_cam.global_position = center + Vector3(cos(_orbit), 0.0, sin(_orbit)) * _ORBIT_RADIUS + Vector3.UP * _ORBIT_HEIGHT
	_menu_cam.look_at(_look + Vector3.UP * 2.0)


func _build_burn() -> void:
	var layer := _BURN_SCENE.instantiate()
	add_child(layer)
	_burn = layer.get_node(^"Burn") as ColorRect
	_burn_mat = _burn.material as ShaderMaterial
	var fade_layer := _FADE_SCENE.instantiate()
	add_child(fade_layer)
	_snapshot = fade_layer.get_node(^"Snapshot") as TextureRect


# coroutine: burn the screen to black (1.0) or back in (0.0)
func _burn_to(target: float, time: float) -> void:
	_burn.visible = true
	var from: float = _burn_mat.get_shader_parameter(&"progress") if _burn_mat.get_shader_parameter(&"progress") != null else 0.0
	# tween a method, not the property path: shader params aren't always real properties
	var tw := _burn.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_method(_set_burn, from, target, time)
	await tw.finished
	_burn.visible = target > 0.0


func _set_burn(v: float) -> void:
	_burn_mat.set_shader_parameter(&"progress", v)

#endregion
