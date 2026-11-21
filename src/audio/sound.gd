class_name Sound
extends RefCounted
## A way to ask for a sound that works wherever the code is loaded: it finds the SFX autoload when called
## and does nothing without it. Menu code and Main use this rather than naming SFX, because a headless
## check (-s) compiles whatever scripts it names before the autoloads exist, and "SFX" would not resolve.
## (The runtime audio nodes, loaded only by Main while the game runs, use SFX directly.)


static func _sfx() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"SFX") if tree else null


## A menu sound (SFX.ui).
static func ui(id: StringName, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _sfx()
	if s: s.call(&"ui", id, vol_db, pitch)


## A flat sound (SFX.play).
static func play(id: StringName, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _sfx()
	if s: s.call(&"play", id, vol_db, pitch)


## A sound in the world (SFX.play_at).
static func at(id: StringName, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _sfx()
	if s: s.call(&"play_at", id, pos, vol_db, pitch)


## The map's ambience and ground sound (SFX.set_map).
static func set_map(map_name: StringName) -> void:
	var s := _sfx()
	if s: s.call(&"set_map", map_name)


## The ambience quieter (menus: negative) or back to normal (0).
static func duck_ambience(db: float) -> void:
	var s := _sfx()
	if s: s.call(&"duck_ambience", db)
