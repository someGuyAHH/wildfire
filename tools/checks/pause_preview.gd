extends SceneTree
# Pause menu, headless: the FOV setting reaches the camera at once while the game's paused, and
# PREVIEW hides every UI layer until a key brings them back. Settings change in memory only.
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/pause_preview.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _visible_layers() -> int:
	var n := 0
	for c: Node in root.find_children("*", "CanvasLayer", true, false): if (c as CanvasLayer).visible: n += 1
	return n


func _run() -> void:
	var stg := root.get_node(^"STG")
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 3, 1, 3)
	for i: int in 10: await process_frame
	var pause: Node = _main.get(&"_pause")
	var rig: Node = _main.call(&"_player_rig")
	var cam := rig.get(&"camera") as Camera3D
	var ok := pause != null and cam != null
	var saved_fov: float = stg.call(&"get_value", &"fov")
	pause.call(&"set_paused", true)
	await process_frame
	stg.call(&"set_value", &"fov", 75.0, false)
	await process_frame
	var fov := cam.fov
	print("paused, FOV set to 75: camera at %.1f" % fov)
	if not is_equal_approx(fov, 75.0): ok = false
	pause.call(&"show_settings", true)
	await process_frame
	var before := _visible_layers()
	pause.call(&"preview", true)
	await process_frame
	var during := _visible_layers()
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	for i: int in 3: await process_frame
	var after := _visible_layers()
	print("UI layers shown: %d before PREVIEW, %d during, %d after a key; still paused: %s" % [before, during, after, paused])
	if during != 0 or after != before or not paused: ok = false
	stg.call(&"set_value", &"fov", saved_fov, false)
	print("PAUSE PREVIEW: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
