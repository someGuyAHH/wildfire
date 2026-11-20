extends SceneTree
# Per-map setting defaults: the Jungle defaults to leaf shadows Low and fast shadows, the Overworld
# keeps the global defaults; a change made in the Jungle sticks to the Jungle only. Headless; in
# memory only (never saved).
#   timeout 180 godot --headless --fixed-fps 120 -s res://tools/checks/map_settings.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var stg := root.get_node(^"STG")
	await create_timer(0.5).timeout
	var ok := true
	_main.call(&"_start_match", 0, 3, 1, 2) # Jungle
	await create_timer(0.3).timeout
	var j := [stg.call(&"get_value", &"leaf_shadows"), stg.call(&"get_value", &"fast_shadows")]
	print("Jungle defaults: leaf shadows %s, fast shadows %s" % j)
	ok = ok and j[0] == 1.0 and j[1] == 1.0
	stg.call(&"set_value", &"leaf_shadows", 3.0, false) # the player's own choice here
	_main.call(&"_start_match", 0, 3, 1, 1) # Overworld
	await create_timer(0.3).timeout
	var o := [stg.call(&"get_value", &"leaf_shadows"), stg.call(&"get_value", &"fast_shadows")]
	print("Overworld: leaf shadows %s, fast shadows %s (the global ones)" % o)
	ok = ok and o[0] == stg.get(&"_defaults")[&"leaf_shadows"] and o[1] == 0.0
	_main.call(&"_start_match", 0, 3, 1, 2) # back to the Jungle
	await create_timer(0.3).timeout
	var j2: float = stg.call(&"get_value", &"leaf_shadows")
	print("Jungle again: leaf shadows %s (the choice made there)" % j2)
	ok = ok and j2 == 3.0
	(stg.get(&"_map_values") as Dictionary).erase("jungle") # leave no trace
	print("map settings: %s" % ("OK" if ok else "FAILED"))
	quit()
