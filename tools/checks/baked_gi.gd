extends SceneTree
# Lighting: High shows a map's baked bounce light (its VoxelGI, with baked data) and SDFGI stays
# off; Low hides it. Headless; the setting changes in memory only (never saved).
#   MAPI=3 timeout 120 godot --headless -s res://tools/checks/baked_gi.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var stg := root.get_node(^"STG")
	var saved: float = stg.call(&"get_value", &"lighting")
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, int(OS.get_environment("MAPI")) if OS.get_environment("MAPI") != "" else 3)
	await create_timer(0.3).timeout
	var map := _main.get(&"_map") as Node3D
	var gis := map.find_children("*", "VoxelGI", true, false)
	var env := (map.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	var ok := not gis.is_empty()
	for high: bool in [true, false]:
		stg.call(&"set_value", &"lighting", 1.0 if high else 0.0, false)
		for n: Node in gis:
			var gi := n as VoxelGI
			var cells: Vector3 = gi.data.get_octree_size() if gi.data else Vector3.ZERO
			# (a near_only box is hidden with the camera away from it, even on High)
			var good: bool = bool(gi.get(&"enabled")) == high and (gi.visible == high or bool(gi.get(&"near_only"))) and cells.x > 0 and not env.sdfgi_enabled
			ok = ok and good
			print("lighting %s: %s visible %s, baked cells %s, sdfgi %s  %s" % ["High" if high else "Low", gi.name, gi.visible, cells, env.sdfgi_enabled, "ok" if good else "WRONG"])
	stg.call(&"set_value", &"lighting", saved, false)
	print("baked gi: %s" % ("OK" if ok else ("FAILED" if not gis.is_empty() else "FAILED (no VoxelGI in the map)")))
	quit()
