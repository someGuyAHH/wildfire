extends SceneTree
# The Leaf shadows setting moves the Jungle's tree-shadow hand-over and switches each side off.
# Headless; changes the setting in memory only (never saved).
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/leaf_shadows.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stg := root.get_node(^"STG")
	var saved: float = stg.call(&"get_value", &"leaf_shadows")
	root.add_child((load("res://scn/map/jungle.tscn") as PackedScene).instantiate())
	var near := get_nodes_in_group(&"shadow_near")
	var far := get_nodes_in_group(&"shadow_far")
	var ok := not near.is_empty() and not far.is_empty()
	print("near twins %d, far stand-ins %d" % [near.size(), far.size()])
	# level: [near visible, near end, far visible, far begin]
	var want := {0: [false, 0.0, false, 0.0], 1: [false, 0.0, true, 0.0], 2: [true, 45.0, true, 45.0], 3: [true, 90.0, true, 90.0]}
	for level: int in want:
		stg.call(&"set_value", &"leaf_shadows", float(level), false)
		var w: Array = want[level]
		for n: Node in near:
			var g := n as GeometryInstance3D
			if g.visible != w[0] or not is_equal_approx(g.visibility_range_end, w[1]): ok = false
		for n: Node in far:
			var g := n as GeometryInstance3D
			if g.visible != w[2] or not is_equal_approx(g.visibility_range_begin, w[3]): ok = false
		print("level %d: %s" % [level, "ok" if ok else "WRONG"])
	stg.call(&"set_value", &"leaf_shadows", saved, false)
	print("LEAF SHADOWS: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
