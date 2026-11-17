extends SceneTree
# How long until a map's navigation answers after it's added (the first build runs async).
#   SCENE=res://scn/map/jungle.tscn godot --headless --fixed-fps 120 -s res://tools/checks/nav_time.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := OS.get_environment("SCENE")
	var map := (load(path) as PackedScene).instantiate() as GameMap
	root.add_child(map)
	var t0 := Time.get_ticks_msec()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var rid := map.get_world_3d().navigation_map
	var probe := map.arena_center + Vector3.UP * 5.0
	for i in 40000:
		await physics_frame
		if NavigationServer3D.map_get_closest_point_owner(rid, probe).is_valid():
			print("%s: nav answers after %d ms" % [path.get_file(), Time.get_ticks_msec() - t0])
			quit()
			return
	print("%s: never answered (%d ms)" % [path.get_file(), Time.get_ticks_msec() - t0])
	quit()
