extends SceneTree
# The match setup's boxes (bots, map, difficulty, PLAY, carousel, arrows, header): after the build-in
# (and after a skip) each sits exactly at its laid-out rest rect (within 1 px) and, bar the full-screen
# carousel, inside the screen margin; while they fall off on leaving none is hidden or gone while any
# part of it is still on screen, and the last one is only cleared once it is fully below the screen.
#   godot --headless --fixed-fps 120 -s res://tools/checks/setup_boxes.gd -- 1920 1080
const _MARGIN := Vector2(96.0, 48.0) # the screen's side and top margins
var _fail := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var w := int(args[0]) if args.size() > 1 else 1920
	var h := int(args[1]) if args.size() > 1 else 1080
	# the view at this size (the project's base is 1920 x 1080 and only ever widens or lengthens from there)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _rects(pieces: Dictionary) -> Dictionary:
	var out := {}
	for key: StringName in pieces.keys(): out[key] = (pieces[key] as Control).get_global_rect()
	return out


func _compare(label: String, pieces: Dictionary, rest: Dictionary) -> void:
	var view := root.get_visible_rect()
	for key: StringName in pieces.keys():
		var r := (pieces[key] as Control).get_global_rect()
		var e: Rect2 = rest[key]
		var same: bool = r.position.distance_to(e.position) <= 1.0 and r.size.distance_to(e.size) <= 1.0
		var inside := key == &"wheel" or Rect2(view.position + _MARGIN - Vector2.ONE, view.size - _MARGIN * 2.0 + Vector2(2.0, 2.0)).encloses(r)
		if not same or not inside:
			_fail = true
			print("  FAIL ", label, " ", key, " ", r, " rest ", e, " same ", same, " inside margin ", inside)
	print(label, ": checked ", pieces.size(), " boxes")


func _run(main: Node) -> void:
	for i: int in 40: await process_frame
	var view := root.get_visible_rect()
	print("viewport ", view.size)
	var menu: Node = main.get(&"_menu")
	var pieces: Dictionary = menu.get(&"_pieces")
	var nodes: Array[Control] = []
	for key: StringName in pieces.keys(): nodes.append(pieces[key])
	# the laid-out rects: the setup shown without any animation
	menu.call(&"open", &"modes")
	for i: int in 30: await process_frame
	var rest := _rects(pieces)
	menu.call(&"show_screen", &"title")
	for i: int in 150: await process_frame
	# built in
	menu.call(&"show_screen", &"modes")
	for i: int in 90: await process_frame
	_compare("after build-in", pieces, rest)
	# falling: watch every frame
	menu.call(&"show_screen", &"title")
	var frames := 0
	var gone_early := false
	var last_all_below := false
	var last_blockers := {}
	while frames < 600:
		await process_frame
		frames += 1
		var modes_visible: bool = (menu.get(&"_screens") as Dictionary)[&"modes"].visible
		if not modes_visible:
			if not last_all_below:
				gone_early = true
				print("  FAIL setup screen hidden while a box was still on screen, frame ", frames, " ", last_blockers)
			break
		var all_below := true
		last_blockers.clear()
		for c: Control in nodes:
			if not is_instance_valid(c):
				gone_early = true
				continue
			var xf := c.get_global_transform()
			var top := INF
			for corner: Vector2 in [Vector2.ZERO, Vector2(c.size.x, 0.0), Vector2(0.0, c.size.y), c.size]: top = minf(top, (xf * corner).y)
			if top < view.end.y - 80.0: # (a frame of falling is under 80 px: the check sees the frame before the end)
				all_below = false
				last_blockers[c.name] = top
				if not c.is_visible_in_tree():
					gone_early = true
					print("  FAIL hidden while on screen: ", c.name, " at frame ", frames)
		last_all_below = all_below
	print("fall: ended after ", frames, " frames (", "%.2f" % (frames / 120.0), " s), cut early: ", gone_early)
	if gone_early or frames >= 600: _fail = true
	_compare("after fall (reset)", pieces, rest)
	# skip: a key press during the build-in
	menu.call(&"show_screen", &"modes")
	for i: int in 5: await process_frame
	var press := InputEventKey.new()
	press.keycode = KEY_SHIFT
	press.pressed = true
	menu.call(&"_input", press)
	_compare("after skip", pieces, rest)
	# skip during the fall
	menu.call(&"show_screen", &"title")
	for i: int in 10: await process_frame
	menu.call(&"_input", press)
	_compare("after skipped fall", pieces, rest)
	print("setup boxes ", view.size, ": ", "FAIL" if _fail else "OK")
	quit()
