extends Node

# the one persistent root scene: loads a map, spawns the player + bots, runs the tag match.
# grows into the real scene manager (menus, match setup) later.

const _IPINPUT := preload("res://src/player/player_input.gd")
const _IBRAIN  := preload("res://src/bot/bot_brain.gd")
const _IMHUD   := preload("res://src/hud/match_hud.gd")
const _IPHUD   := preload("res://src/hud/player_hud.gd")
const _IPAUSE  := preload("res://src/menu/pause_menu.gd")

const PLAYER_SCENE    := preload("res://scn/player/player.tscn")
const BOT_SCENE       := preload("res://scn/bot/bot.tscn")

# bot difficulty
const BOTS_EASY   := 0
const BOTS_NORMAL := 1
const BOTS_HARD   := 2
const BOTS_MIXED  := 3
const _SKILLS: Array[BotSkill] = [
	preload("res://assets/tres/bot/easy.tres"),
	preload("res://assets/tres/bot/normal.tres"),
	preload("res://assets/tres/bot/hard.tres"),
]
const MATCH_HUD_SCENE := preload("res://scn/hud/match_hud.tscn")
const PAUSE_SCENE     := preload("res://scn/menu/pause_menu.tscn")

const _PLAYER_TINT := Color(0.42, 0.7, 1.0)
const _BOT_TINTS: Array[Color] = [
	Color(0.95, 0.85, 0.3), Color(0.45, 0.9, 0.5), Color(0.75, 0.5, 0.95), Color(0.95, 0.6, 0.85),
	Color(0.4, 0.9, 0.9), Color(0.95, 0.65, 0.35), Color(0.7, 0.75, 0.8), Color(0.6, 0.95, 0.25),
]

@export_file("*.tscn") var start_map: String = "res://scn/map/test_gym.tscn"
@export var tag_manager: TagManager
@export var bot_count: int = 7
## 0 easy, 1 normal, 2 hard, 3 mixed (cycles easy/normal/hard).
@export_range(0, 3) var bot_difficulty: int = BOTS_MIXED
## Extra spawn points are laid out on a ring this wide around the map's spawn marker.
@export var spawn_ring_radius: float = 7.0
## Falling below this respawns you.
@export var kill_height: float = -60.0

var _map: Node3D
var _player: Character
var _participants: Array[Character] = []
var _spawn := Transform3D.IDENTITY
var _hud: _IMHUD
var _hunt_player := false


func _ready() -> void:
	if not tag_manager:
		push_error("Main needs a TagManager assigned")
		return
	if not load_map(start_map): return
	_spawn_player()
	for i: int in bot_count: _spawn_bot(i)
	var hud := MATCH_HUD_SCENE.instantiate() as _IMHUD
	add_child(hud)
	hud.setup(tag_manager, _player)
	_hud = hud
	var pause := PAUSE_SCENE.instantiate() as _IPAUSE
	add_child(pause)
	var phud := _player.get_node_or_null(^"Hud") as _IPHUD
	pause.setup(tag_manager, phud.tuning_panel if phud else null, phud.help_overlay if phud else null)
	if not tag_manager.set_participants(_participants, _spawn_points()): return
	tag_manager.start_round()


func _physics_process(_delta: float) -> void:
	for c: Character in _participants:
		if c.global_position.y < kill_height: tag_manager.respawn(c)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_hunt_me"):
		set_hunt_player(not _hunt_player)
		return
	if not event.is_action_pressed(&"toggle_fullscreen"): return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full
								else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Swaps the current map for the one at `path`. Returns true on success, false on fail.
func load_map(path: String) -> bool:
	var packed: PackedScene = load(path)
	if not packed:
		push_error("Couldn't load map '%s'" % path)
		return false
	var map := packed.instantiate() as Node3D
	if not map:
		push_error("Map '%s' root has to be a Node3D" % path)
		return false
	if _map: _map.queue_free()
	_map = map
	add_child(_map)
	var spawn := get_tree().get_first_node_in_group(&"spawn") as Node3D
	_spawn = spawn.global_transform if spawn else Transform3D.IDENTITY
	STG.apply_graphics() # new map, new WorldEnvironment
	if not spawn: push_error("Map '%s' has no node in group 'spawn', using origin" % path)
	return true


## Debug: every bot, whenever it's the It, chases only the player. Toggled with F6.
func set_hunt_player(on: bool) -> void:
	_hunt_player = on
	for c: Character in _participants:
		var brain := c.get_node_or_null(^"Brain") as _IBRAIN
		if brain: brain.force_target = _player if on else null
	if _hud: _hud.notify("debug: It locked onto you" if on else "debug: It picks targets normally", Color(1, 0.62, 0.2))


## Puts the player back on a spawn point.
func respawn_player() -> void:
	if _player: tag_manager.respawn(_player)


func on_player_respawn_requested() -> void:
	respawn_player()


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Character
	_player.position = _spawn.origin
	_player.display_name = "You"
	_player.base_tint = _PLAYER_TINT
	add_child(_player)
	_participants.append(_player)
	var input := _player.get_node(^"Input") as _IPINPUT
	if input: input.respawn_requested.connect(on_player_respawn_requested)


func _spawn_bot(i: int) -> void:
	var bot := BOT_SCENE.instantiate() as Character
	bot.display_name = "Bot %d" % (i + 1)
	bot.base_tint = _BOT_TINTS[i % _BOT_TINTS.size()]
	bot.position = _spawn.origin + Vector3(i * 2.0, 0.0, 3.0)
	var brain := bot.get_node(^"Brain") as _IBRAIN
	if brain:
		brain.tag_manager = tag_manager
		brain.map = _map as GameMap
		brain.skill = _SKILLS[i % _SKILLS.size()] if bot_difficulty == BOTS_MIXED else _SKILLS[bot_difficulty]
	add_child(bot)
	_participants.append(bot)


## Every "spawn" marker on the map, topped up with a ring around the main one.
func _spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n: Node in get_tree().get_nodes_in_group(&"spawn"):
		if n is Node3D: out.append((n as Node3D).global_position)
	var missing := _participants.size() - out.size()
	for i: int in missing:
		var a := TAU * i / float(missing)
		out.append(_spawn.origin + Vector3(cos(a), 0.0, sin(a)) * spawn_ring_radius)
	return out
