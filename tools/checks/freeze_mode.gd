extends SceneTree
# Freeze mode and hunter's sense, headless (--fixed-fps 120). Prints "freeze mode: ok".
#   MAPI=1 timeout 400 godot --headless --fixed-fps 120 -s res://tools/checks/freeze_mode.gd
# 1. rules: a Torch's touch freezes a runner solid (and they stay frozen), a free runner standing by
#    melts them in thaw_time, the thawed one can't be frozen again at once, a Torch touching a thawed
#    runner during its immunity does nothing;
# 2. the round ends when the last runner freezes (Torches win) and the standings use the Freeze score;
# 3. hunter's sense (Classic): after hunter_sense_after s without a touch the nearest runner is shown;
# 4. a bot soak: the player parked, 7 bots, a full round: the bots freeze and thaw each other.
var _main: Node
var _fails := 0


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok: return
	_fails += 1
	print("FAIL: ", what)


func _wait(seconds: float) -> void:
	for i: int in roundi(seconds * 120.0): await physics_frame


# everyone not in `keep` parked far away and still
func _park(chars: Array[Character], keep: Array[Character]) -> void:
	for i: int in chars.size():
		if chars[i] in keep: continue
		chars[i].global_position = Vector3(i * 3.0, 300.0, 0.0) # (high up, inside the arena: Main puts back anyone outside it)
		chars[i].velocity = Vector3.ZERO


func _run() -> void:
	await create_timer(1.0).timeout
	var mapi := int(OS.get_environment("MAPI")) if OS.get_environment("MAPI") != "" else 1
	_main.call(&"_start_match", 4, 5, 1, mapi)
	var tm: TagManager = _main.tag_manager
	var all: Array[Character] = tm.get_participants()
	_check(tm.rules.mode == MatchRules.MODE_FREEZE, "the match is in Freeze mode")
	tm.start_round()
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	_check(tm.get_torches().size() == 1, "6 players: one Torch (got %d)" % tm.get_torches().size())
	var torch := tm.get_torch()
	var runners: Array[Character] = []
	for c: Character in all: if c != torch: runners.append(c)
	# --- 1. rules
	torch.thaw() # (its head-start freeze)
	await _wait(0.1) # (so it stands up)
	# no brains, no input: only the rules. Everyone but the Torch stops outright; the Torch keeps ticking
	# (its recoil after a freeze has to lift) with its brain or input off
	for c: Character in all:
		if c != torch: c.process_mode = Node.PROCESS_MODE_DISABLED
	torch.get_node(^"Brain" if torch.has_node(^"Brain") else ^"Input").process_mode = Node.PROCESS_MODE_DISABLED
	torch.intent.set_wish(Vector3.ZERO) # (its last wish would keep it walking off)
	var floor_y := torch.global_position.y
	var a := runners[0]
	var b := runners[1]
	_park(all, [torch, a, b])
	torch.global_position = Vector3(0.0, floor_y, 0.0)
	a.global_position = Vector3(0.5, floor_y, 0.0)
	b.global_position = Vector3(40.0, floor_y, 0.0)
	await _wait(0.3)
	_check(tm.is_iced(a), "the Torch's touch froze runner a")
	_check(not tm.is_torch(a), "a frozen runner is still a runner")
	_check(a.is_frozen(), "the frozen runner can't move")
	_check(tm.free_runner_count() == runners.size() - 1, "one runner fewer is free")
	await _wait(3.0) # (also lets the Torch's recoil lift)
	_check(tm.is_iced(a), "with nobody near, the ice holds")
	b.global_position = a.global_position + Vector3(1.0, 0.0, 0.0)
	torch.global_position = Vector3(60.0, floor_y, 0.0)
	await _wait(tm.rules.thaw_time * 0.6)
	_check(tm.is_iced(a) and tm.get_thaw_progress(a) > 0.3, "a free runner standing by builds the thaw (%.2f)" % tm.get_thaw_progress(a))
	_check(tm.get_helping_progress(b) > 0.3, "...and the helper's own progress shows (%.2f), for the vignette" % tm.get_helping_progress(b))
	await _wait(tm.rules.thaw_time * 0.6)
	_check(not tm.is_iced(a), "...and melts them")
	_check(tm.get_thaws(b) == 1, "the helper is credited with the thaw")
	torch.global_position = a.global_position + Vector3(0.5, 0.0, 0.0)
	b.global_position = Vector3(40.0, floor_y, 0.0)
	await _wait(0.3)
	_check(not tm.is_iced(a), "just thawed: can't be frozen again at once")
	await _wait(tm.rules.thaw_immunity + 0.3)
	_check(tm.is_iced(a), "after the immunity, frozen again")
	# no shoving your own side: two runners (or two Torches) slamming into each other do nothing
	_check(tm.are_teammates(runners[0], runners[1]), "two runners are teammates")
	_check(not tm.are_teammates(runners[0], torch), "a runner and the Torch are not")
	# --- 2. the round ends when the last runner freezes
	for r: Character in runners:
		if tm.is_iced(r): continue
		torch.global_position = r.global_position + Vector3(0.4, 0.0, 0.0)
		await _wait(0.6)
	await _wait(0.3)
	_check(tm.get_phase() == TagManager.PHASE_RESULTS, "every runner frozen: the round is over")
	_check(not tm.runners_won(), "the Torches won")
	var top := tm.get_standings()[0]
	_check(top == torch or tm.get_score(top) >= tm.get_score(tm.get_standings()[-1]), "standings sorted by the Freeze score")
	for c: Character in all: c.process_mode = Node.PROCESS_MODE_INHERIT
	torch.get_node(^"Brain" if torch.has_node(^"Brain") else ^"Input").process_mode = Node.PROCESS_MODE_INHERIT
	await _wait(0.2)
	_check(not a.is_frozen(), "everyone moves again at the results")
	# --- 3. hunter's sense (Classic)
	_main.call(&"_start_match", 0, 5, 1, mapi)
	tm = _main.tag_manager
	all = tm.get_participants()
	tm.rules = tm.rules.duplicate() # (parked characters would "hide" and catch fire: switch that off for this test)
	tm.rules.still_time = 9999.0
	tm.start_round()
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	torch = tm.get_torch()
	var near: Character
	for c: Character in all: if c != torch: near = c; break
	for c: Character in all: if c != torch: c.process_mode = Node.PROCESS_MODE_DISABLED
	_park(all, [torch, near])
	torch.global_position = Vector3(0.0, torch.global_position.y, 0.0)
	near.global_position = Vector3(20.0, torch.global_position.y, 0.0)
	torch.get_node(^"Brain").process_mode = Node.PROCESS_MODE_DISABLED # (so it doesn't walk off and touch anyone)
	torch.thaw() # its head-start freeze
	await _wait(0.1)
	torch.process_mode = Node.PROCESS_MODE_DISABLED
	_check(tm.get_torch() == torch, "the Torch is still the same one")
	_check(tm.get_revealed() == null, "nobody revealed at first")
	await _wait(tm.rules.hunter_sense_after - 1.0)
	_check(tm.get_revealed() == null, "still nobody just before it")
	await _wait(2.0)
	_check(tm.get_revealed() == near, "after %.0f s with no touch, the nearest runner shows" % tm.rules.hunter_sense_after)
	await _wait(tm.rules.hunter_sense_time + 0.5)
	_check(tm.get_revealed() == null, "the reveal ends")
	# --- 4. bot soak
	_main.call(&"_start_match", 4, 11, 3, mapi)
	tm = _main.tag_manager
	all = tm.get_participants()
	var map := _main.get(&"_map") as GameMap
	var rid := map.get_world_3d().navigation_map
	while not NavigationServer3D.map_get_closest_point_owner(rid, map.arena_center + Vector3.UP * 2.0).is_valid(): await physics_frame
	var player: Character = _main.get(&"_player")
	var froze := [0]
	var melted := [0]
	var planned := [0]
	var doubled := [0]
	tm.tagged.connect(func(_t: Character, _v: Character) -> void: froze[0] += 1)
	tm.thawed.connect(func(_t: Character, _v: Character) -> void: melted[0] += 1)
	tm.start_round()
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	for s: int in 180:
		for i: int in 120:
			player.global_position = Vector3(0.0, 300.0, 0.0)
			player.velocity = Vector3.ZERO
			await physics_frame
		# the thaw plan: while more than one runner is frozen, no two helpers share a target, unless
		# there are more helpers than frozen runners
		var plan: Dictionary = tm.get_thaw_assignment()
		var frozen := 0
		for c: Character in all: if tm.is_iced(c): frozen += 1
		var targets := {}
		for h: Variant in plan: targets[plan[h]] = true
		if frozen > 0 and not plan.is_empty():
			planned[0] += 1
			if targets.size() < mini(frozen, plan.size()): doubled[0] += 1
		if tm.get_phase() != TagManager.PHASE_PLAYING: break
	print("soak (11 bots): %d freezes, %d thaws, round %s" % [froze[0], melted[0],
			"over" if tm.get_phase() != TagManager.PHASE_PLAYING else "still on at the buzzer"])
	_check(froze[0] > 0, "the bot Torches froze someone")
	_check(melted[0] > 0, "the bot runners melted someone")
	print("thaw plan: %d samples, %d with two helpers on one frozen runner while another waited" % [planned[0], doubled[0]])
	_check(doubled[0] == 0, "no two helpers share a frozen runner while another is left")
	print("freeze mode: ", "ok" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)
