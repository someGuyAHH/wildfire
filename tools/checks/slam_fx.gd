extends SceneTree
# Slam-jump impact effects (SlamFx): sizes grow with the slam's height and stop at the cap, the pool is reused
# (no nodes made per slam), and a burst of bot slams never shows more than the pool's decals and impacts.
#   MAPI=3 timeout 300 godot --headless --fixed-fps 120 -s res://tools/checks/slam_fx.gd
# Headless draws nothing: this checks the numbers each impact is played with, not how it looks.
# Prints "slam_fx: ok" or the problems, and exits 1 on any.
var _main: Node
var _problems: Array[String] = []


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _fail(msg: String) -> void:
	_problems.append(msg)
	print("PROBLEM: ", msg)


func _sec(t: float) -> void:
	for i in int(t * 120.0): await physics_frame


func _run() -> void:
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 9, 1, int(OS.get_environment("MAPI")))
	var tm: TagManager = _main.tag_manager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	var fx: SlamFx = _main.get(&"_slam_fx")
	var player: Character = _main.get(&"_player")
	player.get_node(^"Input").process_mode = Node.PROCESS_MODE_DISABLED
	tm.untaggable = player
	await _sec(0.5)
	if not player.is_on_floor(): await _sec(1.0)
	var cfg := fx.config
	var ids := fx.node_ids()
	var children := _count_nodes(fx)
	var stg := root.get_node("STG")

	# 1: one slam-jump of the player's at intensity 0, 0.5, 1, and past the top (clamped)
	var mc := player.config
	var got: Array[Dictionary] = []
	var shakes: Array[float] = []
	for i: float in [0.0, 0.5, 1.0, 1.6]:
		var h := lerpf(mc.slam_bounce_base_height, mc.slam_bounce_max_height, i)
		player.velocity.y = sqrt(2.0 * mc.gravity * h)
		var before := fx.played
		player.jumped.emit(Character.JUMP_SLAM_BOUNCE)
		if fx.played != before + 1:
			_fail("intensity %.1f: no impact played" % i)
			continue
		var idx := _newest(fx)
		var d := fx.describe(idx)
		got.append(d)
		shakes.append(fx.last_shake)
		print("intensity %.1f: response %.2f, cracks r %.2f m (pattern %d), shock r %.2f m, embers %.2f, dust %.2f x%.2f, linger %.2f, debris %.2f, shake %.2f" % [
			i, d.amount, d.crack_radius, d.crack_level, d.shock_radius, d.ember, d.dust, d.dust_size, d.linger, d.debris, fx.last_shake])
		if (d.up as Vector3).dot(Vector3.UP) < 0.5: _fail("intensity %.1f: decal not lying on the ground (up %s)" % [i, d.up])
		await _sec(0.05)
	if got.size() == 4:
		for k: String in ["crack_radius", "shock_radius", "dust", "dust_size", "dust_speed"]:
			if not (got[0][k] < got[1][k] and got[1][k] < got[2][k]): _fail("%s doesn't grow 0 < 0.5 < 1: %s %s %s" % [k, got[0][k], got[1][k], got[2][k]])
		for k: String in ["linger", "debris", "ember", "crack_level"]:
			if not (got[0][k] <= got[1][k] and got[1][k] <= got[2][k] and got[2][k] > got[0][k]): _fail("%s doesn't grow: %s %s %s" % [k, got[0][k], got[1][k], got[2][k]])
		if got[0].debris > 0.0: _fail("debris at intensity 0")
		if got[0].ember > 0.0: _fail("embers at intensity 0")
		if not (shakes[0] < shakes[1] and shakes[1] < shakes[2]): _fail("shake doesn't grow: %s" % [shakes])
		for k: String in ["amount", "crack_radius", "shock_radius", "dust", "dust_size", "linger", "debris", "ember"]:
			if absf(float(got[3][k]) - float(got[2][k])) > 0.0001: _fail("past the top (1.6) %s is %s, not capped at %s" % [k, got[3][k], got[2][k]])
		if got[2].crack_radius > cfg.crack_radius_max + 0.001: _fail("crack radius over the cap")
		if got[2].shock_radius > cfg.shock_radius_max + 0.001: _fail("shock radius over the cap")
		if got[2].dust > 1.0 or got[2].debris > 1.0: _fail("particle share over 1")
	var rig: Object = _main.call(&"_player_rig")
	if rig.call(&"get_trauma") <= 0.0: _fail("the player's camera didn't shake")

	# camera shake off in the settings: no shake (save=false: the real settings file isn't touched)
	var shake_was: float = stg.call(&"get_value", &"camera_shake")
	stg.call(&"set_value", &"camera_shake", 0.0, false)
	await _sec(2.0)
	player.velocity.y = sqrt(2.0 * mc.gravity * mc.slam_bounce_max_height)
	player.jumped.emit(Character.JUMP_SLAM_BOUNCE)
	if rig.call(&"get_trauma") > 0.0: _fail("camera shake Off still shook")
	stg.call(&"set_value", &"camera_shake", shake_was, false)

	# 2: a burst: every bot slam-jumps at the top, twice over, a few ticks apart
	var bots: Array[Character] = []
	for c: Character in _main.get(&"_participants"): if c != player: bots.append(c)
	var peak_decals := 0
	var peak_active := 0
	var shown := 0
	for round_i in 2:
		for b: Character in bots:
			b.global_position = player.global_position + Vector3(randf_range(-6, 6), 0.0, randf_range(-6, 6))
			b.velocity.y = sqrt(2.0 * b.config.slam_bounce_max_height * b.config.gravity)
			var before := fx.played
			b.jumped.emit(Character.JUMP_SLAM_BOUNCE)
			shown += fx.played - before
			peak_decals = maxi(peak_decals, fx.visible_decals())
			peak_active = maxi(peak_active, fx.active_count())
			await physics_frame
	print("burst: %d bot slams, %d shown, peak %d impacts / %d decals (pool %d), %d taken over" % [
		bots.size() * 2, shown, peak_active, peak_decals, fx.pool_size(), fx.taken_over])
	if peak_active > cfg.pool_size: _fail("more impacts at once than the pool (%d > %d)" % [peak_active, cfg.pool_size])
	if peak_decals > cfg.pool_size * 2: _fail("more decals than the cap (%d > %d)" % [peak_decals, cfg.pool_size * 2])
	if fx.taken_over == 0: _fail("the burst never took over an impact (pool too big for the test?)")

	# 3: a bot far off isn't shown at all
	var far := bots[0]
	far.global_position = player.global_position + Vector3(cfg.cull_distance + 40.0, 0.0, 0.0)
	var culled := fx.culled
	far.velocity.y = sqrt(2.0 * far.config.slam_bounce_max_height * far.config.gravity)
	far.jumped.emit(Character.JUMP_SLAM_BOUNCE)
	if fx.culled != culled + 1: _fail("a slam %.0f m from the camera wasn't culled" % (cfg.cull_distance + 40.0))

	# 4: same nodes all along
	if fx.node_ids() != ids: _fail("the pool's nodes changed (made or freed per slam)")
	if _count_nodes(fx) != children: _fail("SlamFx has %d nodes, had %d" % [_count_nodes(fx), children])

	# 5: it all fades and switches off
	await _sec(cfg.crack_hold + cfg.crack_fade + 3.2)
	if fx.active_count() != 0 or fx.visible_decals() != 0: _fail("still %d impacts / %d decals after they should have faded" % [fx.active_count(), fx.visible_decals()])
	if fx.is_processing(): _fail("still processing with nothing to show")

	if _problems.is_empty():
		print("slam_fx: ok (pool %d, %d played, %d culled)" % [fx.pool_size(), fx.played, fx.culled])
		quit()
	else:
		print("slam_fx: %d problems" % _problems.size())
		quit(1)


func _newest(fx: SlamFx) -> int:
	var best := -1
	var best_started := -1
	var impacts: Array = fx.get(&"_impacts")
	for i in impacts.size():
		if impacts[i].active and impacts[i].started > best_started:
			best_started = impacts[i].started
			best = i
	return best


func _count_nodes(n: Node) -> int:
	var k := 1
	for c in n.get_children(): k += _count_nodes(c)
	return k
