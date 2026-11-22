extends SceneTree
# Freeze balance: full rounds with bots only (the player parked up high), mixed difficulty, printing
# per round how it ended (the Torches froze everyone at N s, or the runners held out), how many
# freezes and thaws, how often runners went for the Torch (snuff attempts: a bot starting its sneak-up
# and dash-shove; landed: a shove or stomp on a Torch), and the share of runners frozen at 30 / 60 / 90 s.
# Headless; takes minutes.
#   BOTS=7 ROUNDS=4 MAPI=1 timeout 1500 godot --headless --fixed-fps 120 -s res://tools/checks/freeze_balance.gd
# Rule overrides for trying numbers without editing the resource: RULES="thaw_time=1.0,freeze_players_per_torch=5"
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.get_environment(key) != "" else fallback


func _run() -> void:
	await create_timer(1.0).timeout
	var bots := int(_env("BOTS", "7"))
	var rounds := int(_env("ROUNDS", "4"))
	var mapi := int(_env("MAPI", "1"))
	_main.call(&"_start_match", 4, bots, 3, mapi)
	var tm: TagManager = _main.tag_manager
	tm.rules = tm.rules.duplicate()
	for kv: String in _env("RULES", "").split(",", false):
		tm.rules.set(StringName(kv.get_slice("=", 0)), float(kv.get_slice("=", 1)) if "." in kv.get_slice("=", 1) else int(kv.get_slice("=", 1)))
	var map := _main.get(&"_map") as GameMap
	var rid := map.get_world_3d().navigation_map
	while not NavigationServer3D.map_get_closest_point_owner(rid, map.arena_center + Vector3.UP * 2.0).is_valid(): await physics_frame
	var player: Character = _main.get(&"_player")
	var runner_wins := 0
	var total := 0.0
	for r: int in rounds:
		var froze := [0]
		var melted := [0]
		var f := func(_t: Character, _v: Character) -> void: froze[0] += 1
		var m := func(_t: Character, _v: Character) -> void: melted[0] += 1
		var snuffed := [0]
		var sn := func(_a: Character, v: Character) -> void: if tm.is_torch(v): snuffed[0] += 1
		tm.tagged.connect(f)
		tm.thawed.connect(m)
		tm.bumped.connect(sn)
		var tries := 0
		var was_on := {}
		tm.start_round()
		while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
		var torches := tm.get_torches().size() # (the results clear them: count now)
		var runners := tm.get_participants().size() - torches
		var shares: PackedStringArray = []
		var t := 0
		while tm.get_phase() == TagManager.PHASE_PLAYING:
			for i: int in 120:
				player.global_position = Vector3(0.0, 300.0, 0.0) # the player is a runner: parked, frozen by nothing
				player.velocity = Vector3.ZERO
				await physics_frame
				for c: Character in tm.get_participants(): # a snuff attempt starting (its timer was off)
					var brain := c.get_node_or_null(^"Brain")
					if not brain: continue
					var on: bool = float(brain.get(&"_snuff_timer")) > 0.0
					if on and not was_on.get(c, false): tries += 1
					was_on[c] = on
				if tm.get_phase() != TagManager.PHASE_PLAYING: break
			t += 1
			if t in [30, 60, 90, 120]:
				var iced := 0
				for c: Character in tm.get_participants(): if tm.is_iced(c): iced += 1
				shares.append("%ds:%d/%d" % [t, iced, runners])
		var won := tm.runners_won()
		if won: runner_wins += 1
		total += float(t)
		print("round %d: %s at ~%d s | %d Torch(es), %d runners | freezes %d, thaws %d | snuffs tried %d, landed %d | frozen %s" % [r + 1,
				"RUNNERS held out" if won else "Torches froze everyone", t, torches, runners, froze[0], melted[0],
				tries, snuffed[0], "  ".join(shares)])
		tm.tagged.disconnect(f)
		tm.thawed.disconnect(m)
		tm.bumped.disconnect(sn)
	print("freeze balance: runners won %d of %d, mean round %.0f s (round time %.0f s)" % [runner_wins, rounds, total / rounds, tm.rules.round_time])
	quit()
