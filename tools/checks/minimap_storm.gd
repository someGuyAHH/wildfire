extends SceneTree
# The minimap's storm fill, headless: with the storm centre and radius set to cases (safe circle
# covering the whole view, partly overlapping, fully outside), and the view turned several ways,
# whether points on the minimap count as under the purple. Also that the fill node shows only in a storm.
#   timeout 300 godot --headless --fixed-fps 120 -s res://tools/checks/minimap_storm.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(1.0).timeout
	var ok := true
	_main.call(&"_start_match", 3, 3, 1, 1)
	var tm := _main.get(&"tag_manager") as TagManager
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	for i: int in 10: await process_frame
	var mini: Minimap = root.find_children("*", "Minimap", true, false)[0]
	var shown: bool = mini._storm.visible
	print("fill node visible in a storm match: %s" % shown)
	if not shown: ok = false
	var pp := mini.player.global_position
	var pxz := Vector2(pp.x, pp.z)
	var mid := Vector2.ONE * Minimap.RADIUS
	var rim_r := Minimap.RADIUS - 4.0
	# [name, storm centre offset from you in m (xz), radius m, middle under purple, [rim points under purple]]
	var cases := [
		["covers the view", Vector2(0, 0), 300.0, false],
		["partly overlapping", Vector2(-60, 0), 70.0, null],
		["fully outside", Vector2(500, 0), 50.0, true],
	]
	for turn: float in [0.0, 1.0, 2.5, -1.7]:
		var view := [pxz, Vector2.UP.rotated(turn)]
		for cs: Array in cases:
			tm._storm_center = Vector3(pxz.x + (cs[1] as Vector2).x, pp.y, pxz.y + (cs[1] as Vector2).y)
			tm._storm_radius = cs[2]
			var circle := mini.storm_circle_px(view)
			var n_in := 0
			for k: int in 16: # points round the rim of the disc
				if Minimap.in_storm(mid + Vector2.RIGHT.rotated(TAU * k / 16.0) * rim_r, circle): n_in += 1
			var m_in := Minimap.in_storm(mid, circle)
			var good := true
			match cs[0]:
				"covers the view": good = not m_in and n_in == 0
				"fully outside": good = m_in and n_in == 16
				_: good = n_in > 0 and n_in < 16 # the boundary crosses the disc; you are inside it
			if cs[0] == "partly overlapping" and m_in: good = false
			# a point just either side of the edge, on the line from the circle's centre
			var c: Vector2 = circle[0]
			var rpx: float = circle[1]
			var dir := Vector2.RIGHT.rotated(turn)
			if Minimap.in_storm(c + dir * (rpx - 2.0), circle) or not Minimap.in_storm(c + dir * (rpx + 2.0), circle): good = false
			print("%s, view turned %.1f: middle %s, rim points purple %d/16 -> %s" % [cs[0], turn, m_in, n_in, "ok" if good else "WRONG"])
			if not good: ok = false
	# the same world circle lands elsewhere in px when the view turns, with the same px radius
	tm._storm_center = Vector3(pxz.x + 30.0, pp.y, pxz.y)
	tm._storm_radius = 20.0
	var a: Array = mini.storm_circle_px([pxz, Vector2.UP])
	var b: Array = mini.storm_circle_px([pxz, Vector2.RIGHT])
	var moved: bool = (a[0] as Vector2).distance_to(b[0]) > 1.0 and absf(float(a[1]) - float(b[1])) < 0.01
	print("circle follows the turned view: %s" % ("ok" if moved else "NO"))
	if not moved: ok = false
	print("MINIMAP_STORM: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
