extends SceneTree
# Spread with 11 bots (the player parked out of play): how many Torches after 30, 60, 90 s?
#   MAPI=3 godot --headless --fixed-fps 120 -s res://tools/checks/spread.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 1, 11, 3, int(OS.get_environment("MAPI")))
	var map := _main.get(&"_map") as GameMap
	var rid := map.get_world_3d().navigation_map
	while not NavigationServer3D.map_get_closest_point_owner(rid, map.arena_center + Vector3.UP * 2.0).is_valid(): await physics_frame
	var tm: TagManager = _main.tag_manager
	tm.start_round()
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var player: Character = _main.get(&"_player")
	var line := []
	for s in 120:
		for i in 120:
			player.global_position = Vector3(0, 300, 0)
			player.velocity = Vector3.ZERO
			await physics_frame
		if (s + 1) % 15 == 0: line.append("%ds:%d" % [s + 1, tm.get_torches().size()])
		if tm.get_phase() != TagManager.PHASE_PLAYING: line.append("round over at %ds" % (s + 1)); break
	print("torches (of 11 bots): %s" % "  ".join(line))
	quit()
