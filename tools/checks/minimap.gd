extends SceneTree
# The HUD's minimap, headless, on every map: there in the match HUD, the map has its baked
# picture, and drawing it (map, dots, rim) runs without script errors. Run it and read the log.
#   timeout 300 godot --headless --fixed-fps 120 -s res://tools/checks/minimap.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(1.0).timeout
	var ok := true
	for mapi: int in [1, 2, 3]:
		_main.call(&"_start_match", 0, 3, 1, mapi)
		for i: int in 30: await process_frame
		var mini := root.find_children("*", "Minimap", true, false)
		var map: Node = _main.get(&"_map")
		var tex: Texture2D = map.get(&"minimap") if map else null
		var e: float = map.get(&"minimap_half_extent") if map else 0.0
		print("map %d: minimaps on the HUD %d, picture %s, %.0f m each way" % [mapi, mini.size(), "yes" if tex else "NO", e])
		if mini.size() != 1 or not tex or e <= 0.0: ok = false
	print("MINIMAP: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
