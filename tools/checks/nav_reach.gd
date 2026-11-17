extends SceneTree
# Is there a nav path from FROM to each of SPOTS ("x,y,z;...")? Paths that end more than 1.5 m
# short of the spot are reported. (Reachable on the navmesh, not proof a bot makes the moves.)
#   SCENE=res://scn/map/inferno.tscn FROM="0,1,-100" SPOTS="..." godot --headless -s res://tools/checks/nav_reach.gd

func _initialize() -> void:
	_run.call_deferred()


func _v(s: String) -> Vector3:
	var f := s.split_floats(",")
	return Vector3(f[0], f[1], f[2])


func _run() -> void:
	var map := (load(OS.get_environment("SCENE")) as PackedScene).instantiate() as GameMap
	root.add_child(map)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var rid := map.get_world_3d().navigation_map
	while not NavigationServer3D.map_get_closest_point_owner(rid, map.arena_center + Vector3.UP * 2.0).is_valid(): await physics_frame
	for i in 5: await physics_frame
	var from := map.nav_snap(_v(OS.get_environment("FROM")))
	var bad := 0
	var spots := OS.get_environment("SPOTS").split(";")
	for s in spots:
		var to := map.nav_snap(_v(s))
		var p := NavigationServer3D.map_get_path(rid, from, to, true)
		var short := p[-1].distance_to(to) if p.size() else INF
		if short > 1.5:
			bad += 1
			print("  no way to %s (snapped %s): path ends %.1f m short" % [s, to.snapped(Vector3.ONE * 0.1), short])
	print("reachable: %d / %d" % [spots.size() - bad, spots.size()])
	quit()
