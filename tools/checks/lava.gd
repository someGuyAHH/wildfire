extends SceneTree
# Inferno: the player drops into a hall's lava river: back at the nearest checkpoint, slowed?
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 2, 1, 3)
	var map := _main.get(&"_map") as GameMap
	var tm: TagManager = _main.tag_manager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var player: Character = _main.get(&"_player")
	var drop := Vector3(0.0, 2.0, -130.0) # the north hall's river
	player.teleport(drop)
	var back := Vector3.INF
	for i in 400:
		await physics_frame
		if player.global_position.y > -1.0 and player.global_position.distance_to(drop) > 3.0:
			back = player.global_position
			break
	var feed := ""
	var hud = _main.get(&"_hud")
	if hud: for l in hud.find_children("*", "Label", true, false): if "lava" in (l as Label).text: feed = (l as Label).text
	print("fell in at %s -> back at %s (%.1f m away), slowed %s, top speed now %.1f; feed: %s" % [drop, back.snapped(Vector3.ONE * 0.1), Vector2(back.x - drop.x, back.z - drop.z).length(), player.is_slowed(), player.config.max_speed * player.speed_mult * player.get(&"_slow_mult"), feed])
	await create_timer(2.2).timeout
	print("2.2 s later: slowed %s" % player.is_slowed())
	quit()
