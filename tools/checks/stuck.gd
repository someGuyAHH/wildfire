extends SceneTree
# Classic with 9 bots for ~2 min (player parked out of play): who stays within 2.5 m for 10 s?
# Also counts lava falls.
#   MAPI=3 godot --headless --fixed-fps 120 -s res://tools/checks/stuck.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", int(OS.get_environment("MODE")) if OS.get_environment("MODE") != "" else 0, 9, 2, int(OS.get_environment("MAPI")))
	var map := _main.get(&"_map") as GameMap
	var rid := map.get_world_3d().navigation_map
	while not NavigationServer3D.map_get_closest_point_owner(rid, map.arena_center + Vector3.UP * 2.0).is_valid(): await physics_frame
	var player: Character = _main.get(&"_player")
	var hist := {}
	var stuck := {}
	var falls := 0
	var low := {}
	var last_floor := {}
	for step in 240:
		for i in 60:
			player.global_position = Vector3(0, 300, 0)
			player.velocity = Vector3.ZERO
			await physics_frame
			for c: Character in _main.get(&"_participants"):
				var under := c.is_slowed() # a lava respawn slows you: count those (the crypt floor is low but dry)
				if c.is_on_floor(): last_floor[c] = [c.global_position, c.get_node(^"Brain").call(&"_active_link") if c.has_node(^"Brain") else -1, c.velocity.length()]
				if under and not low.get(c, false):
					falls += 1
					if OS.get_environment("WHY") != "" and last_floor.has(c): print("  fell: last on floor at %s, link %d, speed %.0f" % [(last_floor[c][0] as Vector3).snapped(Vector3.ONE * 0.1), last_floor[c][1], last_floor[c][2]])
				low[c] = under
		for c: Character in _main.get(&"_participants"):
			if c == player: continue
			var h: Array = hist.get(c, [])
			h.append(c.global_position)
			if h.size() > 20: h.pop_front()
			hist[c] = h
			if h.size() == 20 and not c.is_frozen():
				var far := 0.0
				for p: Vector3 in h: far = maxf(far, Vector2(p.x - h[0].x, p.z - h[0].z).length())
				if far < 2.5 and not stuck.has(c):
					stuck[c] = true
					print("STUCK %s at %s (t=%.0f s) link %d\n    %s" % [c.display_name, c.global_position.snapped(Vector3.ONE * 0.1), step * 0.5, c.get_node(^"Brain").call(&"_active_link"), (c.get_node(^"Brain").call(&"debug_text") as String).replace("\n", " | ")])
	print("done: %d bots stuck, %d lava falls" % [stuck.size(), falls])
	quit()
