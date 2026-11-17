extends SceneTree
# A Torch bot chases the frozen player onto each spot in SPOTS ("x,y,z;x,y,z;..."), starting
# from START: does it get there (and how long)?
#   MAPI=3 START="0,1,140" SPOTS="..." godot --headless --fixed-fps 120 -s res://tools/checks/reach.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _v(s: String) -> Vector3:
	var f := s.split_floats(",")
	return Vector3(f[0], f[1], f[2])


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 1, 2, int(OS.get_environment("MAPI")))
	var map := _main.get(&"_map") as GameMap
	var rid := map.get_world_3d().navigation_map
	while not NavigationServer3D.map_get_closest_point_owner(rid, map.arena_center + Vector3.UP * 2.0).is_valid(): await physics_frame
	var tm: TagManager = _main.tag_manager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var player: Character = _main.get(&"_player")
	var bot: Character
	for c: Character in _main.get(&"_participants"): if c != player: bot = c
	var start := map.nav_snap(_v(OS.get_environment("START")))
	var ok := 0
	var spots := OS.get_environment("SPOTS").split(";")
	for s in spots:
		var target := map.nav_snap(_v(s))
		tm.call(&"_clear_torches")
		tm.call(&"_add_torch", bot)
		player.global_position = target + Vector3.UP * 0.3
		player.velocity = Vector3.ZERO
		player.freeze(200.0)
		bot.global_position = start + Vector3.UP * 0.3
		bot.velocity = Vector3.ZERO
		bot.get_node(^"Brain").set(&"force_target", player)
		var got := -1.0
		for i in 60 * 120:
			await physics_frame
			if tm.is_torch(player): got = i / 120.0; break
		if got >= 0.0: ok += 1
		print("%s %s: %s" % ["OK  " if got >= 0.0 else "FAIL", target.snapped(Vector3.ONE * 0.1), "%.1f s" % got if got >= 0.0 else "bot ended %s" % bot.global_position.snapped(Vector3.ONE * 0.1)])
		tm.call(&"_clear_torches")
		player.global_position = Vector3(0, 300, 0)
		await create_timer(0.3).timeout
	print("reached %d / %d" % [ok, spots.size()])
	quit()
