extends SceneTree
# Inferno: nobody can camp on a wall top. The player is dropped (Hunted, 7 bots) on the wall tops
# (there are no invisible lids any more: standing on one burns you, then puts you back at a
# checkpoint with a penalty); after 3 s it must be off the top, and it must have been set alight on
# the way and charged the map's penalty. Prints one line per spot and `walltops: N / N cleared`.
#   MAPI=3 timeout 300 godot --headless --fixed-fps 120 -s res://tools/checks/walltops.gd
var _main: Node
const WALL_TOP := 30.0


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _spots() -> Array[Vector3]:
	# [x, y, z]: the pad corridor's wall top of each hall and the pit's door walls, a few across and
	# along it, and (100 m up, where the lids used to be) a drop onto whatever is below
	var out: Array[Vector3] = []
	for u: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]:
		var tangent := Vector3(-u.z, 0.0, u.x)
		for r: float in [45.5, 88.5]:
			for o: float in [0.0, 5.0, -5.0, 7.5]: out.append(u * r + tangent * o + Vector3.UP * (WALL_TOP + 1.0))
			for c: float in [0.7, -0.7]: out.append(u * (r + c) + Vector3.UP * (WALL_TOP + 1.0))
		out.append(u * 45.5 + tangent * 20.0 + Vector3.UP * 101.5)   # a lid's top
		out.append(u * 88.5 + tangent * 30.0 + Vector3.UP * 101.5)
	for k: int in 4: # the pit's diagonal walls: lid on top
		var a := PI * 0.25 + k * PI * 0.5
		out.append(Vector3(cos(a), 0.0, sin(a)) * 45.5 + Vector3.UP * 101.5)
	return out


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 2, 7, 1, int(OS.get_environment("MAPI") if OS.get_environment("MAPI") != "" else "3"))
	var tm: TagManager = _main.tag_manager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var player: Character = _main.get(&"_player")
	await create_timer(1.0).timeout
	print("player state %d frozen %s" % [player.get_state(), player.has_method(&"is_frozen") and player.call(&"is_frozen")])
	var cleared := 0
	var spots := _spots()
	var penalised := 0
	for s: Vector3 in spots:
		var before := tm.get_torch_time(player)
		player.teleport(s)
		player.velocity = Vector3.ZERO
		var landed := -1.0
		var stood := 0
		for i in 120 * 5:
			await physics_frame
			if OS.get_environment("TRACE") != "" and i % 30 == 0: print("   t %.2f pos %s vel %s state %d floor %s" % [i / 120.0, player.global_position.snapped(Vector3.ONE * 0.1), player.velocity.snapped(Vector3.ONE * 0.1), player.get_state(), player.is_on_floor()])
			if landed < 0.0 and player.is_on_floor() and player.global_position.y > 26.0: landed = i / 120.0
			if i >= 120 * 4 and player.is_on_floor() and player.global_position.y > 26.0: stood += 1
		var y := player.global_position.y
		var gm := _main.get(&"_map") as GameMap
		var charged := tm.get_torch_time(player) - before >= gm.stand_penalty_time - 0.01
		if landed >= 0.0 and charged: penalised += 1
		var ok := stood == 0 and (landed < 0.0 or charged)
		if ok: cleared += 1
		print("%s %s landed %s, after 5 s y %.1f, on floor %s" % ["ok  " if ok else "STAY", s.snapped(Vector3.ONE * 0.1), "%.2f s" % landed if landed >= 0.0 else "never", y, player.is_on_floor()])
	print("walltops: %d / %d cleared (%d charged the penalty)" % [cleared, spots.size(), penalised])
	quit()
