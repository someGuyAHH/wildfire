extends SceneTree
# Hot Potato: where the storm starts and where it ends up on a map (centre, radius, wall bottom),
# by fast-forwarding the round clock.
#   MAPI=2 timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/storm_end.gd
func _initialize() -> void:
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _report(label: String, tm: TagManager, map: GameMap) -> void:
	var wall := map.get(&"_storm").get_child(0) as MeshInstance3D
	var half := 30.0 * wall.global_basis.get_scale().y
	print("%s: centre %s, radius %.0f, wall %s from y %.0f to %.0f" % [label, tm.get_storm_center().snapped(Vector3.ONE * 0.1),
		tm.get_storm_radius(), Vector2(wall.global_position.x, wall.global_position.z).snapped(Vector2.ONE * 0.1),
		wall.global_position.y - half, wall.global_position.y + half])


func _run(main: Node) -> void:
	await create_timer(1.0).timeout
	main.call(&"_start_match", 3, 3, 1, int(OS.get_environment("MAPI")))
	var tm := main.get(&"tag_manager") as TagManager
	var map := main.get(&"_map") as GameMap
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	await physics_frame
	_report("start", tm, map)
	tm.set(&"_elapsed", tm.rules.storm_delay + tm.rules.storm_shrink_time * 0.5)
	await physics_frame
	_report("halfway", tm, map)
	tm.set(&"_elapsed", tm.rules.storm_delay + tm.rules.storm_shrink_time + 1.0)
	await physics_frame
	_report("end", tm, map)
	quit()
