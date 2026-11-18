extends SceneTree
# How long the dry edge and the storm take to punish you, with the player kept walking (so the
# smoke rule stays out of it): a 0.8 s step over the line should cost nothing (the grace), then
# the edge: seconds to smoldering, seconds to catching fire; the storm: seconds to burning out.
#   MAPI=1 timeout 200 godot --headless --fixed-fps 120 -s res://tools/checks/hazards.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


# walk the player round a circle of radius r (3 m/s), for `secs` or until done() says stop
func _walk(r: float, secs: float, done: Callable = Callable()) -> float:
	var map := _main.get(&"_map") as GameMap
	var p := _main.get(&"_player") as Character
	var t := 0.0
	while t < secs:
		var a := t * 3.0 / r
		var x := map.arena_center.x + cos(a) * r
		var z := map.arena_center.z + sin(a) * r
		p.global_position = Vector3(x, map.ground_height(x, z) + 1.0, z)
		p.velocity = Vector3.ZERO
		await physics_frame
		t += 1.0 / 120.0
		if done.is_valid() and done.call(): break
	return t


func _start(mode: int) -> void:
	_main.call(&"_start_match", mode, 3, 1, int(OS.get_environment("MAPI")))
	if not _main.get(&"_cheats")[&"alone"]: _main.call(&"toggle_cheat", &"alone") # nobody tags anyone
	var tm := _main.get(&"tag_manager") as TagManager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame


func _run() -> void:
	await create_timer(1.0).timeout
	var tm := _main.get(&"tag_manager") as TagManager
	await _start(2) # Hunted: the player starts as kindling
	var map := _main.get(&"_map") as GameMap
	var p := _main.get(&"_player") as Character
	var edge := map.get_dry_edge(tm.rules.edge_start)
	var bound := map.get_bound_radius()
	var out_r := (edge + bound) * 0.5
	await _walk(edge - 10.0, 2.0)
	await _walk(out_r, 0.8)
	await _walk(edge - 10.0, 0.1)
	print("dry edge: a 0.8 s step over the line -> heat %.2f" % tm.get_heat(p))
	await _walk(edge - 10.0, 3.0)
	var t_smolder: float = await _walk(out_r, 30.0, func() -> bool: return tm.is_smoldering(p))
	var t_fire: float = await _walk(out_r, 30.0, func() -> bool: return tm.is_torch(p))
	print("dry edge: smoldering after %.1f s out there, then on fire %.1f s later (%.1f s in all)" % [t_smolder, t_fire, t_smolder + t_fire])
	await _start(3) # Hot Potato: the storm starts at the arena radius
	p = _main.get(&"_player") as Character # a new match makes a new player
	map = _main.get(&"_map") as GameMap
	var storm_out := (map.arena_radius + bound) * 0.5
	var t_out: float = await _walk(storm_out, 30.0, func() -> bool: return tm.is_out(p))
	print("storm: burned out after %.1f s outside it" % t_out)
	quit()
