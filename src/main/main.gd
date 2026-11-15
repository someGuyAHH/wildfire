extends Node

# the one persistent root scene: loads a map, spawns the player, handles respawns.
# grows into the real scene manager (menus, match setup) later.

const _IPINPUT := preload("res://src/player/player_input.gd")

const PLAYER_SCENE := preload("res://scn/player/player.tscn")

@export_file("*.tscn") var start_map: String = "res://scn/map/test_gym.tscn"
## Falling below this respawns the player.
@export var kill_height: float = -60.0

var _map: Node3D
var _player: Character
var _spawn := Transform3D.IDENTITY


func _ready() -> void:
	if not load_map(start_map): return
	_spawn_player()


func _physics_process(_delta: float) -> void:
	if _player and _player.global_position.y < kill_height: respawn_player()


func _unhandled_input(event: InputEvent) -> void:
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


## Puts the player back on the map's spawn point.
func respawn_player() -> void:
	if not _player: return
	_player.teleport(_spawn.origin)


func on_player_respawn_requested() -> void:
	respawn_player()


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Character
	_player.position = _spawn.origin
	add_child(_player)
	var input := _player.get_node(^"Input") as _IPINPUT
	if input: input.respawn_requested.connect(on_player_respawn_requested)
