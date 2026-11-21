extends SceneTree
# Inferno: nobody can camp on a wall top. The player is dropped (Hunted, 7 bots) on the pit's wall
# tops and the halls' inner-end wall tops; after 3 s it must be off the top (slid off, or
# put back after the lava). Prints one line per spot and `walltops: N / N cleared`.
#   MAPI=3 timeout 300 godot --headless --fixed-fps 120 -s res://tools/checks/walltops.gd
# (The side and outer walls have an invisible lid over them: nothing can reach those tops.)
var _main: Node
const WALL_TOP := 30.0


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _spots() -> Array[Vector3]:
	# [x, y, z]: the pad corridor's wall top of each hall and the pit's door walls (the only open
	# tops), a few across and along it, and the lids' own tops (100 m: nobody can get there, but
	# a character on one is still put back)
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
	for s: Vector3 in spots:
		player.teleport(s)
		player.velocity = Vector3.ZERO
		var landed := -1.0
		var stood := 0
		for i in 120 * 3:
			await physics_frame
			if OS.get_environment("TRACE") != "" and i % 30 == 0: print("   t %.2f pos %s vel %s state %d floor %s" % [i / 120.0, player.global_position.snapped(Vector3.ONE * 0.1), player.velocity.snapped(Vector3.ONE * 0.1), player.get_state(), player.is_on_floor()])
			if landed < 0.0 and player.is_on_floor() and player.global_position.y > 26.0: landed = i / 120.0
			if i >= 120 * 2 + 60 and player.is_on_floor() and player.global_position.y > 26.0: stood += 1
		var y := player.global_position.y
		var ok := stood == 0
		if ok: cleared += 1
		print("%s %s landed %s, after 3 s y %.1f, on floor %s" % ["ok  " if ok else "STAY", s.snapped(Vector3.ONE * 0.1), "%.2f s" % landed if landed >= 0.0 else "never", y, player.is_on_floor()])
	print("walltops: %d / %d cleared" % [cleared, spots.size()])
	quit()
