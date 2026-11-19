extends SceneTree
# Where bots spend a match: Classic, 8 bots, the player standing idle at spawn, for
# SECONDS of game time; every 2 s each bot's distance from the arena centre. Prints the spread
# (median, 90th percentile, share past half the arena radius) and how many clusters (the map's
# "poi" group) had a bot within 15 m at some point. MAPI picks the map (default 1, the Overworld).
#   MAPI=1 SECONDS=120 timeout 600 godot --headless --fixed-fps 120 -s res://tools/checks/bot_spread.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(1.0).timeout
	var mapi := int(OS.get_environment("MAPI")) if OS.get_environment("MAPI") != "" else 1
	var seconds := float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 120.0
	_main.call(&"_start_match", 0, 8, 1, mapi)
	var tm := _main.get(&"tag_manager") as TagManager
	var map := tm.map
	var me := _main.get(&"_player") as Character
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var pois := get_nodes_in_group(&"poi")
	var visited := {}
	var d: Array[float] = []
	var t := 0.0
	while t < seconds:
		for i: int in 240: await physics_frame
		t += 2.0
		for c: Character in tm.get_participants():
			if c == me: continue
			var off := c.global_position - map.arena_center
			d.append(Vector2(off.x, off.z).length())
			for p: Node in pois:
				var q := (p as Node3D).global_position - c.global_position
				if Vector2(q.x, q.z).length() < 15.0: visited[p] = true
	d.sort()
	var past_half := d.filter(func(x: float) -> bool: return x > map.arena_radius * 0.5).size()
	print("bots over %.0f s on map %d (arena r %.0f): median %.0f m from the centre, 90%% within %.0f m, %.0f%% of samples past half the radius; clusters visited %d / %d" % [
			seconds, mapi, map.arena_radius, d[d.size() / 2], d[int(d.size() * 0.9)], 100.0 * past_half / d.size(), visited.size(), pois.size()])
	quit()
