extends SceneTree
# [DEBUG] cheats: no-tag (a Torch on you can't light you), alone (bots gone and back), fly
# (through a wall), freeze (bots and the clock stop).
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 3, 1, 0)
	var tm: TagManager = _main.tag_manager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var player: Character = _main.get(&"_player")
	player.get_node(^"Input").process_mode = Node.PROCESS_MODE_DISABLED
	var bots: Array = (_main.get(&"_participants") as Array).filter(func(c): return c != player)
	_main.call(&"toggle_cheat", &"no_tag")
	tm.call(&"_clear_torches")
	tm.call(&"_add_torch", bots[0])
	(bots[0] as Character).global_position = player.global_position
	for i in 30: await physics_frame
	print("no-tag: Torch on top of you, you lit: %s" % tm.is_torch(player))
	var before: Vector3 = (bots[1] as Character).global_position
	_main.call(&"toggle_cheat", &"alone")
	await physics_frame
	print("alone: bot visible %s, lifted %.0f m" % [(bots[1] as Character).visible, (bots[1] as Character).global_position.y - before.y])
	_main.call(&"toggle_cheat", &"alone")
	await physics_frame
	print("alone off: bot back where it was: %s (%.2f m off)" % [(bots[1] as Character).global_position.distance_to(before) < 0.5, (bots[1] as Character).global_position.distance_to(before)])
	_main.call(&"toggle_cheat", &"fly")
	var p0 := player.global_position
	for i in 120:
		player.intent.jump_held = true
		await physics_frame
	print("fly: rose %.1f m in 1 s holding jump" % (player.global_position.y - p0.y))
	_main.call(&"toggle_cheat", &"fly")
	_main.call(&"toggle_cheat", &"freeze")
	var t0 := tm.get(&"_elapsed") as float
	var b0 := (bots[2] as Character).global_position
	await create_timer(1.0).timeout
	print("freeze: clock moved %.2f s, bot moved %.2f m" % [(tm.get(&"_elapsed") as float) - t0, (bots[2] as Character).global_position.distance_to(b0)])
	print("label: %s" % (_main.get(&"_cheat_label") as Label).text)
	quit()
